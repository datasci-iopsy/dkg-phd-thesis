"""BigQuery data operations for survey response storage."""

import logging
from datetime import UTC, datetime

from google.cloud import bigquery
from models.qualtrics import WebServicePayload
from shared.utils.bq_schemas import SURVEY_RESPONSES_SCHEMA
from shared.utils.config_models import AppConfig

logger = logging.getLogger(__name__)

# -- BigQuery type -> proto2 type mapping ----------------------------
# Defined at module level because it is a pure data constant with
# no import dependencies on the storage package.
# Covers every type produced by generate_schema() in bq_schemas.py.
# TIMESTAMP maps to TYPE_STRING because the Storage Write API accepts
# ISO 8601 strings for TIMESTAMP columns.
_BQ_TO_PROTO_TYPE: dict[str, int] = {
    "STRING": 3,  # descriptor_pb2.FieldDescriptorProto.TYPE_STRING
    "INTEGER": 3,  # resolved at call time -- see _build_proto_descriptor
    "INT64": 3,
    "FLOAT": 1,
    "FLOAT64": 1,
    "BOOLEAN": 8,
    "BOOL": 8,
    "TIMESTAMP": 3,
}
# Note: the integer values above are placeholders. The actual mapping
# is resolved inside _build_proto_descriptor() where descriptor_pb2
# is imported lazily. The dict is kept here for documentation only.


def _build_insert_row(payload: WebServicePayload) -> dict:
    """Build the row dict for a BigQuery insert from a validated payload.

    Pure function: no I/O, no side effects, no external imports beyond
    datetime. Separated from the transport layer so row construction
    can be tested independently of the Storage Write API client.

    Column names are lowercased to match the BigQuery schema
    (PA1 -> pa1). System columns (_created_at, _processed) are
    added after the model-derived fields, matching SYSTEM_FIELDS
    in bq_schemas.py.

    _created_at is set to the current UTC time as an ISO 8601 string.
    _processed is always initialized to False.

    Args:
        payload: Validated survey response from the Qualtrics
            Web Service task.

    Returns:
        Dict of column names to values, ready for BigQuery insert.
    """
    row = {k.lower(): v for k, v in payload.model_dump().items()}
    row["_created_at"] = datetime.now(UTC).isoformat()
    row["_processed"] = False
    return row


def _build_proto_descriptor(schema: list[bigquery.SchemaField]):
    """Build a proto2 DescriptorProto from a BigQuery schema.

    Imported lazily to avoid loading protobuf at module import time,
    keeping the dev/test environment free of the storage package
    dependency.

    Args:
        schema: List of BigQuery SchemaField objects from bq_schemas.py.

    Returns:
        A DescriptorProto describing the proto2 message structure.

    Raises:
        ValueError: If a SchemaField type has no proto mapping.
    """
    from google.protobuf import descriptor_pb2  # lazy import

    BQ_TO_PROTO = {
        "STRING": descriptor_pb2.FieldDescriptorProto.TYPE_STRING,
        "INTEGER": descriptor_pb2.FieldDescriptorProto.TYPE_INT64,
        "INT64": descriptor_pb2.FieldDescriptorProto.TYPE_INT64,
        "FLOAT": descriptor_pb2.FieldDescriptorProto.TYPE_DOUBLE,
        "FLOAT64": descriptor_pb2.FieldDescriptorProto.TYPE_DOUBLE,
        "BOOLEAN": descriptor_pb2.FieldDescriptorProto.TYPE_BOOL,
        "BOOL": descriptor_pb2.FieldDescriptorProto.TYPE_BOOL,
        "TIMESTAMP": descriptor_pb2.FieldDescriptorProto.TYPE_STRING,
    }

    descriptor_proto = descriptor_pb2.DescriptorProto()
    descriptor_proto.name = "SurveyResponseRow"

    for i, field in enumerate(schema, start=1):
        proto_type = BQ_TO_PROTO.get(field.field_type)
        if proto_type is None:
            raise ValueError(
                f"No proto type mapping for BigQuery field '{field.name}' "
                f"with type '{field.field_type}'. Add an entry to "
                f"_build_proto_descriptor in gcp_utils.py."
            )
        f = descriptor_proto.field.add()
        f.name = field.name
        f.number = i
        f.label = descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL
        f.type = proto_type

    return descriptor_proto


