"""API Gateway lifecycle manager for Qualtrics webhook routing.

Provisions a GCP API Gateway that accepts POST requests with a
static API key (suitable for Qualtrics Web Service tasks) and
forwards them to a Cloud Run function with proper IAM
authentication.

Flow:
    Qualtrics -> POST with x-api-key header
    -> API Gateway validates key via Service Control
    -> Cloud Run function (JWT injected by gateway)

Resources created by 'setup':
    1. Service account (dkg-api-gateway) with Cloud Run Invoker
    2. API Gateway API resource
    3. API Gateway config (generated OpenAPI 2.0 spec)
    4. API Gateway instance
    5. GCP API key restricted to the gateway's managed service

Usage:
    python manage_gateway.py setup
    python manage_gateway.py status
    python manage_gateway.py test
    python manage_gateway.py teardown
    python manage_gateway.py teardown --force
    python manage_gateway.py --help
"""

import argparse
import json
import secrets
import subprocess
import sys
import tempfile
from datetime import UTC, datetime
from pathlib import Path

import yaml
from pydantic import BaseModel, Field

# -- Path resolution -----------------------------------------------

DEPLOY_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = DEPLOY_DIR.parents[1]
GATEWAY_CONFIG_PATH = DEPLOY_DIR / "gateway.yaml"
FUNCTIONS_CONFIG_PATH = DEPLOY_DIR / "functions.yaml"
FIXTURES_DIR = PROJECT_ROOT / "gcp" / "tests" / "fixtures"

# GCP APIs required for API Gateway and API key management.
REQUIRED_APIS = [
    "apigateway.googleapis.com",
    "servicemanagement.googleapis.com",
    "servicecontrol.googleapis.com",
    "apikeys.googleapis.com",
]


# -- Configuration models ------------------------------------------


class GatewaySettings(BaseModel):
    api_id: str
    gateway_id: str
    location: str
    service_account_name: str
    service_account_display_name: str = "API Gateway Service Account"
    api_key_display_name: str


class GatewayConfig(BaseModel):
    gateway: GatewaySettings
    target_function: str
    followup_function: str | None = None


class FunctionsGlobal(BaseModel):
    """Minimal model -- only the fields manage_gateway needs."""

    project: str
    region: str


class FunctionsConfig(BaseModel):
    global_: FunctionsGlobal = Field(alias="global")


# -- Config loading ------------------------------------------------


def load_gateway_config() -> GatewayConfig:
    """Parse and validate gateway.yaml."""
    raw = yaml.safe_load(GATEWAY_CONFIG_PATH.read_text())
    return GatewayConfig.model_validate(raw)


def load_functions_config() -> FunctionsConfig:
    """Parse functions.yaml for project and region."""
    raw = yaml.safe_load(FUNCTIONS_CONFIG_PATH.read_text())
    return FunctionsConfig.model_validate(raw)


# -- Helpers -------------------------------------------------------


def run(cmd: list[str], *, description: str) -> None:
    """Execute a subprocess, exiting on failure."""
    print(f"\n=== {description} ===")
    print(f"  -> {' '.join(cmd)}\n")
    result = subprocess.run(cmd, check=False)
    if result.returncode != 0:
        print(f"\n-> Failed: {description}", file=sys.stderr)
        sys.exit(result.returncode)


