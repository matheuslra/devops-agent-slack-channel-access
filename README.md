# Chat with AWS DevOps Agent from Slack, through a role you control

Sample code for the blog post [The DevOps Agent Just Joined Your On-Call Channel](https://matheusarrais.com/blog/devops-agent-slack-channel-access/).

Since September 2026, AWS DevOps Agent can hold a conversation in a private Slack channel. You mention the app, and it starts and steers investigations, answers questions about resources, metrics, alarms and deployments, and replies in a thread. Everyone in that channel drives the agent through one IAM role, and who's in the channel is decided in Slack. This repo sets up an Agent Space that monitors one account, plus a two-way Slack channel whose role you define in code. By default that role can chat and nothing else.

## What gets deployed

| Resource | Why |
| --- | --- |
| Agent Space role, with `AIDevOpsAgentAccessPolicy` | The agent reads this account through it during investigations and chat |
| Agent Space `sample-oncall` | Holds the investigations, the chat and the Slack association. Its data stays in the Region you deploy to |
| AWS association (`monitor`) | Points the Agent Space at this account |
| Channel role | The identity the Slack channel uses. Its trust policy accepts only this Agent Space |
| Chat-only policy (default) | `aidevops:CreateChat` and `aidevops:SendMessage` on this one Agent Space |
| Slack association, with bidirectional mode on | Binds the private channel to the Agent Space and to the channel role |

The last three are created only once you give the stack the Slack settings, in step 3 below.

### Chat-only or managed

The console's default for a two-way channel is a role with the AWS managed policy `AIDevOpsChannelAccessPolicy` (`arn:aws:iam::aws:policy/service-role/AIDevOpsChannelAccessPolicy`). Version 1 of that policy allowed two actions: `CreateChat` and `SendMessage`. Version 2, published on 2026-10-26, allows 29, including `CreateTrigger`, `DeleteTrigger`, `DeleteAsset` and `UpdateRecommendation`. A role with the managed policy attached got those permissions without anyone changing it.

This repo defaults to `chat-only`: a policy you own with the two version 1 actions, limited to this Agent Space, so the channel's permissions change only when you change them. That's what the feature launched with. Choose `managed` if you want the channel to manage triggers, assets and recommendations from Slack, and you're fine with AWS widening that later.

## Pick a version

The stack is written three ways. They create the same resources, so deploy only one. Each folder's README has its commands, settings, outputs and clean-up.

| Version | Folder |
| --- | --- |
| CloudFormation | [`cloudformation/`](cloudformation/README.md) |
| AWS CDK in TypeScript | [`cdk/`](cdk/README.md) |
| Terraform | [`terraform/`](terraform/README.md) |

This creates real resources. Agent time is billed per second, at $0.0083 per agent-second for chat, investigations and evaluations, which is about $30 per agent-hour ([pricing](https://aws.amazon.com/devops-agent/pricing/)). New customers get a two-month trial with monthly limits. Deploy in a [supported Region](https://docs.aws.amazon.com/devopsagent/latest/userguide/about-aws-devops-agent-supported-regions.html), where the Agent Space and its chat history will live.

## Set it up in four steps

1. **Deploy without the Slack settings.** Leave the four Slack values empty. You get the Agent Space, its role and the monitoring association.
2. **Register Slack from the new Agent Space.** In the AWS DevOps Agent console, open the Agent Space, go to **Capabilities**, add a **Communications** capability, search for **Slack** and choose **Register**. Authorize the app for your Region (for example **AWS DevOps Agent - US East (N. Virginia)**) in your workspace. This is an OAuth flow in the browser, which CloudFormation, CDK and Terraform can't do. Once the workspace is registered, stop when the wizard asks for a channel ID. The registration stays in your account, and the stack creates the channel association. Then get the registration's ID:

   ```bash
   aws devops-agent list-services --filter-service-type slack --query 'services[].{id:serviceId,name:name}'
   ```

3. **Deploy again with the Slack settings:** the registration ID, your workspace ID (it starts with `T`) and name, and the ID of a private channel (open the channel's details in Slack to find it). Two-way chat works only in private channels. This adds the channel role and the two-way association.
4. **Bind the channel in Slack.** Add the regional app to the private channel, then send this exact message, with `<Region>` replaced by the suffix in your app's name:

   ```text
   /invite @AWS DevOps Agent - <Region>
   @AWS DevOps Agent - <Region> setup
   ```

Then ask it something:

```text
@AWS DevOps Agent - <Region> What can you do?
```

It replies in a thread. Mention the app in every message, including replies inside the thread, and start a new top-level message for a new conversation.

## Check who can drive the agent

```bash
pip install -r scripts/requirements.txt
python scripts/audit_slack_channels.py --region us-east-1
```

For every Agent Space in the Region, it lists the Slack channels with two-way chat on, the role each one uses, its policies and their versions, the `aidevops` actions allowed beyond chat, and whether the role's trust policy is limited to one Agent Space. It only reads, and it exits 1 when it finds something, so you can run it on a schedule. With `managed`, expect a finding that lists 27 actions beyond chat.

The script can't see who's in the Slack channel. That list lives in Slack, so review it there, the way you'd review an IAM group.

## See what the channel did

```bash
python scripts/channel_role_activity.py --role-arn <ChannelRoleArn> --hours 24
```

It finds each time the agent assumed the channel role in CloudTrail, with the session tags, and lists the API calls made with that session's credentials. It covers CloudTrail's last 90 days of management events in the Region.

## Before you rely on it

- **The channel is now an access list.** Anyone in the private channel can drive the agent through the channel role, and the agent answers with what its own role can read in your accounts. Keep the channel small, and review its members when people change teams.
- **Pin the channel's policy.** The managed policy widened from 2 to 29 actions after launch. A policy you own changes only in a pull request.
- **Test directed actions before you mix them with Slack.** If you enable directed actions (changes the agent makes after an operator approves them), check in a test Agent Space whether an approval can come from the Slack thread, and what CloudTrail records as the approver when the channel acts through one shared role. The user guide doesn't say.
- **Every mention costs agent time.** At $0.0083 per agent-second, a long thread in a busy incident adds up.
- **Check the answers.** The agent's findings and recommendations come from a language model, and the user guide says to verify them before acting.

## Clean up

Remove the stack with your version's clean-up step: [CloudFormation](cloudformation/README.md#clean-up), [CDK](cdk/README.md#clean-up) or [Terraform](terraform/README.md#clean-up). Deleting the Agent Space also deletes its investigations and chat history.

The Slack registration stays in your account until you deregister it in the console. Don't uninstall the app from the Slack workspace to stop it, because the user guide warns that it might not reinstall. Removing the channel association, which the stack does, is enough.

## What CI checks

On every push, CI lints the CloudFormation template, synthesizes the CDK app, validates the Terraform, and checks the scripts, all without AWS credentials. AWS's `ValidateTemplate` API also accepted the template, both scripts ran read-only against the live DevOps Agent, IAM and CloudTrail APIs, and the audit's policy parser was checked against versions 1 and 2 of `AIDevOpsChannelAccessPolicy`.

## Learn more

- [Connecting Slack](https://docs.aws.amazon.com/devopsagent/latest/userguide/connecting-to-ticketing-and-chat-connecting-slack.html)
- [Working with directed actions](https://docs.aws.amazon.com/devopsagent/latest/userguide/working-with-devops-agent-working-with-directed-actions.html)
- [AWS DevOps Agent security](https://docs.aws.amazon.com/devopsagent/latest/userguide/aws-devops-agent-security.html)
- [AIDevOpsChannelAccessPolicy](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AIDevOpsChannelAccessPolicy.html)
- [What's New announcement](https://aws.amazon.com/about-aws/whats-new/2026/09/aws-devops-agent-bidirectional-slack-communication/)

This is sample code for learning, not an official AWS project. Review it before you use it in your environment.

## License

[MIT-0](LICENSE)
