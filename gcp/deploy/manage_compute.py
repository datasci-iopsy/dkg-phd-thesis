"""Compute Engine VM lifecycle manager for power analysis simulations.

Provisions a single high-CPU VM for running R power analysis
simulations. The VM runs Ubuntu 22.04 LTS and is bootstrapped
with setup_gcp_vm.sh (R + renv).

No service account or GCP API credentials needed -- the VM
only runs R, no GCP SDK calls.

Usage:
    python manage_compute.py setup
    python manage_compute.py status
    python manage_compute.py ssh
    python manage_compute.py scp
    python manage_compute.py teardown
    python manage_compute.py teardown --force
    python manage_compute.py --help
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

import yaml
from pydantic import BaseModel, Field, field_validator

# -- Path resolution -----------------------------------------------
DEPLOY_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = DEPLOY_DIR.parents[1]
COMPUTE_CONFIG_PATH = DEPLOY_DIR / "compute.yaml"
FUNCTIONS_CONFIG_PATH = DEPLOY_DIR / "functions.yaml"

REQUIRED_APIS = [
    "compute.googleapis.com",
]


# -- Configuration models ------------------------------------------
class ComputeSettings(BaseModel):
    vm_name: str
    machine_type: str
    zone: str
    boot_disk_size_gb: int
    image_family: str
    image_project: str
    setup_script: str
    remote_results_dir: str
    available_zones: list[str]

    @field_validator("zone")
    @classmethod
    def zone_must_be_available(cls, v: str, info: object) -> str:
        zones = info.data.get("available_zones", [])
        if zones and v not in zones:
            raise ValueError(
                f"Zone '{v}' not in available_zones: {', '.join(zones)}"
            )
        return v


class ComputeConfig(BaseModel):
    compute: ComputeSettings


class FunctionsGlobal(BaseModel):
    """Minimal model -- only the fields manage_compute needs."""

    project: str
    region: str


class FunctionsConfig(BaseModel):
    global_: FunctionsGlobal = Field(alias="global")


# -- Config loading ------------------------------------------------
def load_compute_config() -> ComputeConfig:
    """Parse and validate compute.yaml."""
    raw = yaml.safe_load(COMPUTE_CONFIG_PATH.read_text())
    return ComputeConfig.model_validate(raw)


def load_functions_config() -> FunctionsConfig:
    """Parse functions.yaml for project ID."""
    raw = yaml.safe_load(FUNCTIONS_CONFIG_PATH.read_text())
    return FunctionsConfig.model_validate(raw)


# -- Helpers (same patterns as manage_pubsub.py) -------------------
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
    """Run a gcloud command with --format=json and parse output."""
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


def print_banner(action: str, vm: ComputeSettings, project: str) -> None:
    """Print a formatted operation banner."""
    print(f"\n+{'=' * 55}+")
    print(f"|  {action:<53}|")
    print(f"|  Project:  {project:<44}|")
    print(f"|  VM:       {vm.vm_name:<44}|")
    print(f"|  Zone:     {vm.zone:<44}|")
    print(f"|  Machine:  {vm.machine_type:<44}|")
    print(f"+{'=' * 55}+")


# -- VM operations -------------------------------------------------
def vm_exists(project: str, zone: str, vm_name: str) -> bool:
    """Check whether the VM instance exists."""
    return resource_exists(
        [
            "gcloud",
            "compute",
            "instances",
            "describe",
            vm_name,
            f"--project={project}",
            f"--zone={zone}",
        ]
    )


def get_vm_info(project: str, zone: str, vm_name: str) -> dict | None:
    """Get VM instance details as a dict."""
    return run_json(
        [
            "gcloud",
            "compute",
            "instances",
            "describe",
            vm_name,
            f"--project={project}",
            f"--zone={zone}",
            "--format=json",
        ]
    )


def get_external_ip(vm_info: dict) -> str | None:
    """Extract the external IP from VM info JSON."""
    try:
        for iface in vm_info["networkInterfaces"]:
            for access in iface.get("accessConfigs", []):
                ip = access.get("natIP")
                if ip:
                    return ip
    except (KeyError, TypeError, IndexError):
        pass
    return None


# -- Subcommand handlers -------------------------------------------
def handle_setup(args: argparse.Namespace) -> None:
    """Create the Compute Engine VM (idempotent).

    Steps:
        1. Check if VM already exists
        2. Enable compute API
        3. Create VM with specified machine type and disk
        4. Print SSH and next-step instructions
    """
    cfg = load_compute_config()
    fn_cfg = load_functions_config()
    vm = cfg.compute
    project = fn_cfg.global_.project

    print_banner("Setting up Compute Engine VM", vm, project)

    if vm_exists(project, vm.zone, vm.vm_name):
        info = get_vm_info(project, vm.zone, vm.vm_name)
        status = info.get("status", "UNKNOWN") if info else "UNKNOWN"
        ip = get_external_ip(info) if info else None
        print(f"\n  VM '{vm.vm_name}' already exists (status: {status}).")
        if ip:
            print(f"  External IP: {ip}")
        print("\n  To connect: python manage_compute.py ssh")
        print()
        return

    # Step 1: Enable compute API
    run(
        [
            "gcloud",
            "services",
            "enable",
            *REQUIRED_APIS,
            f"--project={project}",
        ],
        description="Enabling Compute Engine API",
    )

    # Step 2: Create VM
    run(
        [
            "gcloud",
            "compute",
            "instances",
            "create",
            vm.vm_name,
            f"--project={project}",
            f"--zone={vm.zone}",
            f"--machine-type={vm.machine_type}",
            f"--image-family={vm.image_family}",
            f"--image-project={vm.image_project}",
            f"--boot-disk-size={vm.boot_disk_size_gb}GB",
            "--boot-disk-type=pd-ssd",
        ],
        description=(
            f"Creating VM: {vm.vm_name} ({vm.machine_type} in {vm.zone})"
        ),
    )

    # Print results
    info = get_vm_info(project, vm.zone, vm.vm_name)
    ip = get_external_ip(info) if info else None

    print(f"\n+{'=' * 55}+")
    print(f"|  {'Setup complete':<53}|")
    print(f"+{'=' * 55}+")
    if ip:
        print(f"\n  External IP: {ip}")
    print("\n  Next steps:")
    print("    1. python manage_compute.py ssh")
    print("    2. git clone <repo-url> dkg-phd-thesis")
    print(f"    3. cd dkg-phd-thesis && bash {vm.setup_script}")
    print("    4. make power_analysis_gcp_benchmark")
    print("    5. make power_analysis_gcp_prod")
    print()


def handle_status(args: argparse.Namespace) -> None:
    """Show VM state, zone, machine type, and external IP."""
    cfg = load_compute_config()
    fn_cfg = load_functions_config()
    vm = cfg.compute
    project = fn_cfg.global_.project

    print_banner("Compute Engine status", vm, project)

    if not vm_exists(project, vm.zone, vm.vm_name):
        print(f"\n  VM '{vm.vm_name}' not found in {vm.zone}.")
        print("  Run 'setup' to create it.\n")
        return

    info = get_vm_info(project, vm.zone, vm.vm_name)
    if not info:
        print("\n  Could not retrieve VM details.\n")
        return

    status = info.get("status", "UNKNOWN")
    machine = info.get("machineType", "").split("/")[-1]
    ip = get_external_ip(info)
    creation = info.get("creationTimestamp", "unknown")

    print(f"\n  Status:       {status}")
    print(f"  Machine type: {machine}")
    print(f"  Zone:         {vm.zone}")
    print(f"  External IP:  {ip or 'none'}")
    print(f"  Created:      {creation}")
    print()


def handle_ssh(args: argparse.Namespace) -> None:
    """SSH into the VM via gcloud compute ssh."""
    cfg = load_compute_config()
    fn_cfg = load_functions_config()
    vm = cfg.compute
    project = fn_cfg.global_.project

    if not vm_exists(project, vm.zone, vm.vm_name):
        print(
            f"\n-> VM '{vm.vm_name}' not found. Run 'setup' first.",
            file=sys.stderr,
        )
        sys.exit(1)

    cmd = [
        "gcloud",
        "compute",
        "ssh",
        vm.vm_name,
        f"--project={project}",
        f"--zone={vm.zone}",
    ]

    # Pass through any extra args after --
    if args.ssh_args:
        cmd.append("--")
        cmd.extend(args.ssh_args)

    print(f"\n  Connecting to {vm.vm_name} in {vm.zone}...")
    print(f"  -> {' '.join(cmd)}\n")
    result = subprocess.run(cmd, check=False)
    sys.exit(result.returncode)


def handle_scp(args: argparse.Namespace) -> None:
    """Pull results files from the VM to the local machine.

    Copies the remote results directory to the local
    analysis/run_power_analysis/data/ directory.
    """
    cfg = load_compute_config()
    fn_cfg = load_functions_config()
    vm = cfg.compute
    project = fn_cfg.global_.project

    if not vm_exists(project, vm.zone, vm.vm_name):
        print(
            f"\n-> VM '{vm.vm_name}' not found. Run 'setup' first.",
            file=sys.stderr,
        )
        sys.exit(1)

    local_dest = PROJECT_ROOT / "analysis" / "run_power_analysis" / "data"
    local_dest.mkdir(parents=True, exist_ok=True)
    remote_src = f"{vm.vm_name}:~/{vm.remote_results_dir}/"

    print("\n  Pulling results from VM...")
    print(f"  Remote: ~/{vm.remote_results_dir}/")
    print(f"  Local:  {local_dest}/")

    run(
        [
            "gcloud",
            "compute",
            "scp",
            "--recurse",
            remote_src,
            str(local_dest),
            f"--project={project}",
            f"--zone={vm.zone}",
        ],
        description="Copying results from VM",
    )

    print(f"\n  Results copied to: {local_dest}/\n")


def handle_teardown(args: argparse.Namespace) -> None:
    """Delete the VM (with confirmation unless --force)."""
    cfg = load_compute_config()
    fn_cfg = load_functions_config()
    vm = cfg.compute
    project = fn_cfg.global_.project

    print_banner("Tearing down Compute Engine VM", vm, project)

    if not vm_exists(project, vm.zone, vm.vm_name):
        print(f"\n  VM '{vm.vm_name}' not found -- nothing to do.\n")
        return

    if not args.force:
        print("\n  This will permanently delete:")
        print(f"    VM:   {vm.vm_name}")
        print(f"    Zone: {vm.zone}")
        print(f"    Type: {vm.machine_type}")
        print()
        print("  WARNING: Any unsaved results on the VM will be lost.")
        print("  Run 'scp' first to pull results.\n")
        response = input("  Type 'yes' to confirm: ")
        if response.strip().lower() != "yes":
            print("\n  Teardown cancelled.\n")
            return

    run(
        [
            "gcloud",
            "compute",
            "instances",
            "delete",
            vm.vm_name,
            f"--project={project}",
            f"--zone={vm.zone}",
            "--quiet",
        ],
        description=f"Deleting VM: {vm.vm_name}",
    )

    print("\n  Teardown complete.\n")


# -- CLI definition ------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="manage_compute",
        description=(
            "Compute Engine VM lifecycle manager "
            "for power analysis simulations."
        ),
    )
    subparsers = parser.add_subparsers(
        dest="command",
        required=True,
    )

    # setup
    setup_parser = subparsers.add_parser(
        "setup",
        help="Create the VM (idempotent).",
    )
    setup_parser.set_defaults(handler=handle_setup)

    # status
    status_parser = subparsers.add_parser(
        "status",
        help="Show VM state, zone, machine type, IP.",
    )
    status_parser.set_defaults(handler=handle_status)

    # ssh
    ssh_parser = subparsers.add_parser(
        "ssh",
        help="SSH into the VM.",
    )
    ssh_parser.add_argument(
        "ssh_args",
        nargs="*",
        help=("Extra arguments passed after -- to gcloud compute ssh."),
    )
    ssh_parser.set_defaults(handler=handle_ssh)

    # scp
    scp_parser = subparsers.add_parser(
        "scp",
        help="Pull results files from the VM.",
    )
    scp_parser.set_defaults(handler=handle_scp)

    # teardown
    teardown_parser = subparsers.add_parser(
        "teardown",
        help="Delete the VM.",
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