def run_quiet(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    """Execute a subprocess and capture output without printing."""
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def run_json(cmd: list[str]) -> dict | list | None:
    """Run a gcloud command with --format=json and parse the output."""
    result = run_quiet(cmd)
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except (json.JSONDecodeError, TypeError):
        return None


def print_banner(action: str, gw: GatewaySettings, project: str) -> None:
    """Print a formatted operation banner."""
    print(f"\n+{'=' * 55}+")
    print(f"| {action:<53}|")
    print(f"|  Project:   {project:<42}|")
    print(f"|  Location:  {gw.location:<42}|")
    print(f"|  API:       {gw.api_id:<42}|")
    print(f"|  Gateway:   {gw.gateway_id:<42}|")
    print(f"+{'=' * 55}+")


# -- Derived values ------------------------------------------------


def sa_email(sa_name: str, project: str) -> str:
    """Build the full service account email from its short name."""
    return f"{sa_name}@{project}.iam.gserviceaccount.com"


def generate_config_id(api_id: str) -> str:
    """Generate a unique API config ID using a UTC timestamp."""
    ts = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
    return f"{api_id}-{ts}"


# -- OpenAPI spec generation ---------------------------------------


def _build_post_operation(
    operation_id: str,
    backend_url: str,
) -> dict:
    """Build a single POST operation dict for an OpenAPI path entry."""
    return {
        "operationId": operation_id,
        "x-google-backend": {
            "address": backend_url,
            "jwt_audience": backend_url,
        },
        "security": [{"api_key": []}],
        "parameters": [
            {
                "in": "body",
                "name": "payload",
                "required": True,
                "schema": {"type": "object"},
            }
        ],
        "responses": {
            "200": {"description": "Successful processing"},
            "400": {"description": "Validation error"},
            "500": {"description": "Internal server error"},
        },
    }


def generate_openapi_spec(
    backend_url: str,
    followup_backend_url: str | None = None,
) -> dict:
    """Build a Swagger 2.0 spec for the API Gateway.

    Defines POST endpoints that:
    - Require an API key in the x-api-key header
    - Forward the full request body to Cloud Run
    - Authenticate to Cloud Run via a gateway-signed JWT

    POST / routes to the intake function (run-qualtrics-scheduling).
    POST /followup routes to the followup response function
    (run-followup-response) when followup_backend_url is provided.

    Args:
        backend_url: Cloud Run URL for the intake function (POST /).
        followup_backend_url: Cloud Run URL for the followup response
            function (POST /followup). Omit to skip that route.

    Returns:
        Dict suitable for YAML serialization as an OpenAPI spec.
    """
    paths: dict = {
        "/": {"post": _build_post_operation("qualtricsWebhook", backend_url)}
    }

    if followup_backend_url:
        paths["/followup"] = {
            "post": _build_post_operation(
                "followupResponse", followup_backend_url
            )
        }

    return {
        "swagger": "2.0",
        "info": {
            "title": "DKG Qualtrics Gateway",
            "description": (
                "Routes Qualtrics webhook POSTs to Cloud Run "
                "with IAM authentication"
            ),
            "version": "1.0.0",
        },
        "schemes": ["https"],
        "produces": ["application/json"],
        "consumes": ["application/json"],
        "paths": paths,
        "securityDefinitions": {
            "api_key": {
                "type": "apiKey",
                "name": "x-api-key",
                "in": "header",
            }
        },
    }


# -- Resource queries ----------------------------------------------


def get_project_number(project: str) -> str | None:
    """Get the numeric project number for a project ID."""
    result = run_quiet(
        [
            "gcloud",
            "projects",
            "describe",
            project,
            "--format=value(projectNumber)",
        ]
    )
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()
    return None


def get_cloud_run_url(
    project: str, region: str, function_name: str
) -> str | None:
    """Fetch the Cloud Run service URL via gcloud."""
    result = run_quiet(
        [
            "gcloud",
            "run",
            "services",
            "describe",
            function_name,
            f"--project={project}",
            f"--region={region}",
            "--format=value(status.url)",
        ]
    )
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()
    return None


def get_managed_service(project: str, api_id: str) -> str | None:
    """Get the managed service name for the API.

    The managed service is created when the API is provisioned
    and follows the pattern:
        {api_id}-{hash}.apigateway.{project}.cloud.goog
    """
    result = run_quiet(
        [
            "gcloud",
            "api-gateway",
            "apis",
            "describe",
            api_id,
            f"--project={project}",
            "--format=value(managedService)",
        ]
    )
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()
    return None


def get_gateway_url(project: str, location: str, gateway_id: str) -> str | None:
    """Get the gateway's public URL."""
    result = run_quiet(
        [
            "gcloud",
            "api-gateway",
            "gateways",
            "describe",
            gateway_id,
            f"--location={location}",
            f"--project={project}",
            "--format=value(defaultHostname)",
        ]
    )
    if result.returncode == 0 and result.stdout.strip():
        hostname = result.stdout.strip()
        return f"https://{hostname}"
    return None


def find_api_key_name(project: str, display_name: str) -> str | None:
    """Find an API key resource name by its display name."""
    result = run_quiet(
        [
            "gcloud",
            "services",
            "api-keys",
            "list",
            f"--project={project}",
            "--format=json",
        ]
    )
    if result.returncode != 0:
        return None
    try:
        keys = json.loads(result.stdout or "[]")
        for key in keys:
            if key.get("displayName") == display_name:
                return key.get("name")
    except (json.JSONDecodeError, TypeError):
        pass
    return None


def get_api_key_string(project: str, key_resource_name: str) -> str | None:
    """Retrieve the actual key string for an API key."""
    result = run_quiet(
        [
            "gcloud",
            "services",
            "api-keys",
            "get-key-string",
            key_resource_name,
            "--format=value(keyString)",
        ]
    )
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()
    return None


def resource_exists(cmd: list[str]) -> bool:
    """Check whether a gcloud describe command succeeds."""
    return run_quiet(cmd).returncode == 0


# -- Setup steps ---------------------------------------------------


def enable_apis(project: str) -> None:
    """Enable the GCP APIs required for API Gateway."""
    run(
        [
            "gcloud",
            "services",
            "enable",
            *REQUIRED_APIS,
            f"--project={project}",
        ],
        description="Enabling required GCP APIs",
    )


def grant_service_agent_roles(project: str) -> None:
    """Grant the API Gateway service agent the serviceController role.

    The API Gateway service agent is a GCP-managed account distinct from the
    user-created gateway service account. It calls the Service Control API to
    validate API keys on every inbound request. Without this role the gateway
    returns:
        INTERNAL: Calling Google Service Control API failed with: 403
        Permission 'servicemanagement.services.check' denied on service ...

    The service agent is created automatically when apigateway.googleapis.com
    is enabled, so this must run after enable_apis(). The binding is idempotent
    -- gcloud will no-op if the role is already assigned.
    """
    project_number = get_project_number(project)
    if not project_number:
        print(
            "\n  Warning: could not retrieve project number "
            "-- skipping service agent grant."
        )
        return

    service_agent = (
        f"service-{project_number}@gcp-sa-apigateway.iam.gserviceaccount.com"
    )
    run(
        [
            "gcloud",
            "projects",
            "add-iam-policy-binding",
            project,
            f"--member=serviceAccount:{service_agent}",
            "--role=roles/servicemanagement.serviceController",
        ],
        description="Granting serviceController to API Gateway service agent",
    )


def enable_managed_service(project: str, api_id: str) -> None:
    """Enable the gateway's managed service on the project.

    When GCP creates an API Gateway API, it generates a managed
    service (e.g., {api_id}-{hash}.apigateway.{project}.cloud.goog).
    This service must be explicitly enabled for API key
    authentication to work. Without it, requests fail with
    PERMISSION_DENIED even with a valid API key.

    IMPORTANT: Must be called AFTER create_api_config. The service
    configuration is only registered with Service Management once an
    api-configs create has been executed. Calling this before that step
    results in SERVICE_CONFIG_NOT_FOUND_OR_PERMISSION_DENIED (error_code=220002).
    """
    managed = get_managed_service(project, api_id)
    if not managed:
        print(
            "\n  Warning: could not retrieve managed service name "
            "-- skipping enablement."
        )
        return
    run(
        [
            "gcloud",
            "services",
            "enable",
            managed,
            f"--project={project}",
        ],
        description=f"Enabling managed service: {managed}",
    )


def create_service_account(project: str, name: str, display_name: str) -> str:
    """Create a service account if it does not exist.

    Returns the full email address.
    """
    email = sa_email(name, project)
    if resource_exists(
        [
            "gcloud",
            "iam",
            "service-accounts",
            "describe",
            email,
            f"--project={project}",
        ]
    ):
        print(f"\n  Service account '{email}' already exists -- skipping.")
        return email
    run(
        [
            "gcloud",
            "iam",
            "service-accounts",
            "create",
            name,
            f"--display-name={display_name}",
            f"--project={project}",
        ],
        description=f"Creating service account: {name}",
    )
    return email


def grant_run_invoker(
    project: str, region: str, function_name: str, sa: str
) -> None:
    """Grant Cloud Run Invoker role to the gateway service account."""
    run(
        [
            "gcloud",
            "run",
            "services",
            "add-iam-policy-binding",
            function_name,
            f"--project={project}",
            f"--region={region}",
            f"--member=serviceAccount:{sa}",
            "--role=roles/run.invoker",
        ],
        description="Granting Cloud Run Invoker to gateway SA",
    )


def create_api(project: str, api_id: str) -> None:
    """Create the API Gateway API resource."""
    if resource_exists(
        [
            "gcloud",
            "api-gateway",
            "apis",
            "describe",
            api_id,
            f"--project={project}",
        ]
    ):
        print(f"\n  API '{api_id}' already exists -- skipping.")
        return
    run(
        [
            "gcloud",
            "api-gateway",
            "apis",
            "create",
            api_id,
            f"--project={project}",
        ],
        description=f"Creating API: {api_id}",
    )


def create_api_config(
    project: str,
    api_id: str,
    config_id: str,
    spec: dict,
    backend_sa: str,
) -> None:
    """Create an API config from the generated OpenAPI spec.

    Writes the spec to a temporary YAML file and passes it to
    gcloud. The backend_sa is the service account the gateway
    uses to sign JWTs when calling Cloud Run.

    This step typically takes 3-5 minutes.
    """
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".yaml", delete=False, prefix="openapi-"
    ) as f:
        yaml.dump(spec, f, default_flow_style=False, sort_keys=False)
        spec_path = f.name

    print(f"\n  OpenAPI spec written to: {spec_path}")
    run(
        [
            "gcloud",
            "api-gateway",
            "api-configs",
            "create",
            config_id,
            f"--api={api_id}",
            f"--openapi-spec={spec_path}",
            f"--backend-auth-service-account={backend_sa}",
            f"--project={project}",
        ],
        description=(
            f"Creating API config: {config_id} "
            f"(this typically takes 3-5 minutes)"
        ),
    )


