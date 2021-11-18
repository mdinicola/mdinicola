# Copy terraform.config.example to terraform.config and enter your values
# Run terraform init -backend-config=terraform.config

terraform {
  backend "s3" {}
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
  default_tags {
    tags = {
      Component = var.service_name
    }
  }
}

resource "aws_codepipeline" "pipeline" {
  name = var.service_name
  role_arn = var.pipeline_role_arn
  artifact_store {
    location = var.artifacts_bucket_name
    type = "S3"
  }
  stage {
    name = "Source"
    action {
      name = "GitHubSource"
      category = "Source"
      owner = "AWS"
      provider = "CodeStarSourceConnection"
      version = 1
      configuration = {
        ConnectionArn = var.repository_connection_arn
        FullRepositoryId = var.repository_name
        BranchName = var.repository_branch_name
        OutputArtifactFormat = "CODE_ZIP"
        DetectChanges: true
      }
      output_artifacts = [ "SourceArtifact" ]
    }
  }

  stage {
    name = "Deploy"
    action {
      name = "DeployToS3"
      category = "Deploy"
      owner = "AWS"
      provider = "S3"
      input_artifacts = [ "SourceArtifact" ]
      version = 1
      configuration = {
        BucketName = var.website_bucket_name
        Extract = true
      }
      run_order = 1
    }
  }
}

resource "aws_codestarnotifications_notification_rule" "pipeline_notification_rule" {
  name = "${var.service_name}-PipelineNotificationRule"
  detail_type = "BASIC"
  resource = aws_codepipeline.pipeline.arn
  event_type_ids = [ "codepipeline-pipeline-pipeline-execution-succeeded",
                      "codepipeline-pipeline-pipeline-execution-canceled",
                      "codepipeline-pipeline-pipeline-execution-failed" ]
  target {
    type = "SNS"
    address = var.pipeline_notification_topic_arn
  }
}