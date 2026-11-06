# CloudFormation version

One template, `template.yaml`, deployed with the AWS CLI. It creates everything listed in the [main README](../README.md#what-gets-deployed). The Slack resources (the channel role, its policy and the two-way association) are created only when `SlackServiceId` is set.

## Deploy, in two passes

The caller needs permission to create IAM roles and policies and to pass them to AWS DevOps Agent (`iam:PassRole`), plus `aidevops:*` permissions on the Agent Space. An administrator in a test account works.

**First pass, without Slack:**

```bash
aws cloudformation deploy --stack-name devops-agent-slack-demo \
  --template-file cloudformation/template.yaml --capabilities CAPABILITY_IAM
```

Then [register Slack from the new Agent Space](../README.md#set-it-up-in-four-steps) and note the IDs.

**Second pass, with Slack:**

```bash
aws cloudformation deploy --stack-name devops-agent-slack-demo \
  --template-file cloudformation/template.yaml --capabilities CAPABILITY_IAM \
  --parameter-overrides SlackServiceId=<registration-id> SlackWorkspaceId=T0123456789 \
    SlackWorkspaceName=<workspace-name> SlackChannelId=C0123456789
```

| Parameter | Default | What it does |
| --- | --- | --- |
| `AgentSpaceName` | `sample-oncall` | Name of the Agent Space |
| `SlackServiceId` | empty | The Slack registration's ID. Empty skips the Slack resources |
| `SlackWorkspaceId` | empty | Slack workspace ID, starting with `T` or `E` |
| `SlackWorkspaceName` | empty | Slack workspace name |
| `SlackChannelId` | empty | ID of the private channel |
| `ChannelPolicy` | `chat-only` | `chat-only` for a policy you own with chat only, or `managed` for `AIDevOpsChannelAccessPolicy` |

`CAPABILITY_IAM` is needed because the stack creates the Agent Space role, the channel role and the chat-only policy.

## Outputs

`AgentSpaceId`, `AgentSpaceArn`, `NextStep`, and after the second pass `ChannelRoleArn` and `ChannelPolicy`:

```bash
aws cloudformation describe-stacks --stack-name devops-agent-slack-demo --query 'Stacks[0].Outputs' --output table
```

Then [bind the channel in Slack](../README.md#set-it-up-in-four-steps).

## Clean up

```bash
aws cloudformation delete-stack --stack-name devops-agent-slack-demo
aws cloudformation wait stack-delete-complete --stack-name devops-agent-slack-demo
```

This deletes the Agent Space with its investigations and chat history. The Slack registration stays until you deregister it in the console.