def create_gateway(
    project: str,
    location: str,
    gateway_id: str,
    api_id: str,
    config_id: str,
) -> None:
    """Create or update the API Gateway instance.

    If the gateway already exists, updates it to use the new
    config. Gateway creation typically takes 5-10 minutes.
    """
    if resource_exists(
        [
            "gcloud",
            "api-gateway",
            "gateways",
            "describe",
            gateway_id,
            f"--location={location}",
            f"--project={project}",
        ]
    ):
        print(f"\n  Gateway '{gateway_id}' already exists -- updating config.")
        run(
            [
                "gcloud",
                "api-gateway",
                "gateways",
                "update",
                gateway_id,
                f"--api={api_id}",
                f"--api-config={config_id}",
                f"--location={location}",
                f"--project={project}",
            ],
            description=(
                f"Updating gateway: {gateway_id} "
                f"(this typically takes 5-10 minutes)"
            ),
        )
        return
    run(
        [
            "gcloud",
            "api-gateway",
            "gateways",
            "create",
            gateway_id,
            f"--api={api_id}",
            f"--api-config={config_id}",
            f"--location={location}",
            f"--project={project}",
        ],
        description=(
            f"Creating gateway: {gateway_id} "
            f"(this typically takes 5-10 minutes)"
        ),
    )


