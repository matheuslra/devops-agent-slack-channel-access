data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  has_slack  = var.slack_service_id != ""
}

# The role the agent uses to read this account during investigations and chat.
resource "aws_iam_role" "agent_space" {
  name_prefix = "devops-agent-space-"
  description = "Lets AWS DevOps Agent read this account for the sample Agent Space"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "aidevops.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:aidevops:${var.region}:${local.account_id}:agentspace/*" }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "agent_space" {
  role       = aws_iam_role.agent_space.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AIDevOpsAgentAccessPolicy"
}

resource "aws_iam_role_policy" "agent_space_slr" {
  name = "AllowCreateServiceLinkedRoles"
  role = aws_iam_role.agent_space.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AllowResourceExplorerServiceLinkedRole"
      Effect   = "Allow"
      Action   = "iam:CreateServiceLinkedRole"
      Resource = "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/resource-explorer-2.amazonaws.com/AWSServiceRoleForResourceExplorer"
    }]
  })
}

resource "awscc_devopsagent_agent_space" "this" {
  name        = var.agent_space_name
  description = "Sample Agent Space with a two-way Slack channel"
}

resource "awscc_devopsagent_association" "monitor" {
  agent_space_id = awscc_devopsagent_agent_space.this.agent_space_id
  service_id     = "aws"

  configuration = {
    aws = {
      account_id         = local.account_id
      account_type       = "monitor"
      assumable_role_arn = aws_iam_role.agent_space.arn
    }
  }

  depends_on = [aws_iam_role_policy_attachment.agent_space]
}

# Version 1 of AIDevOpsChannelAccessPolicy granted only these two actions. Version 2 (2026-10-26) grants 29,
# including creating and deleting triggers and assets. Owning the policy means it changes only when you change it.
resource "aws_iam_policy" "chat_only" {
  count       = local.has_slack && var.channel_policy == "chat-only" ? 1 : 0
  name_prefix = "devops-agent-chat-only-"
  description = "Lets the Slack channel chat with this one Agent Space, and nothing else"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowChatInThisAgentSpace"
      Effect    = "Allow"
      Action    = ["aidevops:CreateChat", "aidevops:SendMessage"]
      Resource  = awscc_devopsagent_agent_space.this.arn
      Condition = { StringEquals = { "aws:ResourceAccount" = local.account_id } }
    }]
  })
}

# Everyone in the private channel drives the agent through this one role.
resource "aws_iam_role" "channel" {
  count       = local.has_slack ? 1 : 0
  name_prefix = "devops-agent-channel-"
  description = "Identity of the two-way Slack channel. Every member of the channel acts through it"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "aidevops.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnEquals    = { "aws:SourceArn" = awscc_devopsagent_agent_space.this.arn }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "channel" {
  count      = local.has_slack ? 1 : 0
  role       = aws_iam_role.channel[0].name
  policy_arn = var.channel_policy == "managed" ? "arn:${local.partition}:iam::aws:policy/service-role/AIDevOpsChannelAccessPolicy" : one(aws_iam_policy.chat_only[*].arn)
}

resource "awscc_devopsagent_association" "slack" {
  count          = local.has_slack ? 1 : 0
  agent_space_id = awscc_devopsagent_agent_space.this.agent_space_id
  service_id     = var.slack_service_id

  configuration = {
    slack = {
      workspace_id   = var.slack_workspace_id
      workspace_name = var.slack_workspace_name
      transmission_target = {
        incident_response_target = { channel_id = var.slack_channel_id }
      }
      bidirectional = {
        enabled  = true
        role_arn = aws_iam_role.channel[0].arn
      }
    }
  }

  depends_on = [aws_iam_role_policy_attachment.channel]
}
