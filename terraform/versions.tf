terraform {
  required_version = ">= 1.6"

  required_providers {
    # IAM roles and policies.
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    # The Agent Space and its associations, including Slack's bidirectional block.
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.109"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "awscc" {
  region = var.region
}
