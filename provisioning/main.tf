# Copy backend.tf.example to backend.tf and enter your values

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
  assume_role {
    role_arn = var.aws_assume_role_arn
  }
  default_tags {
    tags = {
      Component = var.service_name
    }
  }
}

resource "aws_s3_bucket" "website_bucket" {
  bucket = var.website_bucket_name
}

resource "aws_s3_bucket_server_side_encryption_configuration" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_cloudfront_origin_access_control" "cloudfront_s3_access" {
  name = "S3MdinicolaComAccess"
  description = "Access mdinicola.com S3 bucket from CloudFront"
  origin_access_control_origin_type = "s3"
  signing_behavior = "always"
  signing_protocol = "sigv4"
}

resource "aws_cloudfront_distribution" "www_mdinicola_com" {
  origin {
    domain_name = aws_s3_bucket.website_bucket.bucket_regional_domain_name
    origin_id = var.cloudfront_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.cloudfront_s3_access.id
  }

  aliases = ["www.mdinicola.com", "mdinicola.com"]

  enabled = true
  is_ipv6_enabled = true
  price_class = "PriceClass_100"

  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    target_origin_id = var.cloudfront_origin_id
    cached_methods = ["GET", "HEAD"]
    viewer_protocol_policy = "redirect-to-https"
    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    acm_certificate_arn = var.acm_certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method = "sni-only"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

data "aws_iam_policy_document" "allow_acess_from_cloudfront" {
  statement {
    principals {
      type = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.website_bucket.arn}/*"]

    condition {
      test = "StringEquals"
      variable = "AWS:SourceArn"
      values = ["${aws_cloudfront_distribution.www_mdinicola_com.arn}"]
    }
  }
}

resource "aws_s3_bucket_policy" "website_bucket" {
  bucket = aws_s3_bucket.website_bucket.id
  policy = data.aws_iam_policy_document.allow_acess_from_cloudfront.json
}

resource "aws_route53_record" "mdinicola_com_A" {
  zone_id = var.route53_hosted_zone_id
  name    = "mdinicola.com"
  type    = "A"
  alias {
    name                   = "${var.cloudfront_domain}"
    zone_id                = "${var.cloudfront_hosted_zone_id}" 
    evaluate_target_health = "false"
  }
}

resource "aws_route53_record" "www_mdinicola_com_CNAME" {
  zone_id = var.route53_hosted_zone_id
  name    = "www.mdinicola.com"
  type    = "CNAME"
  ttl     = 3600
  records = [
    "${var.cloudfront_domain}",
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
    image = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
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
        UserParameters = aws_cloudfront_distribution.www_mdinicola_com.id
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