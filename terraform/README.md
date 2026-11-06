# Terraform version

The same stack as the CloudFormation version, in Terraform. It uses two providers: `hashicorp/awscc` 1.109 or later for the Agent Space and its associations (`awscc_devopsagent_agent_space` and `awscc_devopsagent_association`, including Slack's `bidirectional` block), and `hashicorp/aws` for the IAM roles and policies.

## Before you start

- Terraform 1.6 or later.
- AWS credentials for the target account, for example `export AWS_PROFILE=my-test-account`, with permission to create IAM roles and policies, pass them to AWS DevOps Agent (`iam:PassRole`), and manage the Agent Space.

## Deploy, in two passes

**First pass, without Slack:**

```bash
cd terraform
terraform init
terraform apply
```

Then [register Slack from the new Agent Space](../README.md#set-it-up-in-four-steps) and note the IDs.

**Second pass, with Slack:**

```bash
terraform apply -var slack_service_id=<registration-id> -var slack_workspace_id=T0123456789 \
  -var slack_workspace_name=<workspace-name> -var slack_channel_id=C0123456789
```

To keep those values out of your shell history, put them in a `terraform.tfvars` file instead. `.gitignore` already excludes it.

| Variable | Default | What it does |
| --- | --- | --- |
| `region` | `us-east-1` | A Region where AWS DevOps Agent is available. The Agent Space and its data live here |
| `agent_space_name` | `sample-oncall` | Name of the Agent Space |
| `slack_service_id` | empty | The Slack registration's ID. Empty skips the Slack resources |
| `slack_workspace_id` | empty | Slack workspace ID, starting with `T` or `E` |
| `slack_workspace_name` | empty | Slack workspace name |
| `slack_channel_id` | empty | ID of the private channel |
| `channel_policy` | `chat-only` | `chat-only` for a policy you own with chat only, or `managed` for `AIDevOpsChannelAccessPolicy` |

## Outputs

```bash
terraform output
```

That lists `agent_space_id`, `agent_space_arn`, `channel_role_arn` (empty until the second pass), `channel_policy` and `next_step`. Then [bind the channel in Slack](../README.md#set-it-up-in-four-steps).

## Clean up

From `terraform/`:

```bash
terraform destroy
```

This deletes the Agent Space with its investigations and chat history. The Slack registration stays until you deregister it in the console.
