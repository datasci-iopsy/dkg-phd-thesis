"""Cloud Run Functions lifecycle manager.

Reads function configuration from functions.yaml and handles
local development, deployment, teardown, and inspection of
Cloud Run functions.

Each function can declare a dedicated service account with
least-privilege IAM roles. During deploy, the service account
is created (if it does not exist), granted the declared roles,
and passed to gcloud via --service-account. During teardown,
the service account is deleted along with the function.

Usage:
    python manage_functions.py dev      <function-name>
    python manage_functions.py dev      <function-name> --port 9090
    python manage_functions.py deploy   <function-name>
    python manage_functions.py teardown <function-name>
    python manage_functions.py teardown <function-name> --force
    python manage_functions.py list
    python manage_functions.py --help
    python manage_functions.py dev --help
"""

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

import yaml
from pydantic import BaseModel, Field

# -- Path resolution -----------------------------------------------
DEPLOY_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = DEPLOY_DIR.parents[1]
FUNCTIONS_BASE = PROJECT_ROOT / "gcp" / "cloud_run_functions"
CONFIG_PATH = DEPLOY_DIR / "functions.yaml"


# -- Configuration models ------------------------------------------
class GlobalConfig(BaseModel):
    project: str
    region: str
    runtime: str
    gen2: bool = True


class ServiceAccountConfig(BaseModel):
    name: str
    display_name: str = "Cloud Run Function Service Account"
    roles: list[str] = Field(default_factory=list)


class FunctionConfig(BaseModel):
    source_dir: str
    poetry_group: str
    entry_point: str
    trigger: str
    allow_unauthenticated: bool = False
    secrets: list[str] = Field(default_factory=list)
    service_account: ServiceAccountConfig | None = None


class DeployConfig(BaseModel):
    global_: GlobalConfig = Field(alias="global")
    functions: dict[str, FunctionConfig]


# -- Helpers --------------------------------------------------------
def load_config() -> DeployConfig:
    """Parse and validate functions.yaml."""
    raw = yaml.safe_load(CONFIG_PATH.read_text())
    return DeployConfig.model_validate(raw)


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


def resource_exists(cmd: list[str]) -> bool:
    """Check whether a gcloud describe command succeeds."""
    return run_quiet(cmd).returncode == 0


def sa_email(sa_name: str, project: str) -> str:
    """Build the full service account email from its short name."""
    return f"{sa_name}@{project}.iam.gserviceaccount.com"


def resolve_function(
    config: DeployConfig, name: str
) -> tuple[FunctionConfig, GlobalConfig, Path]:
    """Validate function name and return its config + paths."""
    if name not in config.functions:
        print(f"\n-> Unknown function: '{name}'", file=sys.stderr)
        print("  Run 'list' to see available functions.")
        sys.exit(1)

    fn = config.functions[name]
    g = config.global_
    function_dir = FUNCTIONS_BASE / fn.source_dir
    return fn, g, function_dir


def print_banner(action: str, name: str, g: GlobalConfig) -> None:
    """Print a formatted operation banner."""
    label = f"{action}: {name}"
    print(f"\n+{'=' * 50}+")
    print(f"|  {label:<48}|")
    print(f"|  Project:   {g.project:<38}|")
    print(f"|  Region:    {g.region:<38}|")
    print(f"+{'=' * 50}+")


# -- Service account steps -----------------------------------------
def create_service_account(
    project: str, sa_config: ServiceAccountConfig
) -> str:
    """Create a service account if it does not exist.

    Returns the full email address.
    """
    email = sa_email(sa_config.name, project)

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
            sa_config.name,
            f"--display-name={sa_config.display_name}",
            f"--project={project}",
        ],
        description=f"Creating service account: {sa_config.name}",
    )
    return email


