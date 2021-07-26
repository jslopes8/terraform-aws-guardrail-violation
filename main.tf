##################################################################################################
#
# Guardrails Intergration of the Microsoft Teams
#

## Get Account ID current
data "aws_caller_identity" "current" {}

## Get AWS Regions Current
data "aws_region" "current" {}

#############################################################################################
#
# SNS Topic Protocol HTTPS
#

module "sns_topic" {
  source = "git::https://github.com/jslopes8/terraform-aws-sns.git?ref=v1.0"

  subscriptions_endpoint = [{
    name          = local.stack_name
    display_name  = "${local.stack_name} - Notification"
    protocol      = "lambda"
    endpoint      = module.create_lambda.arn

    ## This policy defines who can access your topic. 
    ## By default, only the topic owner can publish or subscribe to the topic.
    access_policy = [
      {
        sid     = "__default_statement_ID"
        effect  = "Allow"
        principals = {
          type  = "AWS"
          identifiers = ["*"]
        }
        actions = [
          "SNS:GetTopicAttributes",
          "SNS:SetTopicAttributes",
          "SNS:AddPermission",
          "SNS:RemovePermission",
          "SNS:DeleteTopic",
          "SNS:Subscribe",
          "SNS:ListSubscriptionsByTopic",
          "SNS:Publish",
          "SNS:Receive"
        ]
        resources = [
          "arn:aws:sns:us-east-1:${data.aws_caller_identity.current.account_id}:${local.stack_name}*" 
        ]
        condition = {
          test      = "StringEquals"
          variable  = "AWS:SourceOwner"
          values    = [ data.aws_caller_identity.current.account_id ]
        }
      },
      {
        sid = "AWSEvents"
        effect = "Allow"
        principals = {
          type = "Service"
          identifiers = ["events.amazonaws.com"]
        }
        actions = ["sns:Publish"]
        resources = ["arn:aws:sns:us-east-1:${data.aws_caller_identity.current.account_id}:${local.stack_name}*"]
      }
    ]
  }]

  default_tags = local.default_tags
}

#############################################################################################
#
# EventBridge Rules
#

module "eventbridge_rule" {
  source  = "git::https://github.com/jslopes8/terraform-aws-cw-event-rules.git?ref=v1.1"

  name        = local.stack_name
  description = "${local.stack_name} Notification"

  event_pattern = jsonencode({
    "source": ["aws.config"],
    "detail-type": ["Config Rules Compliance Change"],
    "detail": {
      "messageType": ["ComplianceChangeNotification"],
      "configRuleName": [
        "AWSControlTower_AWS-GR_RESTRICTED_COMMON_PORTS",
        "AWSControlTower_AWS-GR_RESTRICTED_SSH",
        "CheckForIAMUserMFA",
        "AWSControlTower_AWS-GR_S3_BUCKET_PUBLIC_WRITE_PROHIBITED",
        "AWSControlTower_AWS-GR_S3_BUCKET_PUBLIC_READ_PROHIBITED",
        "AWSControlTower_AWS-GR_ROOT_ACCOUNT_MFA_ENABLED",
        "AWSControlTower_AWS-GR_ENCRYPTED_VOLUMES",
        "AWSControlTower_AWS-GR_RDS_STORAGE_ENCRYPTED",
        "AWSControlTower_AWS-GR_S3_VERSIONING_ENABLED",
        "AWSControlTower_AWS-GR_IAM_USER_MFA_ENABLED"
      ],
      "newEvaluationResult": {
        "complianceType": ["NON_COMPLIANT"]
      }
    }
  })

  targets = [
    {
      target_id  = "SendToSNS"
      arn = module.baseline_sns_topic.arn["ARN"]
    
      input_transformer = [{
        input_paths = {
          "aws_account":"$.account",
          "aws_regions":"$.region",
          "compliance_type":"$.detail.newEvaluationResult.complianceType",
          "resource_id":"$.detail.resourceId",
          "resource_type":"$.detail.resourceType",
          "rule_name":"$.detail.configRuleName",
          "time":"$.time"
        }
        input_template = "\"Notificação de Mudança de Conformidade na conta <aws_account> com o Config Rule <rule_name> na região de <aws_regions>. Para o recurso <resource_type> com o Id <resource_id>, resultando em <compliance_type>.\""
      }]
    }
  ]

  default_tags = local.default_tags
}

#############################################################################################
#
# IAM Role Lambda Function
#

module "lambda_role" {
  source = "git::https://github.com/jslopes8/terraform-aws-iam-roles.git?ref=v1.3"

  ## Provide the required information below and review this role before you create it.
  name            = "${local.stack_name}-Role"
  path            = "/service-role/"
  description     = "Allow ${local.stack_name} Notification"

  ## Trusted entities - AWS service: lambda.amazonaws.com
  assume_role_policy  = [
    {
      effect      = "Allow"
      actions     = [ "sts:AssumeRole" ]
      principals  = {
        type        = "Service"
        identifiers = [ "lambda.amazonaws.com" ]
      }
    }
  ]

  ## Attach permissions policies
  iam_policy  = [
    {
      effect    = "Allow"
      actions   = [ "logs:CreateLogGroup" ]
      resources = [ 
        "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*" 
      ]
    },
    {
      effect    = "Allow"
      actions   = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      resources = [ 
        "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.stack_name}*:*" 
      ]  
    }
  ]
  default_tags = local.default_tags
}

#############################################################################################
#
# Lambda Function - Python 3.6
#

module "lambda_func" {
  source = "git::https://github.com/jslopes8/terraform-aws-lamda.git?ref=v0.1.0"

  function_name = local.stack_name
  description   = "${local.stack_name} NON-Compliance"

  ## Expected Runtime: nodejs nodejs4.3 nodejs6.10 nodejs8.10 nodejs10.x nodejs12.x nodejs14.x java8 java8.al2 java11 python2.7 
  ## python3.6 python3.7 python3.8 dotnetcore1.0 dotnetcore2.0 dotnetcore2.1 dotnetcore3.1 nodejs4.3-edge go1.x 
  ## ruby2.5 ruby2.7 provided provided.al2
  handler = "lambda_function.lambda_handler"
  runtime = "python3.6"
  timeout = "3"
  role    = module.create_lambda_role.role_arn

  environment = {
    WebHookTeams = "https://exemple.webhook.office.com/webhookb2/92a06e6e-634a-........"
  }

  archive_file = [{
    type        = "zip"
    source_dir  = "lambda-code"
    output_path = "lambda-code/lambda_function.zip"
  }]

  lambda_permission   = [
    {
      statement_id  = "AllowExecutionFromCloudWatch"
      action        = "lambda:InvokeFunction"
      principal     = "events.amazonaws.com"
      source_arn    = module.baseline_eventbridge.cw_arn
    },
    {
      statement_id  = "AllowExecutionFromSNS"
      action        = "lambda:InvokeFunction"
      principal     = "sns.amazonaws.com"
      source_arn    = module.baseline_sns_topic.topic_arn
    }
  ]

  default_tags = local.default_tags
}