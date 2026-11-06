output "agent_space_id" {
  value = awscc_devopsagent_agent_space.this.agent_space_id
}

output "agent_space_arn" {
  value = awscc_devopsagent_agent_space.this.arn
}

output "channel_role_arn" {
  description = "Every Slack message that drives the agent runs as this role. Empty until the Slack variables are set"
  value       = one(aws_iam_role.channel[*].arn)
}

output "channel_policy" {
  value = var.channel_policy
}

output "next_step" {
  value = local.has_slack ? "In the private channel, add the regional app and send: @AWS DevOps Agent - <Region> setup" : "Register Slack from this Agent Space in the console, then apply again with the four Slack variables"
}
