"""Pub/Sub topic lifecycle manager.

Creates and manages Pub/Sub topics for inter-function
communication. Topics must exist before their consuming
functions are deployed.

Subscriptions are NOT managed here. When a consuming Cloud Run
function is deployed with a Pub/Sub trigger via manage_functions.py,
Eventarc automatically creates a push subscription.

Topics managed:
    - dkg-intake-processed (qualtrics scheduling → confirmation)
    - dkg-followup-scheduling (confirmation → follow-up scheduling)

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
    topics: list[str]


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


def print_banner(action: str, topics: list[str], project: str) -> None:
    """Print a formatted operation banner."""
    print(f"\n+{'=' * 55}+")
    print(f"|  {action:<53}|")
    print(f"|  Project:  {project:<44}|")
    for topic_id in topics:
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
    """Provision all Pub/Sub topics.

    Creates topics for inter-function communication.
    Idempotent -- safe to run again if topics already exist.

    Eventarc subscriptions are created automatically when
    consuming functions are deployed with Pub/Sub triggers.
    """
    ps_config = load_pubsub_config()
    fn_config = load_functions_config()

    topics = ps_config.pubsub.topics
    project = fn_config.global_.project

    print_banner("Setting up Pub/Sub", topics, project)

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

    # Step 2: Create topics
    for topic_id in topics:
        create_topic(project, topic_id)

    # Done
    print(f"\n+{'=' * 55}+")
    print(f"|  {'Setup complete':<53}|")
    print(f"+{'=' * 55}+")
    for topic_id in topics:
        full_topic = f"projects/{project}/topics/{topic_id}"
        print(f"\n  Topic: {full_topic}")
    print()
    print("  Next steps:")
    print("    1. Deploy publishing functions with pubsub.publisher role.")
    print("    2. Deploy consuming functions with Pub/Sub triggers.")
    print()


def handle_status(args: argparse.Namespace) -> None:
    """Show the current state of all Pub/Sub topics."""
    ps_config = load_pubsub_config()
    fn_config = load_functions_config()

    topics = ps_config.pubsub.topics
    project = fn_config.global_.project

    print_banner("Pub/Sub status", topics, project)

    for topic_id in topics:
        if not topic_exists(project, topic_id):
            print(f"\n  Topic '{topic_id}' does not exist.")
            print("  Run 'setup' to create it.")
            continue

        full_topic = f"projects/{project}/topics/{topic_id}"
        print(f"\n  Topic: {full_topic} (exists)")

        # Subscriptions
        subs = list_subscriptions(project, topic_id)
        if subs:
            print(f"  Subscriptions ({len(subs)}):")
            for sub in subs:
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
                "    (Eventarc creates one when the consuming "
                "function is deployed)"
            )

    print()


def handle_teardown(args: argparse.Namespace) -> None:
    """Delete all Pub/Sub topics.

    Deleting a topic also removes all Eventarc-managed
    subscriptions attached to it. Consuming Cloud Run
    functions are NOT deleted.

    Use --force to skip the confirmation prompt.
    """
    ps_config = load_pubsub_config()
    fn_config = load_functions_config()

    topics = ps_config.pubsub.topics
    project = fn_config.global_.project

    print_banner("Tearing down Pub/Sub", topics, project)

    existing_topics = [t for t in topics if topic_exists(project, t)]

    if not existing_topics:
        print("\n  No topics found -- nothing to do.\n")
        return

    if not args.force:
        print("\n  This will permanently delete:")
        for topic_id in existing_topics:
            subs = list_subscriptions(project, topic_id)
            sub_count = len(subs) if subs else 0
            sub_detail = (
                f" ({sub_count} subscription(s))" if sub_count > 0 else ""
            )
            print(f"    - {topic_id}{sub_detail}")
        print()

        response = input("  Type 'yes' to confirm: ")
        if response.strip().lower() != "yes":
            print("\n  Teardown cancelled.\n")
            return

    for topic_id in existing_topics:
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

    print("\n  Teardown complete.\n")


# -- CLI definition ------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="manage_pubsub",
        description="Pub/Sub topic lifecycle manager.",
    )
    subparsers = parser.add_subparsers(
        dest="command",
        required=True,
    )

    # setup
    setup_parser = subparsers.add_parser(
        "setup",
        help="Create all Pub/Sub topics.",
    )
    setup_parser.set_defaults(handler=handle_setup)

    # status
    status_parser = subparsers.add_parser(
        "status",
        help="Show current state of topics and subscriptions.",
    )
    status_parser.set_defaults(handler=handle_status)

    # teardown
    teardown_parser = subparsers.add_parser(
        "teardown",
        help="Delete all topics and their attached subscriptions.",
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