def _build_proto_message_class(schema: list[bigquery.SchemaField]):
    """Build a proto2 message class from a BigQuery schema.

    Imported lazily to avoid loading protobuf at module import time.

    Args:
        schema: List of BigQuery SchemaField objects.

    Returns:
        A proto2 message class for SurveyResponseRow.
    """
    from google.protobuf import descriptor_pb2, descriptor_pool  # lazy import
    from google.protobuf.message_factory import GetMessageClass  # lazy import

    descriptor_proto = _build_proto_descriptor(schema)

    file_proto = descriptor_pb2.FileDescriptorProto()
    file_proto.name = "survey_response_row.proto"
    file_proto.syntax = "proto2"
    file_proto.message_type.add().CopyFrom(descriptor_proto)

    pool = descriptor_pool.DescriptorPool()
    pool.Add(file_proto)
    message_descriptor = pool.FindMessageTypeByName("SurveyResponseRow")
    return GetMessageClass(message_descriptor)


def get_bigquery_client(config: AppConfig) -> bigquery.Client:
    """Initialize a BigQuery client from application config.

    Args:
        config: Validated application configuration.

    Returns:
        Authenticated BigQuery client scoped to the project.
    """
    return bigquery.Client(project=config.gcp.project_id)


def insert_survey_response(
    payload: WebServicePayload,
    table_name: str,
    config: AppConfig,
) -> bool:
    """Insert a survey response into BigQuery via Storage Write API.

    Uses COMMITTED mode, which writes rows directly to permanent
    storage and bypasses the streaming buffer. This makes rows
    immediately available for DML (UPDATE/DELETE), resolving the
    conflict where update_processed_flag in run_intake_confirmation
    was blocked by the streaming buffer.

    The public interface (arguments, return type) is identical to
    the previous streaming implementation. No changes are needed
    in run_qualtrics_scheduling/main.py.

    Args:
        payload: Validated survey response from the Qualtrics
            Web Service task.
        table_name: Target BigQuery table name.
        config: Validated application configuration.

    Returns:
        True if the insert succeeded, False otherwise.
    """
    from google.cloud.bigquery_storage_v1 import BigQueryWriteClient  # lazy
    from google.cloud.bigquery_storage_v1.types import (  # lazy
        AppendRowsRequest,
        ProtoRows,
        ProtoSchema,
        WriteStream,
    )

    try:
        project = config.gcp.project_id
        dataset = config.bq.dataset_id

        row = _build_insert_row(payload)
        schema = SURVEY_RESPONSES_SCHEMA

        # Build the proto message class and serialize the row.
        msg_class = _build_proto_message_class(schema)
        msg = msg_class()
        for field in schema:
            value = row.get(field.name)
            if value is not None:
                try:
                    setattr(msg, field.name, value)
                except (AttributeError, ValueError) as exc:
                    logger.warning(
                        "Skipping field '%s': could not set value %r (%s)",
                        field.name,
                        value,
                        exc,
                    )

        proto_rows = ProtoRows(serialized_rows=[msg.SerializeToString()])

        # _build_proto_descriptor returns a raw descriptor_pb2.DescriptorProto.
        # ProtoSchema accepts it directly because DescriptorProto is a raw
        # protobuf type (not proto-plus), which the storage library handles.
        descriptor_proto = _build_proto_descriptor(schema)

        write_client = BigQueryWriteClient()
        parent = write_client.table_path(project, dataset, table_name)

        write_stream = write_client.create_write_stream(
            parent=parent,
            write_stream=WriteStream(type_=WriteStream.Type.COMMITTED),
        )
        stream_name = write_stream.name
        logger.info(
            "Storage Write API: created COMMITTED stream %s", stream_name
        )

        # proto-plus types are constructed with keyword arguments.
        # CopyFrom() is a raw protobuf method and does not exist on
        # proto-plus wrappers -- constructing directly is the correct pattern.
        append_request = AppendRowsRequest(
            write_stream=stream_name,
            proto_rows=AppendRowsRequest.ProtoData(
                writer_schema=ProtoSchema(proto_descriptor=descriptor_proto),
                rows=proto_rows,
            ),
        )

        responses = write_client.append_rows(iter([append_request]))
        for response in responses:
            if response.error.code != 0:
                logger.error(
                    "Storage Write API append error (code %d): %s",
                    response.error.code,
                    response.error.message,
                )
                return False

        write_client.finalize_write_stream(name=stream_name)

        full_table_id = f"{project}.{dataset}.{table_name}"
        logger.info(
            "Successfully committed response %s to %s",
            payload.response_id,
            full_table_id,
        )
        return True

    except Exception as e:
        logger.error(
            "Unexpected error writing to BigQuery: %s", e, exc_info=True
        )
        return False
