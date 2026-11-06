import { Aws, CfnCondition, CfnOutput, CfnParameter, CfnResource, Fn, Stack, StackProps } from 'aws-cdk-lib';
import * as devopsagent from 'aws-cdk-lib/aws-devopsagent';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

export type ChannelPolicy = 'chat-only' | 'managed';

export interface OnCallChannelStackProps extends StackProps {
  agentSpaceName: string;
  // chat-only: a policy you own with the two actions AIDevOpsChannelAccessPolicy granted at launch.
  // managed: the AWS managed policy, which AWS can widen without notice (version 2 grants 29 actions).
  channelPolicy: ChannelPolicy;
}

export class OnCallChannelStack extends Stack {
  constructor(scope: Construct, id: string, props: OnCallChannelStackProps) {
    super(scope, id, props);

    // Leave the Slack parameters empty on the first deploy. Register Slack from the new Agent Space in the console
    // (an OAuth flow that CDK can't do), then deploy again with them to add the channel.
    const slackServiceId = new CfnParameter(this, 'SlackServiceId', {
      default: '',
      description: 'ID of the Slack registration, from `aws devops-agent list-services --filter-service-type slack`',
      maxLength: 255,
    });
    const slackWorkspaceId = new CfnParameter(this, 'SlackWorkspaceId', { default: '', allowedPattern: '^$|^[TE][A-Z0-9]+$' });
    const slackWorkspaceName = new CfnParameter(this, 'SlackWorkspaceName', { default: '' });
    const slackChannelId = new CfnParameter(this, 'SlackChannelId', {
      default: '',
      description: 'ID of the private Slack channel. Two-way chat works only in private channels',
      allowedPattern: '^$|^[CGD][A-Z0-9]{7,15}$',
    });
    const hasSlack = new CfnCondition(this, 'HasSlack', {
      expression: Fn.conditionNot(Fn.conditionEquals(slackServiceId.valueAsString, '')),
    });
    const onlyWithSlack = (construct: Construct) => {
      (construct.node.defaultChild as CfnResource).cfnOptions.condition = hasSlack;
    };

    const agentSpacesInThisAccount = `arn:${Aws.PARTITION}:aidevops:${Aws.REGION}:${Aws.ACCOUNT_ID}:agentspace/*`;

    // The role the agent uses to read this account during investigations and chat.
    const agentSpaceRole = new iam.Role(this, 'AgentSpaceRole', {
      description: 'Lets AWS DevOps Agent read this account for the sample Agent Space',
      assumedBy: new iam.PrincipalWithConditions(new iam.ServicePrincipal('aidevops.amazonaws.com'), {
        StringEquals: { 'aws:SourceAccount': Aws.ACCOUNT_ID },
        ArnLike: { 'aws:SourceArn': agentSpacesInThisAccount },
      }),
      managedPolicies: [iam.ManagedPolicy.fromAwsManagedPolicyName('AIDevOpsAgentAccessPolicy')],
      inlinePolicies: {
        AllowCreateServiceLinkedRoles: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              sid: 'AllowResourceExplorerServiceLinkedRole',
              actions: ['iam:CreateServiceLinkedRole'],
              resources: [
                `arn:${Aws.PARTITION}:iam::${Aws.ACCOUNT_ID}:role/aws-service-role/resource-explorer-2.amazonaws.com/AWSServiceRoleForResourceExplorer`,
              ],
            }),
          ],
        }),
      },
    });

    const agentSpace = new devopsagent.CfnAgentSpace(this, 'AgentSpace', {
      name: props.agentSpaceName,
      description: 'Sample Agent Space with a two-way Slack channel',
    });

    new devopsagent.CfnAssociation(this, 'MonitorThisAccount', {
      agentSpaceId: agentSpace.ref,
      serviceId: 'aws',
      configuration: {
        aws: { accountId: Aws.ACCOUNT_ID, accountType: 'monitor', assumableRoleArn: agentSpaceRole.roleArn },
      },
    });

    // Everyone in the private channel drives the agent through this one role.
    const channelPolicy =
      props.channelPolicy === 'managed'
        ? iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AIDevOpsChannelAccessPolicy')
        : new iam.ManagedPolicy(this, 'ChatOnlyPolicy', {
            description: 'Lets the Slack channel chat with this one Agent Space, and nothing else',
            statements: [
              new iam.PolicyStatement({
                sid: 'AllowChatInThisAgentSpace',
                actions: ['aidevops:CreateChat', 'aidevops:SendMessage'],
                resources: [agentSpace.attrArn],
                conditions: { StringEquals: { 'aws:ResourceAccount': Aws.ACCOUNT_ID } },
              }),
            ],
          });

    const channelRole = new iam.Role(this, 'ChannelRole', {
      description: 'Identity of the two-way Slack channel. Every member of the channel acts through it',
      assumedBy: new iam.SessionTagsPrincipal(
        new iam.PrincipalWithConditions(new iam.ServicePrincipal('aidevops.amazonaws.com'), {
          StringEquals: { 'aws:SourceAccount': Aws.ACCOUNT_ID },
          ArnEquals: { 'aws:SourceArn': agentSpace.attrArn },
        }),
      ),
      managedPolicies: [channelPolicy],
    });
    onlyWithSlack(channelRole);
    if (channelPolicy instanceof iam.ManagedPolicy) onlyWithSlack(channelPolicy);

    const slackChannel = new devopsagent.CfnAssociation(this, 'SlackChannel', {
      agentSpaceId: agentSpace.ref,
      serviceId: slackServiceId.valueAsString,
      configuration: {
        slack: {
          workspaceId: slackWorkspaceId.valueAsString,
          workspaceName: slackWorkspaceName.valueAsString,
          transmissionTarget: { incidentResponseTarget: { channelId: slackChannelId.valueAsString } },
          bidirectional: { enabled: true, roleArn: channelRole.roleArn },
        },
      },
    });
    slackChannel.cfnOptions.condition = hasSlack;

    new CfnOutput(this, 'AgentSpaceId', { value: agentSpace.ref });
    new CfnOutput(this, 'AgentSpaceArn', { value: agentSpace.attrArn });
    new CfnOutput(this, 'ChannelRoleArn', {
      condition: hasSlack,
      description: 'Every Slack message that drives the agent runs as this role',
      value: channelRole.roleArn,
    });
    new CfnOutput(this, 'ChannelPolicy', { condition: hasSlack, value: props.channelPolicy });
    new CfnOutput(this, 'NextStep', {
      value: Fn.conditionIf(
        hasSlack.logicalId,
        'In the private channel, add the regional app and send: @AWS DevOps Agent - <Region> setup',
        'Register Slack from this Agent Space in the console, then deploy again with the four Slack parameters',
      ).toString(),
    });
  }
}
