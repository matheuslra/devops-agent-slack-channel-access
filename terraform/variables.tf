variable "region" {
  description = "A Region where AWS DevOps Agent is available. The Agent Space and its data live here"
  type        = string
  default     = "us-east-1"
}

variable "agent_space_name" {
  description = "Name of the Agent Space"
  type        = string
  default     = "sample-oncall"
}

# Leave the four Slack variables empty on the first apply. Register Slack from the new Agent Space in the console
# (an OAuth flow that Terraform can't do), then apply again with them to add the channel.
variable "slack_service_id" {
  description = "ID of the Slack registration, from `aws devops-agent list-services --filter-service-type slack`"
  type        = string
  default     = ""
}

variable "slack_workspace_id" {
  description = "Slack workspace ID, such as T0123456789"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^$|^[TE][A-Z0-9]+$", var.slack_workspace_id))
    error_message = "A Slack workspace ID starts with T or E, followed by capital letters and digits."
  }
}

variable "slack_workspace_name" {
  description = "Slack workspace name"
  type        = string
  default     = ""
}

variable "slack_channel_id" {
  description = "ID of the private Slack channel. Two-way chat works only in private channels"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^$|^[CGD][A-Z0-9]{7,15}$", var.slack_channel_id))
    error_message = "A Slack channel ID starts with C, G or D and is 8 to 16 characters long."
  }
}

variable "channel_policy" {
  description = "chat-only: a policy you own with the two actions the AWS managed policy granted at launch. managed: AIDevOpsChannelAccessPolicy, which AWS can widen without notice"
  type        = string
  default     = "chat-only"

  validation {
    condition     = contains(["chat-only", "managed"], var.channel_policy)
    error_message = "channel_policy must be chat-only or managed."
  }
}
