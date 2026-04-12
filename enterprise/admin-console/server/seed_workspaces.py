"""Seed S3 with initial workspace files for the Consig sandbox employees."""
import boto3, os

AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

def get_bucket():
    account = boto3.client("sts", region_name=AWS_REGION).get_caller_identity()["Account"]
    return f"openclaw-tenants-{account}"

def put(s3, bucket, key, content):
    s3.put_object(Bucket=bucket, Key=key, Body=content.encode("utf-8"), ContentType="text/markdown")

EMPLOYEES = {
    "emp-rj": {"name": "RJ Burnham", "role": "Executive", "dept": "Engineering", "tz": "Europe/Lisbon", "lang": "English",
        "focus": "Evaluating OpenClaw as a secure internal assistant platform for Consig", "style": "Direct, strategic. Prefer high-signal summaries, architecture tradeoffs, and concrete next steps.",
        "memory": "Exploring Slack-connected internal assistants with access to code, logs, and scoped AWS tooling. Interested in reusable enterprise controls, not demo behavior.",
        "daily": "Provisioned the Agents Lab sandbox, enabled Bedrock models, and started reducing the sample org to a two-user Consig environment."},
    "emp-jason": {"name": "Jason Sajovic", "role": "DevOps Engineer", "dept": "Platform Team", "tz": "America/New_York", "lang": "English",
        "focus": "Platform operations, observability, deployment debugging, and AWS infrastructure review", "style": "Operational and concise. Prefer commands, root-cause hypotheses, and remediation steps.",
        "memory": "Working on infrastructure and operations workflows where an assistant can inspect code, logs, and cloud state without unsafe write access.",
        "daily": "Testing the OpenClaw sandbox as an ops-oriented assistant environment with Slack as the primary user surface."},
}

def seed():
    s3 = boto3.client("s3", region_name=AWS_REGION)
    bucket = get_bucket()
    count = 0

    for emp_id, e in EMPLOYEES.items():
        prefix = f"{emp_id}/workspace"

        # IDENTITY.md
        put(s3, bucket, f"{prefix}/IDENTITY.md", f"""# Agent Identity

- **Name:** {e['name']}'s AI Assistant
- **Role:** {e['role']} Digital Employee
- **Department:** {e['dept']}
- **Vibe:** Professional, knowledgeable, {e['style'].split('.')[0].lower()}
""")

        # USER.md
        put(s3, bucket, f"{prefix}/USER.md", f"""# User Profile — {e['name']}

- **Name:** {e['name']}
- **Role:** {e['role']}
- **Department:** {e['dept']}
- **Timezone:** {e['tz']}
- **Language:** {e['lang']}
- **Communication style:** {e['style']}
- **Current focus:** {e['focus']}
""")

        # MEMORY.md
        put(s3, bucket, f"{prefix}/MEMORY.md", f"""# Agent Memory — {e['name']}

## Key Context
{e['memory']}

## Learned Preferences
- {e['style']}
""")

        # Daily memory
        put(s3, bucket, f"{prefix}/memory/2026-03-20.md", f"""# March 20, 2026

## Session Summary
{e['daily']}
""")

        count += 1
        print(f"  {emp_id} ({e['name']}): IDENTITY.md, USER.md, MEMORY.md, memory/2026-03-20.md")

    print(f"\nDone! {count} employee workspaces seeded.")

if __name__ == "__main__":
    seed()
