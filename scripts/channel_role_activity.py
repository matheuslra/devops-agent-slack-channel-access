"""Show what a Slack channel's role did, from CloudTrail.

Read-only. It finds each time AWS DevOps Agent assumed the channel role in the time window, then lists the API calls
made with that session's credentials. Use it after an incident to see what the channel asked the agent to do.
CloudTrail's LookupEvents covers management events from the last 90 days in this Region.

Usage: python scripts/channel_role_activity.py --role-arn <ChannelRoleArn> [--hours 24] [--region us-east-1]
"""

import argparse
import json
import sys
import time
from datetime import datetime, timedelta, timezone

import boto3


def lookup(cloudtrail, attribute, value, start, end):
    pages = cloudtrail.get_paginator("lookup_events").paginate(
        LookupAttributes=[{"AttributeKey": attribute, "AttributeValue": value}], StartTime=start, EndTime=end
    )
    for page in pages:
        for event in page["Events"]:
            yield json.loads(event["CloudTrailEvent"])
        time.sleep(0.5)  # LookupEvents allows two requests per second per account and Region.


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--role-arn", required=True, help="The ChannelRoleArn output of the stack")
    parser.add_argument("--hours", type=int, default=24)
    parser.add_argument("--region", default=boto3.session.Session().region_name or "us-east-1")
    args = parser.parse_args()

    cloudtrail = boto3.client("cloudtrail", region_name=args.region)
    end = datetime.now(timezone.utc)
    start = end - timedelta(hours=args.hours)

    sessions = 0
    for event in lookup(cloudtrail, "EventName", "AssumeRole", start, end):
        request = event.get("requestParameters") or {}
        if request.get("roleArn") != args.role_arn:
            continue
        sessions += 1
        tags = {t.get("key"): t.get("value") for t in request.get("tags", []) if isinstance(t, dict)}
        print(f'\n{event["eventTime"]}  assumed by {event.get("userIdentity", {}).get("invokedBy") or event.get("sourceIPAddress")}')
        if tags:
            print(f"  session tags: {tags}")
        key = ((event.get("responseElements") or {}).get("credentials") or {}).get("accessKeyId")
        if not key:
            print("  (CloudTrail didn't record the session's access key, so its calls can't be linked here)")
            continue
        calls = list(lookup(cloudtrail, "AccessKeyId", key, start, end))
        for call in sorted(calls, key=lambda c: c["eventTime"]):
            print(f'  {call["eventTime"]}  {call["eventSource"]}  {call["eventName"]}')
        if not calls:
            print("  no management events recorded for this session yet")

    print(f"\n{sessions} session(s) of {args.role_arn} in the last {args.hours} hours.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
