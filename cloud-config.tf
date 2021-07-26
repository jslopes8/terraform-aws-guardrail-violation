#############################################################################################################################
#
# Provider - AWS
#

provider "aws" {
  region  = "us-east-1"

  ## AWS Profile Master Account que permite o Assume Role
  profile = "aws-profile-master"

  ## IAM Role na linked account
  assume_role {
    role_arn    = "arn:aws:iam::AWS-ID-ACCOUNT:role/NomeRoleAccess"
  }
}

terraform {
  backend "s3" {
    profile                     = "aws-profile-master"
    bucket                      = "s3-bucket-tfstate"
    key                         = "edp-acc-master/guardrail-notification/terraform.tfstate"
    region                      = "us-east-1"
    encrypt                     = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
  }
}

#############################################################################################################################
#
# Variavies de Input Global
#

locals {
  # Stack Name Global
  stack_name = "GuardrailChangeCompliance"

  # Tag Resource
  default_tags = {
    SquadTeam   = "SRE"
    CostCenter  = "12345678"
    Environment = "Production"
  }
}