def grant_iam_roles(project: str, sa_email: str, roles: list[str]) -> None:
    """Grant project-level IAM roles to the service account.

    Each role is bound individually. Existing bindings are
    idempotent -- gcloud does not duplicate them.
    """
    for role in roles:
        run(
            [
                "gcloud",
                "projects",
                "add-iam-policy-binding",
                project,
                f"--member=serviceAccount:{sa_email}",
                f"--role={role}",
                "--condition=None",
                "--quiet",
            ],
            description=f"Granting {role}",
        )


def delete_service_account(
    project: str, sa_config: ServiceAccountConfig
) -> None:
    """Delete the function's service account if it exists."""
    email = sa_email(sa_config.name, project)

    if not resource_exists(
        [
            "gcloud",
            "iam",
            "service-accounts",
            "describe",
            email,
            f"--project={project}",
        ]
    ):
        print(f"\n  Service account '{email}' not found -- skipping.")
        return

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
        description=f"Deleting service account: {email}",
    )


# -- Deploy steps ---------------------------------------------------
def export_requirements(
    poetry_group: str,
    output_path: Path,
) -> None:
    """Generate requirements.txt from Poetry for a given group."""
    run(
        [
            "poetry",
            "export",
            "--only",
            f"main,{poetry_group}",
            "--without-hashes",
            "-f",
            "requirements.txt",
            "-o",
            str(output_path),
        ],
        description="Generating requirements.txt from Poetry",
    )


def copy_shared_utils(function_dir: Path) -> None:
    """Copy shared utilities into the function directory."""
    src = PROJECT_ROOT / "gcp" / "shared"
    dest = function_dir / "shared"
    print(f"\n=== Copying shared utilities ===")
    print(f"  -> {src} -> {dest}\n")
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(src, dest)


def gcloud_deploy(
    name: str,
    fn: FunctionConfig,
    g: GlobalConfig,
    function_dir: Path,
    run_as: str | None = None,
) -> None:
    """Run gcloud functions deploy with the resolved configuration.

    Args:
        name: Cloud Run function name.
        fn: Function configuration from functions.yaml.
        g: Global configuration from functions.yaml.
        function_dir: Path to the function source directory.
        run_as: Service account email the function runs as.
            If None, GCP uses the default compute SA.
    """
    cmd = [
        "gcloud",
        "functions",
        "deploy",
        name,
        f"--project={g.project}",
        f"--runtime={g.runtime}",
        f"--region={g.region}",
        f"--source={function_dir}",
        f"--entry-point={fn.entry_point}",
        f"--trigger-{fn.trigger}",
    ]
    if g.gen2:
        cmd.append("--gen2")
    if fn.allow_unauthenticated:
        cmd.append("--allow-unauthenticated")
    if fn.secrets:
        cmd.append(f"--set-secrets={','.join(fn.secrets)}")
    if run_as:
        cmd.append(f"--service-account={run_as}")

    run(cmd, description="Deploying to Cloud Run Functions")


def cleanup_local(function_dir: Path) -> None:
    """Remove copied shared utilities from the function directory."""
    shared = function_dir / "shared"
    print(f"\n=== Cleaning up local artifacts ===")
    if shared.exists():
        shutil.rmtree(shared)
        print(f"  -> Removed {shared}")


# -- Teardown steps -------------------------------------------------
def confirm_teardown(name: str, g: GlobalConfig, fn: FunctionConfig) -> None:
    """Require explicit confirmation before destroying resources."""
    print("\n  This will permanently delete the following resources:")
    print(f"    Function:          {name}")
    print(f"    Cloud Run service: {name} (managed by gen2)")
    print(
        f"    AR images:         {g.region}-docker.pkg.dev"
        f"/{g.project}/gcf-artifacts/{name}"
    )
    if fn.service_account:
        email = sa_email(fn.service_account.name, g.project)
        print(f"    Service account:   {email}")
    print()

    response = input("  Type the function name to confirm: ")
    if response.strip() != name:
        print("\n-> Teardown cancelled.")
        sys.exit(0)


