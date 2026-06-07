#!/usr/bin/env python3
"""
ansible/inventories/aws_ec2_inventory.py
------------------------------------------
Dynamic inventory for Ansible → pulls Windows Spot EC2 instances
from AWS using boto3.

Usage (standalone test):
  python3 aws_ec2_inventory.py --list
  python3 aws_ec2_inventory.py --host <ip>

GitHub Actions sets AWS credentials via OIDC env vars automatically.
"""

import argparse
import json
import os
import sys

try:
    import boto3
except ImportError:
    print("boto3 not installed. Run: pip install boto3", file=sys.stderr)
    sys.exit(1)


def get_instances(region: str, project_tag: str) -> dict:
    """Query EC2 for running Windows instances tagged with our project."""
    ec2 = boto3.client("ec2", region_name=region)

    response = ec2.describe_instances(
        Filters=[
            {"Name": "instance-state-name", "Values": ["running"]},
            {"Name": "tag:Project",         "Values": [project_tag]},
        ]
    )

    inventory = {
        "windows": {
            "hosts": [],
            "vars": {
                # WinRM connection settings (Ansible Windows)
                "ansible_connection":          "winrm",
                "ansible_winrm_transport":     "basic",
                "ansible_winrm_port":          5985,
                "ansible_winrm_scheme":        "http",
                "ansible_winrm_server_cert_validation": "ignore",
                "ansible_user":                os.environ.get("ANSIBLE_WINRM_USER", "ansible_admin"),
                "ansible_password":            os.environ.get("ANSIBLE_WINRM_PASSWORD", ""),
            },
        },
        "_meta": {
            "hostvars": {}
        }
    }

    for reservation in response["Reservations"]:
        for instance in reservation["Instances"]:
            public_ip = instance.get("PublicIpAddress")
            if not public_ip:
                continue  # skip instances without a public IP

            instance_id = instance["InstanceId"]
            name_tag = next(
                (t["Value"] for t in instance.get("Tags", []) if t["Key"] == "Name"),
                instance_id
            )

            inventory["windows"]["hosts"].append(public_ip)
            inventory["_meta"]["hostvars"][public_ip] = {
                "instance_id":   instance_id,
                "instance_name": name_tag,
                "instance_type": instance.get("InstanceType"),
                "availability_zone": instance["Placement"]["AvailabilityZone"],
                "private_ip":    instance.get("PrivateIpAddress"),
            }

    return inventory


def main():
    parser = argparse.ArgumentParser(description="AWS EC2 Dynamic Inventory")
    parser.add_argument("--list", action="store_true", help="List all hosts")
    parser.add_argument("--host", help="Get vars for a specific host")
    args = parser.parse_args()

    region      = os.environ.get("AWS_DEFAULT_REGION", "ap-southeast-2")
    project_tag = os.environ.get("PROJECT_TAG", "terraform-ansible-demo")

    inventory = get_instances(region, project_tag)

    if args.host:
        print(json.dumps(inventory["_meta"]["hostvars"].get(args.host, {}), indent=2))
    else:
        print(json.dumps(inventory, indent=2))


if __name__ == "__main__":
    main()
