"""
Seed workspace files for the Consig sandbox employees.
Creates IDENTITY.md, USER.md, MEMORY.md, and a daily memory file for each.
Skips employees that already have workspace files in S3.
"""
import argparse
import os
import boto3
from datetime import datetime, timezone

EMPLOYEES = {
    "emp-rj": {"name": "RJ Burnham", "pos": "pos-exec", "posName": "Executive", "dept": "Engineering"},
    "emp-jason": {"name": "Jason Sajovic", "pos": "pos-devops", "posName": "DevOps Engineer", "dept": "Platform Team"},
}

USER_TEMPLATES = {
    "pos-devops": "# User Preferences\n\n- Communication: direct, operational\n- Focus: infrastructure as code, CI/CD, monitoring\n- Tools: Terraform, Docker, Kubernetes, GitHub Actions\n- Always consider security and cost",
    "pos-exec": "# User Preferences\n\n- Communication: direct, strategic\n- Focus: architecture tradeoffs, operating leverage, and risk\n- Format: concise summaries first, details on request\n- Always tie recommendations to execution reality",
}


def seed(bucket: str, region: str):
    s3 = boto3.client("s3", region_name=region)
    now = datetime.now(timezone.utc)
    today = now.strftime("%Y-%m-%d")
    created = 0
    skipped = 0

    for emp_id, info in EMPLOYEES.items():
        # Check if workspace already exists
        prefix = f"{emp_id}/workspace/"
        try:
            resp = s3.list_objects_v2(Bucket=bucket, Prefix=prefix, MaxKeys=1)
            if resp.get("KeyCount", 0) > 0:
                existing = resp["Contents"][0]["Key"]
                # Check if it has IDENTITY.md (full workspace) or just SOUL.md (partial)
                resp2 = s3.list_objects_v2(Bucket=bucket, Prefix=f"{prefix}IDENTITY.md", MaxKeys=1)
                if resp2.get("KeyCount", 0) > 0:
                    print(f"  {emp_id}: already has full workspace, skipping")
                    skipped += 1
                    continue
                else:
                    print(f"  {emp_id}: partial workspace (no IDENTITY.md), creating missing files")
        except Exception:
            pass

        pos = info["pos"]
        name = info["name"]

        # IDENTITY.md
        identity = f"# Agent Identity\n\n- **Name**: {name}'s AI Assistant\n- **Position**: {info['posName']}\n- **Department**: {info['dept']}\n- **Company**: ACME Corp\n- **Platform**: OpenClaw Enterprise\n"
        s3.put_object(Bucket=bucket, Key=f"{prefix}IDENTITY.md", Body=identity.encode(), ContentType="text/markdown")

        # USER.md
        user_md = USER_TEMPLATES.get(pos, "# User Preferences\n\n- Default preferences")
        s3.put_object(Bucket=bucket, Key=f"{prefix}USER.md", Body=user_md.encode(), ContentType="text/markdown")

        # MEMORY.md
        memory = f"# Long-term Memory\n\n- Agent activated on {today}\n- Position: {info['posName']} at ACME Corp\n- Department: {info['dept']}\n"
        s3.put_object(Bucket=bucket, Key=f"{prefix}MEMORY.md", Body=memory.encode(), ContentType="text/markdown")

        # Daily memory
        daily = f"# {today}\n\n- Workspace initialized for {name}\n- Position: {info['posName']}\n"
        s3.put_object(Bucket=bucket, Key=f"{prefix}memory/{today}.md", Body=daily.encode(), ContentType="text/markdown")

        created += 1
        print(f"  {emp_id}: workspace created ({info['posName']})")

    print(f"\nDone! Created: {created}, Skipped: {skipped}, Total: {len(EMPLOYEES)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket", default=os.environ.get("S3_BUCKET", ""))
    parser.add_argument("--region", default=os.environ.get("AWS_REGION", "us-east-1"))
    args = parser.parse_args()
    if not args.bucket:
        print("ERROR: --bucket required or set S3_BUCKET env var")
        exit(1)
    seed(args.bucket, args.region)