def delete_function(name: str, g: GlobalConfig) -> None:
    """Delete the Cloud Run function (and its underlying service)."""
    run(
        [
            "gcloud",
            "functions",
            "delete",
            name,
            f"--project={g.project}",
            f"--region={g.region}",
            "--gen2",
            "--quiet",
        ],
        description="Deleting Cloud Run function",
    )


def cleanup_artifact_registry(name: str, g: GlobalConfig) -> None:
    """Remove container images left behind by gen2 deploys.

    Gen2 functions push images to Artifact Registry at:
        {region}-docker.pkg.dev/{project}/gcf-artifacts/{function-name}

    gcloud functions delete does NOT clean these up.
    """
    ar_path = f"{g.region}-docker.pkg.dev/{g.project}/gcf-artifacts/{name}"

    # Check if images exist before attempting deletion
    print(f"\n=== Checking Artifact Registry ===")
    print(f"  -> {ar_path}\n")

    result = run_quiet(
        [
            "gcloud",
            "artifacts",
            "docker",
            "images",
            "list",
            ar_path,
            f"--project={g.project}",
            "--format=json",
            "--limit=1",
        ]
    )

    if result.returncode != 0 or not json.loads(result.stdout or "[]"):
        print("  No images found -- skipping.")
        return

    run(
        [
            "gcloud",
            "artifacts",
            "docker",
            "images",
            "delete",
            ar_path,
            f"--project={g.project}",
            "--delete-tags",
            "--quiet",
        ],
        description="Removing Artifact Registry images",
    )


def cleanup_generated_requirements(function_dir: Path) -> None:
    """Clear the Poetry-generated requirements.txt contents."""
    reqs = function_dir / "requirements.txt"
    print(f"\n=== Cleaning up generated requirements ===")
    if reqs.exists():
        reqs.write_text("")
        print(f"  -> Cleared {reqs}")
    else:
        print("  No generated requirements.txt found -- skipping.")


# -- Subcommand handlers --------------------------------------------
def handle_dev(args: argparse.Namespace) -> None:
    """Serve a function locally using functions-framework."""
    config = load_config()
    fn, g, function_dir = resolve_function(config, args.function_name)

    if not function_dir.exists():
        print(
            f"\n-> Source directory not found: {function_dir}",
            file=sys.stderr,
        )
        sys.exit(1)

    source_file = function_dir / "main.py"
    if not source_file.exists():
        print(
            f"\n-> Entry file not found: {source_file}",
            file=sys.stderr,
        )
        sys.exit(1)

    print_banner("Local dev", args.function_name, g)
    print(f"\n  Entry point: {fn.entry_point}")
    print(f"  Source:      {source_file}")
    print(f"  Port:        {args.port}")

    # Check for secrets that would be injected by GCP in production
    if fn.secrets:
        print(f"\n  Note: This function expects {len(fn.secrets)} secret(s).")
        print("  Make sure they are set as environment variables locally")
        print("  (e.g., via direnv / .envrc):")
        for secret in fn.secrets:
            env_var = secret.split("=")[0]
            print(f"    - {env_var}")

    try:
        copy_shared_utils(function_dir)

        cmd = [
            "poetry",
            "run",
            "functions-framework",
            f"--target={fn.entry_point}",
            f"--source={source_file}",
            f"--port={args.port}",
            "--debug",
        ]

        run(cmd, description="Starting local development server")

    except KeyboardInterrupt:
        print("\n\n-> Server stopped.")
    finally:
        cleanup_local(function_dir)
        print(f"\n  Local dev stopped: {args.function_name}\n")


