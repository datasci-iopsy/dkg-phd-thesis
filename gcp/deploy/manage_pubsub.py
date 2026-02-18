"""Pub/Sub topic lifecycle manager for intake response processing.

Creates and manages the Pub/Sub topic that connects the qualtrics
scheduling function (publisher) to the intake confirmation
function (subscriber). The topic must exist before either
function is deployed.

The subscription is NOT managed here. When the intake
confirmation function is deployed with a Pub/Sub trigger via
manage_functions.py, Eventarc automatically creates a push
subscription to the Cloud Run function.

Resources created by 'setup':
    1. Pub/Sub topic (dkg-intake-processed)

Usage:
    python manage_pubsub.py setup
    python manage_pubsub.py status
    python manage_pubsub.py teardown
    python manage_pubsub.py teardown --force
    python manage_pubsub.py --help
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

import yaml
from pydantic import BaseModel, Field

# -- Path resolution -----------------------------------------------
DEPLOY_DIR = Path(__file__).resolve().parent
PUBSUB_CONFIG_PATH = DEPLOY_DIR / "pubsub.yaml"
FUNCTIONS_CONFIG_PATH = DEPLOY_DIR / "functions.yaml"

REQUIRED_APIS = [
    "pubsub.googleapis.com",
]


# -- Configuration models ------------------------------------------
class PubSubSettings(BaseModel):
    topic_id: str


class PubSubConfig(BaseModel):
    pubsub: PubSubSettings


class FunctionsGlobal(BaseModel):
    """Minimal model -- only the fields manage_pubsub needs."""

    project: str
    region: str


class FunctionsConfig(BaseModel):
    global_: FunctionsGlobal = Field(alias="global")


# -- Config loading ------------------------------------------------
def load_pubsub_config() -> PubSubConfig:
    """Parse and validate pubsub.yaml."""
    raw = yaml.safe_load(PUBSUB_CONFIG_PATH.read_text())
    return PubSubConfig.model_validate(raw)


def load_functions_config() -> FunctionsConfig:
    """Parse functions.yaml for project and region."""
    raw = yaml.safe_load(FUNCTIONS_CONFIG_PATH.read_text())
    return FunctionsConfig.model_validate(raw)


# -- Helpers (same patterns as manage_gateway.py) ------------------
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


def resource_exists(cmd: list[str]) -> bool:
    """Check whether a gcloud describe command succeeds."""
    return run_quiet(cmd).returncode == 0


def print_banner(action: str, topic_id: str, project: str) -> None:
    """Print a formatted operation banner."""
    print(f"\n+{'=' * 55}+")
    print(f"|  {action:<53}|")
    print(f"|  Project:  {project:<44}|")
    print(f"|  Topic:    {topic_id:<44}|")
    print(f"+{'=' * 55}+")


# -- Topic operations ----------------------------------------------
def topic_exists(project: str, topic_id: str) -> bool:
    """Check whether the Pub/Sub topic exists."""
    return resource_exists(
        [
            "gcloud",
            "pubsub",
            "topics",
            "describe",
            topic_id,
            f"--project={project}",
        ]
    )


def create_topic(project: str, topic_id: str) -> None:
    """Create the Pub/Sub topic if it does not exist."""
    if topic_exists(project, topic_id):
        print(f"\n  Topic '{topic_id}' already exists -- skipping.")
        return

    run(
        [
            "gcloud",
            "pubsub",
            "topics",
            "create",
            topic_id,
            f"--project={project}",
        ],
        description=f"Creating topic: {topic_id}",
    )


def list_subscriptions(project: str, topic_id: str) -> list[dict] | None:
    """List subscriptions attached to the topic."""
    full_topic = f"projects/{project}/topics/{topic_id}"
    result = run_json(
        [
            "gcloud",
            "pubsub",
            "topics",
            "list-subscriptions",
            full_topic,
            f"--project={project}",
            "--format=json",
        ]
    )
    if isinstance(result, list):
        return result
    return None


# -- Subcommand handlers -------------------------------------------
def handle_setup(args: argparse.Namespace) -> None:
    """Provision the Pub/Sub topic.

    Creates the topic used for intake response processing.
    Idempotent -- safe to run again if it already exists.

    The Eventarc subscription is created automatically when
    the consuming function is deployed with a Pub/Sub trigger.
    """
    ps_config = load_pubsub_config()
    fn_config = load_functions_config()

    topic_id = ps_config.pubsub.topic_id
    project = fn_config.global_.project

    print_banner("Setting up Pub/Sub", topic_id, project)

    # Step 1: Enable APIs
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

    # Step 2: Create topic
    create_topic(project, topic_id)

    # Done
    full_topic = f"projects/{project}/topics/{topic_id}"
    print(f"\n+{'=' * 55}+")
    print(f"|  {'Setup complete':<53}|")
    print(f"+{'=' * 55}+")
    print(f"\n  Topic: {full_topic}")
    print()
    print("  Next steps:")
    print("    1. Deploy the publishing function (run-qualtrics-scheduling)")
    print("       with pubsub.publisher role on its service account.")
    print("    2. Deploy the consuming function (run-intake-confirmation)")
    print("       with a Pub/Sub trigger pointing to this topic.")
    print()


def handle_status(args: argparse.Namespace) -> None:
    """Show the current state of the Pub/Sub topic."""
    ps_config = load_pubsub_config()
    fn_config = load_functions_config()

    topic_id = ps_config.pubsub.topic_id
    project = fn_config.global_.project

    print_banner("Pub/Sub status", topic_id, project)

    # Topic
    if not topic_exists(project, topic_id):
        print(f"\n  Topic '{topic_id}' does not exist.")
        print("  Run 'setup' to create it.\n")
        return

    full_topic = f"projects/{project}/topics/{topic_id}"
    print(f"\n  Topic: {full_topic} (exists)")

    # Subscriptions
    subs = list_subscriptions(project, topic_id)
    if subs:
        print(f"  Subscriptions ({len(subs)}):")
        for sub in subs:
            # Subscription names can be full resource paths or
            # simple strings depending on gcloud version.
            if isinstance(sub, str):
                sub_name = sub.split("/")[-1]
                print(f"    - {sub_name}")
            elif isinstance(sub, dict):
                sub_name = sub.get("name", str(sub)).split("/")[-1]
                push_config = sub.get("pushConfig", {})
                endpoint = push_config.get("pushEndpoint", "")
                detail = f" -> {endpoint}" if endpoint else ""
                print(f"    - {sub_name}{detail}")
    else:
        print("  Subscriptions: none")
        print(
            "    (Eventarc creates one when the consuming function is deployed)"
        )

    print()


def handle_teardown(args: argparse.Namespace) -> None:
    """Delete the Pub/Sub topic.

    Deleting a topic also removes all Eventarc-managed
    subscriptions attached to it. The consuming Cloud Run
    function is NOT deleted.

    Use --force to skip the confirmation prompt.
    """
    ps_config = load_pubsub_config()
    fn_config = load_functions_config()

    topic_id = ps_config.pubsub.topic_id
    project = fn_config.global_.project

    print_banner("Tearing down Pub/Sub", topic_id, project)

    if not topic_exists(project, topic_id):
        print(f"\n  Topic '{topic_id}' does not exist -- nothing to do.\n")
        return

    if not args.force:
        # Show what will be affected
        subs = list_subscriptions(project, topic_id)
        sub_count = len(subs) if subs else 0

        print(f"\n  This will permanently delete:")
        print(f"    Topic:         {topic_id}")
        if sub_count > 0:
            print(
                f"    Subscriptions: {sub_count} "
                f"(automatically removed with topic)"
            )
        print()

        response = input("  Type 'yes' to confirm: ")
        if response.strip().lower() != "yes":
            print("\n  Teardown cancelled.\n")
            return

    # Delete topic
    run(
        [
            "gcloud",
            "pubsub",
            "topics",
            "delete",
            topic_id,
            f"--project={project}",
            "--quiet",
        ],
        description=f"Deleting topic: {topic_id}",
    )

    print(f"\n  Teardown complete.\n")


# -- CLI definition ------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="manage_pubsub",
        description=(
            "Pub/Sub topic lifecycle manager for intake response processing."
        ),
    )
    subparsers = parser.add_subparsers(
        dest="command",
        required=True,
    )

    # setup
    setup_parser = subparsers.add_parser(
        "setup",
        help="Create the Pub/Sub topic.",
    )
    setup_parser.set_defaults(handler=handle_setup)

    # status
    status_parser = subparsers.add_parser(
        "status",
        help="Show current state of the topic and subscriptions.",
    )
    status_parser.set_defaults(handler=handle_status)

    # teardown
    teardown_parser = subparsers.add_parser(
        "teardown",
        help="Delete the topic and any attached subscriptions.",
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
