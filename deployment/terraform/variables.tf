variable "aws_profile" {
  description = "The name of the credentials profile for authentication with AWS"
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
variable "pipeline_role_arn" {
  description = "The IAM role ARN of the pipeline role"
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