def handle_deploy(args: argparse.Namespace) -> None:
    """Build and deploy a function to Cloud Run.

    If the function declares a service_account in functions.yaml,
    the service account is created (idempotent), granted its
    declared IAM roles, and passed to gcloud via --service-account.
    """
    config = load_config()
    fn, g, function_dir = resolve_function(config, args.function_name)

    if not function_dir.exists():
        print(
            f"\n-> Source directory not found: {function_dir}",
            file=sys.stderr,
        )
        sys.exit(1)

    print_banner("Deploying", args.function_name, g)

    # Provision service account before deploying
    run_as = None
    if fn.service_account:
        run_as = create_service_account(g.project, fn.service_account)
        if fn.service_account.roles:
            grant_iam_roles(g.project, run_as, fn.service_account.roles)

    try:
        export_requirements(
            fn.poetry_group,
            function_dir / "requirements.txt",
        )
        copy_shared_utils(function_dir)
        gcloud_deploy(args.function_name, fn, g, function_dir, run_as)
    finally:
        cleanup_local(function_dir)

    print(f"\n  Deploy complete: {args.function_name}")
    if run_as:
        print(f"  Running as:      {run_as}")
    print()


def handle_teardown(args: argparse.Namespace) -> None:
    """Delete a function and clean up all its GCP resources.

    Deletion order:
        1. Cloud Run function
        2. Artifact Registry images
        3. Service account (if declared)
        4. Local artifacts
    """
    config = load_config()
    fn, g, function_dir = resolve_function(config, args.function_name)

    print_banner("Tearing down", args.function_name, g)

    if not args.force:
        confirm_teardown(args.function_name, g, fn)

    delete_function(args.function_name, g)
    cleanup_artifact_registry(args.function_name, g)

    if fn.service_account:
        delete_service_account(g.project, fn.service_account)

    cleanup_generated_requirements(function_dir)
    cleanup_local(function_dir)

    print(f"\n  Teardown complete: {args.function_name}\n")


def handle_list(args: argparse.Namespace) -> None:
    config = load_config()
    print("\nConfigured functions:\n")
    for name, fn in config.functions.items():
        print(f"  {name}")
        print(f"    source:       {fn.source_dir}")
        print(f"    entry_point:  {fn.entry_point}")
        print(f"    poetry_group: {fn.poetry_group}")
        print(f"    trigger:      {fn.trigger}")
        if fn.service_account:
            email = sa_email(fn.service_account.name, config.global_.project)
            print(f"    runs_as:      {email}")
            if fn.service_account.roles:
                for role in fn.service_account.roles:
                    print(f"      - {role}")
        else:
            print(f"    runs_as:      (default compute SA)")
        print()


# -- CLI definition -------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="manage_functions",
        description="Cloud Run Functions lifecycle manager.",
    )
    subparsers = parser.add_subparsers(
        dest="command",
        required=True,
    )

    # dev
    dev_parser = subparsers.add_parser(
        "dev",
        help="Serve a function locally using functions-framework.",
    )
    dev_parser.add_argument("function_name")
    dev_parser.add_argument(
        "--port",
        "-p",
        type=int,
        default=8080,
        help="Local server port (default: 8080).",
    )
    dev_parser.set_defaults(handler=handle_dev)

    # deploy
    deploy_parser = subparsers.add_parser(
        "deploy",
        help="Build and deploy a function to Cloud Run.",
    )
    deploy_parser.add_argument("function_name")
    deploy_parser.set_defaults(handler=handle_deploy)

    # teardown
    teardown_parser = subparsers.add_parser(
        "teardown",
        help="Delete a function and clean up its GCP resources.",
    )
    teardown_parser.add_argument("function_name")
    teardown_parser.add_argument(
        "--force",
        "-f",
        action="store_true",
        help="Skip confirmation prompt.",
    )
    teardown_parser.set_defaults(handler=handle_teardown)

    # list
    list_parser = subparsers.add_parser(
        "list",
        help="Show all functions defined in functions.yaml.",
    )
    list_parser.set_defaults(handler=handle_list)

    return parser


# -- Entrypoint -----------------------------------------------------
def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()