def create_api_key(
    project: str, display_name: str, managed_service: str
) -> str | None:
    """Create a GCP API key restricted to the gateway.

    If a key with the same display name already exists, retrieves
    its key string instead of creating a duplicate.

    Returns the key string, or None if creation/retrieval fails.
    """
    existing = find_api_key_name(project, display_name)
    if existing:
        print(f"\n  API key '{display_name}' already exists -- retrieving.")
        return get_api_key_string(project, existing)

    # Create the key (non-fatal on failure so we can still
    # print the gateway URL and other setup results)
    print(f"\n=== Creating API key: {display_name} ===")
    result = run_quiet(
        [
            "gcloud",
            "services",
            "api-keys",
            "create",
            f"--display-name={display_name}",
            f"--api-target=service={managed_service}",
            f"--project={project}",
        ]
    )
    if result.returncode != 0:
        print("\n  Warning: API key creation failed.")
        print(f"  Error: {result.stderr.strip()}")
        print("  Create it manually in the GCP Console under")
        print("  APIs & Services -> Credentials -> Create API Key,")
        print(f"  then restrict it to: {managed_service}")
        return None

    print("  -> API key created.")

    key_name = find_api_key_name(project, display_name)
    if key_name:
        return get_api_key_string(project, key_name)

    print("\n  Warning: key created but could not retrieve key string.")
    print("  Run 'manage_gateway.py status' to retrieve it later.")
    return None


# -- Subcommand handlers -------------------------------------------


