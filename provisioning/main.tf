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

resource "aws_s3_bucket" "website_bucket" {
  bucket = var.website_bucket_name
  website {
    index_document = "index.html"
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
  policy = <<POLICY
{
	"Version": "2012-10-17",
	"Statement": [{
		"Sid": "PublicReadGetObject",
		"Effect": "Allow",
		"Principal": "*",
		"Action": "s3:GetObject",
		"Resource": "arn:aws:s3:::${var.website_bucket_name}/*"
	}]
}
POLICY
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_record" "mdinicola_com_A" {
  zone_id = var.hosted_zone_id
  name    = "mdinicola.com"
  type    = "A"
  alias {
    name                   = "d1wzzgw9mfhbc7.cloudfront.net."
    zone_id                = "Z2FDTNDATAQYW2" # hosted_zone_id for cloudfront distribution aliases
    evaluate_target_health = "false"
  }
}

resource "aws_route53_record" "www_mdinicola_com_CNAME" {
  zone_id = var.hosted_zone_id
  name    = "www.mdinicola.com"
  type    = "CNAME"
  ttl     = 3600
  records = [
    "d1wzzgw9mfhbc7.cloudfront.net.",
  ]
}

resource "aws_codebuild_project" "buildproject" {
  name = var.service_name
  service_role = var.build_project_role_arn
  source {
    type = "CODEPIPELINE"
    buildspec = "src/buildspec.yaml"
  }
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image = "aws/codebuild/amazonlinux2-x86_64-standard:4.0"
    type = "LINUX_CONTAINER"
    environment_variable {
      name = "ARTIFACTS_BUCKET"
      value = var.artifacts_bucket_name
    }
    environment_variable {
      name = "ARTIFACTS_FOLDER"
      value = var.service_name
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
    name = "Build"
    action {
      name = "Build"
      category = "Build"
      owner = "AWS"
      provider = "CodeBuild"
      version = 1
      configuration = {
        ProjectName = var.service_name
      }
      input_artifacts = [ "SourceArtifact" ]
      output_artifacts = [ "BuildArtifact" ]
    }
  }
  stage {
    name = "Deploy"
    action {
      name = "CreateChangeSet"
      category = "Deploy"
      owner = "AWS"
      provider = "CloudFormation"
      version = 1
      configuration = {
        ActionMode = "CHANGE_SET_REPLACE"
        Capabilities = "CAPABILITY_IAM,CAPABILITY_NAMED_IAM,CAPABILITY_AUTO_EXPAND"
        RoleArn = var.deploy_role_arn
        StackName = var.service_name
        TemplatePath = "BuildArtifact::src/packaged-template.yaml"
        ChangeSetName = "${var.service_name}-Deploy"
      }
      input_artifacts = [ "BuildArtifact" ]
      run_order = 1
    }
    action {
      name = "ExecuteChangeSet"
      category = "Deploy"
      owner = "AWS"
      provider = "CloudFormation"
      version = 1
      configuration = {
        ActionMode = "CHANGE_SET_EXECUTE"
        StackName = var.service_name
        ChangeSetName = "${var.service_name}-Deploy"
      }
      run_order = 2
    }
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
      run_order = 3
    }
    action {
      name = "InvalidateContent"
      category = "Invoke"
      owner = "AWS"
      provider = "Lambda"
      version = 1
      configuration = {
        FunctionName = "${var.service_name}-InvalidateContent"
        UserParameters = var.website_distribution_id
      }
      run_order = 4
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