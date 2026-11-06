# AWS CDK version (TypeScript)

The same stack as the CloudFormation version, written as a CDK app. It uses the L1 constructs `CfnAgentSpace` and `CfnAssociation` from `aws-cdk-lib/aws-devopsagent` (there's no L2 yet) and L2 IAM constructs for the roles. `lib/stack.ts` defines the resources, `bin/app.ts` reads the settings, and it deploys as the stack `devops-agent-slack-demo`.

## Before you start

- Node.js and npm. CI uses Node.js 24.
- A CDK-bootstrapped account and Region. If you've never used CDK there, run this once:

  ```bash
  cd cdk && npm ci && npx cdk bootstrap
  ```

- Permission to create IAM roles and policies, pass them to AWS DevOps Agent (`iam:PassRole`), and manage the Agent Space. An administrator in a test account works.

## Deploy, in two passes

**First pass, without Slack:**

```bash
cd cdk
npm ci
npx cdk deploy
```

Then [register Slack from the new Agent Space](../README.md#set-it-up-in-four-steps) and note the IDs.

**Second pass, with Slack:**

```bash
npx cdk deploy --parameters SlackServiceId=<registration-id> --parameters SlackWorkspaceId=T0123456789 \
  --parameters SlackWorkspaceName=<workspace-name> --parameters SlackChannelId=C0123456789
```

The Slack values are stack parameters, so the app synthesizes without them. These settings are CDK context instead:

| Context key | Default | What it does |
| --- | --- | --- |
| `agentSpaceName` | `sample-oncall` | Name of the Agent Space |
| `channelPolicy` | `chat-only` | `chat-only` for a policy you own with chat only, or `managed` for `AIDevOpsChannelAccessPolicy` |

```bash
npx cdk deploy -c channelPolicy=managed --parameters ...
```

## Outputs

`npx cdk deploy` prints `AgentSpaceId`, `AgentSpaceArn`, `NextStep`, and after the second pass `ChannelRoleArn` and `ChannelPolicy`. Then [bind the channel in Slack](../README.md#set-it-up-in-four-steps).

## Clean up

From `cdk/`:

```bash
npx cdk destroy
```

This deletes the Agent Space with its investigations and chat history. The Slack registration stays until you deregister it in the console.