def handle_setup(args: argparse.Namespace) -> None:
    """Provision the complete API Gateway stack.

    Creates all resources in dependency order:
        1.  Enable required GCP APIs
        1b. Grant API Gateway service agent the serviceController role
        2.  Create gateway service account
        3.  Resolve Cloud Run backend URL
        4.  Grant Cloud Run Invoker to gateway SA
        5.  Create API resource
        6.  Create API config (registers service config with Service Management)
        7.  Enable managed service (must follow step 6)
        8.  Create or update gateway instance
        9.  Create API key
        10. Print results

    Idempotent -- safe to re-run after a failed step or a full teardown.
    Existing resources are detected and skipped; IAM bindings are upserted.

    Step ordering notes:
    - Step 1b must follow step 1: the service agent only exists once
      apigateway.googleapis.com is enabled.
    - Step 7 must follow step 6: the managed service has no registered service
      configuration until api-configs create runs. Enabling it before that
      yields SERVICE_CONFIG_NOT_FOUND_OR_PERMISSION_DENIED (error_code=220002).
    """
    gw_config = load_gateway_config()
    fn_config = load_functions_config()
    gw = gw_config.gateway
    project = fn_config.global_.project
    region = fn_config.global_.region

    print_banner("Setting up API Gateway", gw, project)

    # Step 1: Enable required GCP APIs
    enable_apis(project)

    # Step 1b: Grant API Gateway service agent the serviceController role.
    # Required so the gateway can call Service Control to validate API keys.
    # The service agent (service-{NUMBER}@gcp-sa-apigateway.iam.gserviceaccount.com)
    # is distinct from the user-managed gateway SA and is created automatically
    # when apigateway.googleapis.com is enabled above.
    grant_service_agent_roles(project)

    # Step 2: Create gateway service account
    backend_sa = create_service_account(
        project,
        gw.service_account_name,
        gw.service_account_display_name,
    )

    # Step 3: Resolve Cloud Run backend URL
    print("\n=== Resolving Cloud Run URL ===")
    backend_url = get_cloud_run_url(project, region, gw_config.target_function)
    if not backend_url:
        print(
            f"\n-> Could not find Cloud Run service "
            f"'{gw_config.target_function}' in {region}.",
            file=sys.stderr,
        )
        print("  Deploy the function first:")
        print(
            f"    python manage_functions.py deploy {gw_config.target_function}"
        )
        sys.exit(1)
    print(f"  -> {backend_url} (intake, POST /)")

    followup_backend_url: str | None = None
    if gw_config.followup_function:
        followup_backend_url = get_cloud_run_url(
            project, region, gw_config.followup_function
        )
        if followup_backend_url:
            print(f"  -> {followup_backend_url} (followup, POST /followup)")
        else:
            print(
                f"  -> '{gw_config.followup_function}' not deployed; "
                f"POST /followup will be omitted from the spec."
            )

    # Step 4: Grant Cloud Run Invoker to gateway SA
    grant_run_invoker(project, region, gw_config.target_function, backend_sa)
    if followup_backend_url and gw_config.followup_function:
        grant_run_invoker(
            project, region, gw_config.followup_function, backend_sa
        )

    # Step 5: Create API resource
    create_api(project, gw.api_id)

    # Step 6: Generate OpenAPI spec and create API config.
    # This registers the service configuration with Service Management.
    # enable_managed_service (step 7) depends on this having run first.
    spec = generate_openapi_spec(backend_url, followup_backend_url)
    config_id = generate_config_id(gw.api_id)
    create_api_config(project, gw.api_id, config_id, spec, backend_sa)

    # Step 7: Enable the managed service.
    # Safe to call here -- the api-configs create above has pushed the
    # service config to Service Management.
    enable_managed_service(project, gw.api_id)

    # Step 8: Create or update gateway instance
    create_gateway(project, gw.location, gw.gateway_id, gw.api_id, config_id)

    # Step 9: Create API key restricted to gateway managed service
    api_key = None
    managed_service = get_managed_service(project, gw.api_id)
    if not managed_service:
        print("\n  Warning: could not retrieve managed service name.")
        print("  API key creation skipped -- create it manually.")
    else:
        api_key = create_api_key(
            project, gw.api_key_display_name, managed_service
        )

    # Step 10: Print results
    gateway_url = get_gateway_url(project, gw.location, gw.gateway_id)
    print(f"\n+{'=' * 55}+")
    print(f"| {'Setup complete':<53}|")
    print(f"+{'=' * 55}+")
    print(f"\n  Gateway URL: {gateway_url or '(pending...)'}")
    if api_key:
        print(f"  API key:     {api_key}")
    print()
    print("  Qualtrics Web Service task configuration:")
    print("    Method:  POST")
    print(f"    URL:     {gateway_url or ''}")
    print(f"    Header:  x-api-key = {api_key or ''}")
    print("    Header:  Content-Type = application/json")
    print("    Body:    JSON payload (see README)")
    print()
    print("  Test with:")
    print("    python manage_gateway.py test")
    print()


