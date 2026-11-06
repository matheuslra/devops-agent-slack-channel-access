import { App } from 'aws-cdk-lib';
import { OnCallChannelStack, type ChannelPolicy } from '../lib/stack';

const app = new App();
const channelPolicy = (app.node.tryGetContext('channelPolicy') ?? 'chat-only') as string;
if (channelPolicy !== 'chat-only' && channelPolicy !== 'managed') {
  throw new Error(`channelPolicy must be chat-only or managed, not "${channelPolicy}"`);
}

new OnCallChannelStack(app, 'OnCallChannel', {
  stackName: 'devops-agent-slack-demo',
  agentSpaceName: (app.node.tryGetContext('agentSpaceName') ?? 'sample-oncall') as string,
  channelPolicy: channelPolicy as ChannelPolicy,
});
