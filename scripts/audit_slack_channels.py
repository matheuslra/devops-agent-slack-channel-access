"""List every Slack channel that can talk to AWS DevOps Agent, and what its role can do.

Read-only. For each Agent Space in the Region, it finds Slack associations with bidirectional mode on, then reads
the IAM role each one uses: which policies are attached, which aidevops actions they allow beyond chat, and
whether the trust policy is limited to one Agent Space. It exits 1 when it finds something worth a look, so you can
run it on a schedule.

Usage: python scripts/audit_slack_channels.py [--region us-east-1]
"""

import argparse
import json
import sys
import urllib.parse

import boto3

MANAGED_CHANNEL_POLICY = "AIDevOpsChannelAccessPolicy"
CHAT_ONLY = {"aidevops:CreateChat", "aidevops:SendMessage"}


def paged(client, operation, key, **kwargs):
    for page in client.get_paginator(operation).paginate(**kwargs):
        yield from page.get(key, [])


def as_list(value):
    return value if isinstance(value, list) else [value]


def allowed_actions(document):
    """aidevops actions an IAM policy document allows. Wildcards are kept as written."""
    actions = set()
    for statement in as_list(document.get("Statement", [])):
        if statement.get("Effect") != "Allow":
            continue
        for action in as_list(statement.get("Action", [])):
            if action == "*" or action.lower().startswith("aidevops:"):
                actions.add(action)
    return actions


def role_report(iam, role_arn):
    name = role_arn.split("/")[-1]
    role = iam.get_role(RoleName=name)["Role"]
    trust = role["AssumeRolePolicyDocument"]
    if isinstance(trust, str):
        trust = json.loads(urllib.parse.unquote(trust))

    attached, actions = [], set()
    for policy in paged(iam, "list_attached_role_policies", "AttachedPolicies", RoleName=name):
        meta = iam.get_policy(PolicyArn=policy["PolicyArn"])["Policy"]
        version = iam.get_policy_version(PolicyArn=policy["PolicyArn"], VersionId=meta["DefaultVersionId"])
        attached.append(f'{policy["PolicyName"]} ({meta["DefaultVersionId"]})')
        actions |= allowed_actions(version["PolicyVersion"]["Document"])
    for policy_name in paged(iam, "list_role_policies", "PolicyNames", RoleName=name):
        document = iam.get_role_policy(RoleName=name, PolicyName=policy_name)["PolicyDocument"]
        attached.append(f"{policy_name} (inline)")
        actions |= allowed_actions(document)

    source_arns = set()
    for statement in as_list(trust.get("Statement", [])):
        for operator in ("ArnEquals", "ArnLike", "StringEquals", "StringLike"):
            value = statement.get("Condition", {}).get(operator, {}).get("aws:SourceArn")
            if value:
                source_arns.update(as_list(value))
    return attached, actions, source_arns


def slack_channels(association):
    targets = association["configuration"]["slack"].get("transmissionTarget", {})
    return sorted({t["channelId"] for t in targets.values() if isinstance(t, dict) and t.get("channelId")})


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--region", default=boto3.session.Session().region_name or "us-east-1")
    args = parser.parse_args()

    agent = boto3.client("devops-agent", region_name=args.region)
    iam = boto3.client("iam")
    findings = 0

    for space in paged(agent, "list_agent_spaces", "agentSpaces"):
        for association in paged(agent, "list_associations", "associations", agentSpaceId=space["agentSpaceId"]):
            slack = association.get("configuration", {}).get("slack")
            if not slack or not slack.get("bidirectional", {}).get("enabled"):
                continue
            role_arn = slack["bidirectional"].get("roleArn", "")
            print(f'\nAgent Space "{space["name"]}" ({space["agentSpaceId"]})')
            print(f'  Slack workspace {slack.get("workspaceName")}, channel {", ".join(slack_channels(association)) or "?"}')
            print(f"  Channel role: {role_arn}")
            try:
                attached, actions, source_arns = role_report(iam, role_arn)
            except iam.exceptions.NoSuchEntityException:
                print("  ! The role doesn't exist. The channel can't chat until it does.")
                findings += 1
                continue

            print(f'  Policies: {", ".join(attached) or "none"}')
            beyond_chat = sorted(actions - CHAT_ONLY)
            if any(MANAGED_CHANNEL_POLICY in p for p in attached):
                print(f"  ! Uses the AWS managed {MANAGED_CHANNEL_POLICY}. AWS can add actions to it without you changing anything.")
                findings += 1
            if beyond_chat:
                print(f"  ! Allows {len(beyond_chat)} aidevops actions beyond chat: {', '.join(beyond_chat)}")
                findings += 1
            if not source_arns or any(arn.endswith("/*") or arn == "*" for arn in source_arns):
                print("  ! The trust policy isn't limited to one Agent Space, so another Agent Space could use this role.")
                findings += 1
            print("  Everyone in this private channel acts through this role. Review who's in it like you'd review an IAM group.")

    print(f"\n{findings} finding(s).")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