def handle_status(args: argparse.Namespace) -> None:
    """Show the current state of all gateway resources."""
    gw_config = load_gateway_config()
    fn_config = load_functions_config()
    gw = gw_config.gateway
    project = fn_config.global_.project

    print_banner("Gateway status", gw, project)

    # API
    api_info = run_json(
        [
            "gcloud",
            "api-gateway",
            "apis",
            "describe",
            gw.api_id,
            f"--project={project}",
            "--format=json",
        ]
    )
    if api_info:
        managed = api_info.get("managedService", "unknown")
        state = api_info.get("state", "unknown")
        print(f"\n  API: {gw.api_id} ({state})")
        print(f"  Managed service: {managed}")
    else:
        print(f"\n  API '{gw.api_id}' not found.")
        print("  Run 'setup' to provision.\n")
        return

    # Gateway
    gateway_url = get_gateway_url(project, gw.location, gw.gateway_id)
    if gateway_url:
        print(f"  Gateway URL: {gateway_url}")
    else:
        print(f"  Gateway: '{gw.gateway_id}' not found")

    # Service account
    email = sa_email(gw.service_account_name, project)
    sa_exists = resource_exists(
        [
            "gcloud",
            "iam",
            "service-accounts",
            "describe",
            email,
            f"--project={project}",
        ]
    )
    print(
        f"  Service account: {email} ({'exists' if sa_exists else 'missing'})"
    )

    # API Gateway service agent
    project_number = get_project_number(project)
    if project_number:
        service_agent = f"service-{project_number}@gcp-sa-apigateway.iam.gserviceaccount.com"
        bindings = run_json(
            [
                "gcloud",
                "projects",
                "get-iam-policy",
                project,
                "--format=json",
            ]
        )
        has_controller = False
        if bindings:
            for binding in bindings.get("bindings", []):
                if (
                    binding.get("role")
                    == "roles/servicemanagement.serviceController"
                ):
                    if f"serviceAccount:{service_agent}" in binding.get(
                        "members", []
                    ):
                        has_controller = True
                        break
        status = (
            "serviceController granted"
            if has_controller
            else "WARNING: serviceController missing"
        )
        print(f"  Service agent:   {service_agent} ({status})")

    # API key
    key_name = find_api_key_name(project, gw.api_key_display_name)
    if key_name:
        key_string = get_api_key_string(project, key_name)
        if key_string:
            masked = f"{key_string[:8]}...{key_string[-4:]}"
            print(f"  API key: {masked}")
        else:
            print("  API key: (exists, could not retrieve string)")
    else:
        print("  API key: not found")

    # Backends
    backend_url = get_cloud_run_url(
        project, fn_config.global_.region, gw_config.target_function
    )
    print(f"  Backend (POST /):         {backend_url or 'not deployed'}")
    if gw_config.followup_function:
        followup_url = get_cloud_run_url(
            project, fn_config.global_.region, gw_config.followup_function
        )
        print(f"  Backend (POST /followup): {followup_url or 'not deployed'}")
    print()


