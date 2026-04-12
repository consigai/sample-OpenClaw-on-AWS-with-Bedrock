"""
Seed DynamoDB with a minimal Consig sandbox org.
Single-table design: PK/SK pattern from PRD §15.

Usage: python seed_dynamodb.py [--region us-east-1] [--table openclaw]
"""
import argparse
import os
import json
import time
import boto3

ORG = "ORG#acme"

def seed(table_name: str, region: str):
    ddb = boto3.resource("dynamodb", region_name=region)
    table = ddb.Table(table_name)

    items = []

    # --- Organization meta ---
    items.append({"PK": ORG, "SK": "META", "GSI1PK": "TYPE#org", "GSI1SK": ORG,
        "name": "Consig AI", "plan": "enterprise", "createdAt": "2026-01-10T00:00:00Z"})

    # --- Departments ---
    depts = [
        ("dept-eng", "Engineering", None, 2),
        ("dept-eng-platform", "Platform Team", "dept-eng", 1),
    ]
    for did, name, parent, hc in depts:
        items.append({"PK": ORG, "SK": f"DEPT#{did}", "GSI1PK": "TYPE#dept", "GSI1SK": f"DEPT#{did}",
            "id": did, "name": name, "parentId": parent, "headCount": hc, "createdAt": "2026-01-10T00:00:00Z"})

    # --- Positions ---
    positions = [
        ("pos-devops", "DevOps Engineer", "dept-eng-platform", "Platform Team", ["jina-reader","deep-research","github-pr"], ["web_search","shell","browser","file","file_write","code_execution"], 1),
        ("pos-exec", "Executive", "dept-eng", "Engineering", ["jina-reader","deep-research","web_search"], ["web_search","shell","browser","file","file_write","code_execution"], 1),
    ]
    for pid, name, did, dname, skills, tools, mc in positions:
        items.append({"PK": ORG, "SK": f"POS#{pid}", "GSI1PK": "TYPE#pos", "GSI1SK": f"POS#{pid}",
            "id": pid, "name": name, "departmentId": did, "departmentName": dname,
            "defaultSkills": skills, "toolAllowlist": tools, "memberCount": mc, "createdAt": "2026-01-20T00:00:00Z"})

    # --- Employees ---
    employees = [
        ("emp-rj", "RJ Burnham", "EMP-001", "rj@consig.ai", "pos-exec", "Executive", "dept-eng", "Engineering", ["slack"], "agent-exec-rj", "active"),
        ("emp-jason", "Jason Sajovic", "EMP-002", "jason@consig.ai", "pos-devops", "DevOps Engineer", "dept-eng-platform", "Platform Team", ["slack"], "agent-devops-jason", "active"),
    ]
    for eid, name, eno, email, pid, pname, did, dname, chs, aid, ast in employees:
        item = {"PK": ORG, "SK": f"EMP#{eid}", "GSI1PK": "TYPE#emp", "GSI1SK": f"EMP#{eid}",
            "id": eid, "name": name, "email": email, "employeeNo": eno, "positionId": pid, "positionName": pname,
            "departmentId": did, "departmentName": dname, "channels": chs, "agentStatus": ast, "createdAt": "2026-01-20T00:00:00Z"}
        if aid:
            item["agentId"] = aid
        items.append(item)

    # --- Agents ---
    agents = [
        ("agent-exec-rj", "Executive Agent - RJ", "emp-rj", "RJ Burnham", "pos-exec", "Executive", "active", 4.8, ["jina-reader","deep-research","web_search"], ["slack"]),
        ("agent-devops-jason", "DevOps Agent - Jason", "emp-jason", "Jason Sajovic", "pos-devops", "DevOps Engineer", "active", 4.7, ["jina-reader","deep-research","github-pr"], ["slack"]),
    ]
    for aid, name, eid, ename, pid, pname, status, qs, skills, chs in agents:
        item = {"PK": ORG, "SK": f"AGENT#{aid}", "GSI1PK": "TYPE#agent", "GSI1SK": f"AGENT#{aid}",
            "id": aid, "name": name, "employeeName": ename, "positionId": pid, "positionName": pname,
            "status": status, "qualityScore": str(qs), "skills": skills, "channels": chs,
            "soulVersions": {"global": 3, "position": 1, "personal": 1 if eid else 0},
            "createdAt": "2026-01-25T00:00:00Z", "updatedAt": "2026-03-20T00:00:00Z"}
        if eid:
            item["employeeId"] = eid
        items.append(item)

    # --- Bindings ---
    # Every employee automatically gets a 1:1 Serverless agent.
    # Admin can upgrade to Always-on (Fargate) for scheduled tasks and instant response.
    agent_name_map = {aid: aname for aid, aname, *_ in agents}
    bindings = []
    for eid, ename, _eno, _email, _pid, _pname, _did, _dname, chs, aid, _ast in employees:
        if not aid:
            continue
        primary_ch = chs[0] if chs else "serverless"
        bid = f"bind-{eid.replace('emp-', '')}-auto"
        aname = agent_name_map.get(aid, aid)
        bindings.append((bid, eid, ename, aid, aname, "1:1", primary_ch, "bound"))
    for bid, eid, ename, aid, aname, mode, ch, st in bindings:
        items.append({"PK": ORG, "SK": f"BIND#{bid}", "GSI1PK": f"AGENT#{aid}", "GSI1SK": f"BIND#{bid}",
            "id": bid, "employeeId": eid, "employeeName": ename, "agentId": aid, "agentName": aname,
            "mode": mode, "channel": ch, "status": st, "createdAt": "2026-02-01T00:00:00Z"})

    # --- Write all items ---
    print(f"Writing {len(items)} items to {table_name}...")
    with table.batch_writer() as batch:
        for item in items:
            batch.put_item(Item=item)
    print(f"Done! {len(items)} items seeded.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--table", default=os.environ.get("DYNAMODB_TABLE", "openclaw"))
    parser.add_argument("--region", default=os.environ.get("AWS_REGION", "us-east-1"))
    args = parser.parse_args()
    seed(args.table, args.region)
