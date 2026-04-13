"""Seed DynamoDB with settings (model config, security policy)."""
import argparse
import os
import json
import boto3

ORG = "ORG#acme"

def seed(table_name: str, region: str):
    ddb = boto3.resource("dynamodb", region_name=region)
    table = ddb.Table(table_name)
    items = []

    # Model config
    items.append({"PK": ORG, "SK": "CONFIG#model", "GSI1PK": "TYPE#config", "GSI1SK": "CONFIG#model",
        "default": {"modelId": "us.anthropic.claude-sonnet-4-6", "modelName": "Claude Sonnet 4.6", "inputRate": "3.00", "outputRate": "15.00"},
        "fallback": {"modelId": "amazon.nova-lite-v1:0", "modelName": "Amazon Nova Lite", "inputRate": "0.06", "outputRate": "0.24"},
        "positionOverrides": {},
        "availableModels": [
            {"modelId": "amazon.nova-pro-v1:0", "modelName": "Amazon Nova Pro", "inputRate": "0.80", "outputRate": "3.20", "enabled": True},
            {"modelId": "amazon.nova-lite-v1:0", "modelName": "Amazon Nova Lite", "inputRate": "0.06", "outputRate": "0.24", "enabled": True},
            {"modelId": "amazon.nova-premier-v1:0", "modelName": "Amazon Nova Premier", "inputRate": "2.50", "outputRate": "12.50", "enabled": True},
            {"modelId": "us.anthropic.claude-sonnet-4-6", "modelName": "Claude Sonnet 4.6", "inputRate": "3.00", "outputRate": "15.00", "enabled": True},
            {"modelId": "us.anthropic.claude-opus-4-6-v1", "modelName": "Claude Opus 4.6", "inputRate": "15.00", "outputRate": "75.00", "enabled": True},
        ],
    })

    # Security config
    items.append({"PK": ORG, "SK": "CONFIG#security", "GSI1PK": "TYPE#config", "GSI1SK": "CONFIG#security",
        "alwaysBlocked": ["install_skill", "load_extension", "eval", "rm -rf /", "chmod 777"],
        "piiDetection": {"enabled": True, "mode": "redact"},
        "dataSovereignty": {"enabled": True, "region": "us-east-1"},
        "conversationRetention": {"days": 180},
        "dockerSandbox": True,
        "fastPathRouting": True,
        "verboseAudit": False,
    })

    # KB assignments — which knowledge bases each position receives by default.
    # All positions get company policies + onboarding; role-specific KBs are layered on top.
    # Admins can adjust these from Knowledge Base → Assignments tab in the Admin Console.
    items.append({"PK": ORG, "SK": "CONFIG#kb-assignments", "GSI1PK": "TYPE#config", "GSI1SK": "CONFIG#kb-assignments",
        "positionKBs": {
            "pos-devops": ["kb-policies", "kb-onboarding", "kb-org-directory", "kb-runbooks"],
            "pos-exec":   ["kb-policies", "kb-onboarding", "kb-org-directory", "kb-finance", "kb-product"],
        },
        "employeeKBs": {},
    })

    # IM bot info — admin configures actual values via Admin Console after
    # setting up bots in the Gateway UI.  Deep link templates are fixed per
    # platform; only the bot-specific fields (appId, username) need filling in.
    items.append({"PK": ORG, "SK": "CONFIG#im-bot-info", "GSI1PK": "TYPE#config", "GSI1SK": "CONFIG#im-bot-info",
        "channels": {
            "telegram": {
                "label": "Telegram",
                "botUsername": "",
                "deepLinkTemplate": "https://t.me/{bot}?start={token}",
            },
            "discord": {
                "label": "Discord",
                "botUsername": "",
                "instructions": "Open Discord → company server → DM the bot → send the command",
            },
            "feishu": {
                "label": "Feishu / Lark",
                "botUsername": "",
                "feishuAppId": "",
                "deepLinkTemplate": "https://applink.feishu.cn/client/bot/open?appId={appId}",
            },
            "slack": {
                "label": "Slack",
                "botUsername": "",
            },
            "whatsapp": {
                "label": "WhatsApp",
                "botUsername": "",
            },
        },
    })

    print(f"Writing {len(items)} config items...")
    with table.batch_writer() as batch:
        for item in items:
            batch.put_item(Item=item)
    print("Done!")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--table", default=os.environ.get("DYNAMODB_TABLE", "openclaw"))
    parser.add_argument("--region", default=os.environ.get("AWS_REGION", "us-east-1"))
    args = parser.parse_args()
    seed(args.table, args.region)