def handle_test(args: argparse.Namespace) -> None:
    """Send the test fixture through the gateway.

    Simulates exactly what Qualtrics will do: a POST with
    an x-api-key header, no bearer token, no IAM credentials.

    The ``--selected-date`` flag overrides the ``selected_date``
    field in the fixture payload. If omitted, defaults to
    tomorrow (ensures all 3 follow-up time slots are far enough
    in the future for Twilio's 15-minute scheduling minimum).

    The ``--now`` flag sets ``send_immediately=True`` in the
    payload and uses today as ``selected_date``. This causes
    run-followup-scheduling to schedule all 3 SMS at
    now+16 / now+32 / now+48 min instead of fixed study times,
    so the full pipeline can be verified within ~48 minutes.

    The ``--now-with-me PHONE`` flag behaves like ``--now`` but
    replaces the fixture's virtual phone number with PHONE and
    uses a distinct response_id / connect_id so the BQ
    idempotency guard does not block it after a ``--now`` run.
    Pass PHONE as 10 digits, 11 digits, or E.164 (+1XXXXXXXXXX).

    ``--now``, ``--now-with-me``, and ``--selected-date`` are
    mutually exclusive with each other.
    ``--followup`` is mutually exclusive with all of the above.

    This is the closest thing to a 'dev' mode for the gateway.
    """
    from datetime import date as _date
    from datetime import timedelta as _timedelta

    followup_mode = args.followup

    if followup_mode:
        if args.now or args.selected_date or args.now_with_me:
            print(
                "\n-> --followup is mutually exclusive with "
                "--now, --now-with-me, and --selected-date.",
                file=sys.stderr,
            )
            sys.exit(1)
    else:
        flags_set = sum(
            [
                bool(args.now),
                bool(args.selected_date),
                bool(args.now_with_me),
            ]
        )
        if flags_set > 1:
            print(
                "\n-> --now, --now-with-me, and --selected-date "
                "are mutually exclusive.",
                file=sys.stderr,
            )
            sys.exit(1)

    gw_config = load_gateway_config()
    fn_config = load_functions_config()
    gw = gw_config.gateway
    project = fn_config.global_.project

    # Resolve gateway URL
    gateway_url = get_gateway_url(project, gw.location, gw.gateway_id)
    if not gateway_url:
        print("\n-> Gateway not found. Run 'setup' first.", file=sys.stderr)
        sys.exit(1)

    # Resolve API key
    key_name = find_api_key_name(project, gw.api_key_display_name)
    if not key_name:
        print("\n-> API key not found. Run 'setup' first.", file=sys.stderr)
        sys.exit(1)

    api_key = get_api_key_string(project, key_name)
    if not api_key:
        print("\n-> Could not retrieve API key string.", file=sys.stderr)
        sys.exit(1)

    masked_key = f"{api_key[:8]}...{api_key[-4:]}"

    if followup_mode:
        # POST /followup -- no date manipulation, terminal endpoint
        fixture = FIXTURES_DIR / "followup_web_service_payload.json"
        if not fixture.exists():
            print(f"\n-> Fixture not found: {fixture}", file=sys.stderr)
            sys.exit(1)
        payload = json.loads(fixture.read_text())
        target_url = f"{gateway_url}/followup"
        payload_json = json.dumps(payload)
        print(f"\n  Gateway:  {target_url}")
        print(f"  Fixture:  {fixture.name}")
        print(f"  API key:  {masked_key}")
        print(
            "\n  Sending POST /followup (no IAM token -- just the API key)..."
        )
    else:
        # POST / -- intake fixture with optional date overrides
        fixture = FIXTURES_DIR / "web_service_payload.json"
        if not fixture.exists():
            print(f"\n-> Fixture not found: {fixture}", file=sys.stderr)
            sys.exit(1)
        payload = json.loads(fixture.read_text())

        if getattr(args, "now", False):
            payload["SELECTED_DATE"] = _date.today().isoformat()
            payload["send_immediately"] = True
        elif args.now_with_me:
            # Strip leading + so the raw-digit format matches what
            # Qualtrics submits; fn1's normalize_phone_number() converts
            # 10- or 11-digit strings to E.164 before sending.
            payload["SELECTED_DATE"] = _date.today().isoformat()
            payload["send_immediately"] = True
            payload["PHONE"] = args.now_with_me.lstrip("+")
            # Generate a unique response_id per invocation so the fn2/fn3
            # idempotency guards don't block repeated runs with any phone
            # number. Format: R_TEST_{last4digits}_{6-char hex}.
            _last4 = payload["PHONE"][-4:]
            _suffix = secrets.token_hex(3)
            payload["RESPONSE_ID"] = f"R_TEST_{_last4}_{_suffix}"
            payload["CONNECT_ID"] = f"test_{_last4}_{_suffix}"
        elif args.selected_date:
            payload["SELECTED_DATE"] = args.selected_date
        else:
            payload["SELECTED_DATE"] = (
                _date.today() + _timedelta(days=1)
            ).isoformat()

        target_url = gateway_url
        payload_json = json.dumps(payload)
        print(f"\n  Gateway:       {target_url}")
        print(f"  Fixture:       {fixture.name}")
        print(f"  selected_date: {payload['SELECTED_DATE']}")
        if args.now_with_me:
            masked_phone = payload["PHONE"][:3] + "***" + payload["PHONE"][-4:]
            print(
                f"  Mode:          --now-with-me "
                f"(real phone {masked_phone}, SMS at now+16/32/48 min)"
            )
            print(f"  response_id:   {payload['RESPONSE_ID']}")
        elif payload.get("send_immediately"):
            print("  Mode:          --now (SMS scheduled at now+16/32/48 min)")
        print(f"  API key:       {masked_key}")
        print("\n  Sending POST (no IAM token -- just the API key)...")

    # Send the request exactly as Qualtrics would
    result = subprocess.run(
        [
            "curl",
            "-s",
            "-w",
            "\n--- HTTP %{http_code} ---",
            "-X",
            "POST",
            target_url,
            "-H",
            "Content-Type: application/json",
            "-H",
            f"x-api-key: {api_key}",
            "-d",
            payload_json,
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    print(f"\n  Response:\n  {result.stdout}")
    if result.stderr:
        print(f"  {result.stderr}")
    print()


def handle_teardown(args: argparse.Namespace) -> None:
    """Delete the gateway and all related resources.

    Deletion order respects dependencies:
        1. Gateway (depends on API config)
        2. API configs (depend on API)
        3. API
        4. API key
        5. Service account

    The IAM binding for the GCP-managed service agent is intentionally
    NOT removed -- it is project-level, harmless when the gateway is down,
    and will be needed again on the next setup.

    The dataset and Cloud Run function are NOT touched.
    """
    gw_config = load_gateway_config()
    fn_config = load_functions_config()
    gw = gw_config.gateway
    project = fn_config.global_.project

    print_banner("Tearing down API Gateway", gw, project)

    if not args.force:
        print("\n  This will permanently delete:")
        print(f"    Gateway:         {gw.gateway_id}")
        print(f"    API + configs:   {gw.api_id}")
        print(f"    API key:         {gw.api_key_display_name}")
        print(f"    Service account: {gw.service_account_name}")
        print()
        response = input("  Type 'yes' to confirm: ")
        if response.strip().lower() != "yes":
            print("\n  Teardown cancelled.\n")
            return

    # 1. Delete gateway
    if resource_exists(
        [
            "gcloud",
            "api-gateway",
            "gateways",
            "describe",
            gw.gateway_id,
            f"--location={gw.location}",
            f"--project={project}",
        ]
    ):
        run(
            [
                "gcloud",
                "api-gateway",
                "gateways",
                "delete",
                gw.gateway_id,
                f"--location={gw.location}",
                f"--project={project}",
                "--quiet",
            ],
            description="Deleting gateway (this may take several minutes)",
        )
    else:
        print(f"\n  Gateway '{gw.gateway_id}' not found -- skipping.")

    # 2. Delete all API configs for this API
    configs = run_json(
        [
            "gcloud",
            "api-gateway",
            "api-configs",
            "list",
            f"--api={gw.api_id}",
            f"--project={project}",
            "--format=json",
        ]
    )
    if configs:
        for cfg in configs:
            # Resource name: projects/.../locations/global/apis/.../configs/ID
            cfg_id = cfg["name"].split("/")[-1]
            run(
                [
                    "gcloud",
                    "api-gateway",
                    "api-configs",
                    "delete",
                    cfg_id,
                    f"--api={gw.api_id}",
                    f"--project={project}",
                    "--quiet",
                ],
                description=f"Deleting API config: {cfg_id}",
            )
    else:
        print(f"\n  No API configs found for '{gw.api_id}' -- skipping.")

    # 3. Delete API
    if resource_exists(
        [
            "gcloud",
            "api-gateway",
            "apis",
            "describe",
            gw.api_id,
            f"--project={project}",
        ]
    ):
        run(
            [
                "gcloud",
                "api-gateway",
                "apis",
                "delete",
                gw.api_id,
                f"--project={project}",
                "--quiet",
            ],
            description="Deleting API",
        )
    else:
        print(f"\n  API '{gw.api_id}' not found -- skipping.")

    # 4. Delete API key
    key_name = find_api_key_name(project, gw.api_key_display_name)
    if key_name:
        run(
            [
                "gcloud",
                "services",
                "api-keys",
                "delete",
                key_name,
                f"--project={project}",
                "--quiet",
            ],
            description="Deleting API key",
        )
    else:
        print(f"\n  API key '{gw.api_key_display_name}' not found -- skipping.")

    # 5. Delete service account
    email = sa_email(gw.service_account_name, project)
    if resource_exists(
        [
            "gcloud",
            "iam",
            "service-accounts",
            "describe",
            email,
            f"--project={project}",
        ]
    ):
        run(
            [
                "gcloud",
                "iam",
                "service-accounts",
                "delete",
                email,
                f"--project={project}",
                "--quiet",
            ],
            description="Deleting service account",
        )
    else:
        print(f"\n  Service account '{email}' not found -- skipping.")

    print("\n  Teardown complete.\n")


# -- CLI definition ------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="manage_gateway",
        description="API Gateway lifecycle manager for Qualtrics webhook routing.",
    )
    subparsers = parser.add_subparsers(
        dest="command",
        required=True,
    )

    # setup
    setup_parser = subparsers.add_parser(
        "setup",
        help="Provision API Gateway, service account, and API key.",
    )
    setup_parser.set_defaults(handler=handle_setup)

    # status
    status_parser = subparsers.add_parser(
        "status",
        help="Show current state of all gateway resources.",
    )
    status_parser.set_defaults(handler=handle_status)

    # test
    test_parser = subparsers.add_parser(
        "test",
        help="Send the test fixture payload through the gateway.",
    )
    test_parser.add_argument(
        "--selected-date",
        help=(
            "Override selected_date in the fixture (ISO format, "
            "e.g., 2026-03-11). Defaults to tomorrow if not specified. "
            "Mutually exclusive with --now."
        ),
    )
    test_parser.add_argument(
        "--now",
        action="store_true",
        help=(
            "Schedule follow-up SMS at now+16/32/48 min instead of "
            "fixed study times. Uses today as selected_date. "
            "Mutually exclusive with --selected-date and --now-with-me."
        ),
    )
    test_parser.add_argument(
        "--now-with-me",
        metavar="PHONE",
        help=(
            "Like --now, but sends to PHONE instead of the fixture's "
            "virtual number. Accepts 10 digits, 11 digits, or E.164 "
            "(e.g. +15551234567). Uses a distinct response_id and "
            "connect_id to avoid BQ idempotency collision with "
            "--now runs. Mutually exclusive with --now and "
            "--selected-date."
        ),
    )
    test_parser.add_argument(
        "--followup",
        action="store_true",
        help=(
            "Send the followup fixture to POST /followup instead of "
            "the intake fixture to POST /. Tests the "
            "run-followup-response path end-to-end. Mutually exclusive "
            "with --now, --now-with-me, and --selected-date."
        ),
    )
    test_parser.set_defaults(handler=handle_test)

    # teardown
    teardown_parser = subparsers.add_parser(
        "teardown",
        help="Delete the gateway and all related resources.",
    )
    teardown_parser.add_argument(
        "--force",
        "-f",
        action="store_true",
        help="Skip confirmation prompt.",
    )
    teardown_parser.set_defaults(handler=handle_teardown)

    return parser


# -- Entrypoint ----------------------------------------------------


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()
