variable "aws_profile" {
  description = "The name of the credentials profile for authentication with AWS"
  type = string
}
variable "aws_assume_role_arn" {
  description = "The ARN of the IAM role to assume with AWS"
  type = string
}
variable "aws_region" {
  description = "The AWS region to use for provisioning resources"
  default = "ca-central-1"
  type = string
}
variable "service_name" {
  description = "The name of the project"
  type = string
}
variable "repository_name" {
  description = "The full repository name e.g. some-user/my-repo"
  type = string
}
variable "repository_branch_name" {
  description = "The repository branch to watch for changes"
  default = "main"
  type = string
}
variable "repository_connection_arn" {
  description = "The ARN of the CodeStar connection to the external repository"
  type = string
}
variable "build_project_role_arn" {
  description = "The IAM role ARN to use with CodeBuild"
  type = string
}
variable "deploy_role_arn" {
  description = "The IAM role ARN for deployment"
  type = string
}
variable "pipeline_role_arn" {
  description = "The IAM role ARN to use with CodePipeline"
  type = string
}
variable "pipeline_notification_topic_arn" {
  description = "The ARN of the SNS topic for pipeline notifications"
  type = string
}
variable "artifacts_bucket_name" {
  description = "The name of the artifacts bucket"
  type = string
}
variable "website_bucket_name" {
  description = "The name of the website bucket"
  type = string
}
variable "website_distribution_id" {
  description = "The CloudFront distribution id for the website"
  type = string
}
variable "cloudfront_domain" {
  description = "The CloudFront domain for the website"
  type = string
}
variable "cloudfront_hosted_zone_id" {
  description = "The value of the CloudFront Alias Hosted Zone Id.  See https://docs.aws.amazon.com/Route53/latest/APIReference/API_AliasTarget.html"
  type = string
}
variable "route53_hosted_zone_id" {
  description = "The hosted zone id in Route53"
  type = string
}