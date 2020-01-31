provider "aws" {
  region = "${var.aws_region}"
}

terraform {
  required_version = "~> 0.12"
  backend "s3" {
    encrypt = true
  }
}


data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "terraform-service-monitoring"
    key    = "terraform-state-vpc-monitoring"
    region = "eu-central-1"
  }
}

data "terraform_remote_state" "iam_policy_lambda" {
  backend = "s3"
  config = {
    bucket = "terraform-service-monitoring"
    key    = "lb-lambda-terraform-policy-s3-to-cw"
    region = "eu-central-1"
  }
}

module "file" {
  source = "./file"
}


module "lambda" {
  source = "./lambda3"

  function_name            = "${var.function_name}"
  handler                  = "${var.handler}"
  runtime                  = "${var.runtime}"
  vpc_endpoint             = "${var.vpc_endpoint}"
  retention_period_in_days = "${var.retention_period_in_days}"
  schedule_expression      = "${var.schedule_expression}"
  bucket                   = "${var.bucket}"
  vpc_id                   = "${data.terraform_remote_state.vpc.outputs.vpc_id}"
  public_subnet_ids        = "${data.terraform_remote_state.vpc.outputs.public_subnet_ids}"
  private_subnet_ids       = "${data.terraform_remote_state.vpc.outputs.private_subnet_ids}"
  instance_security_group  = "${data.terraform_remote_state.vpc.outputs.instance_sg_id}"
  iam_policy_arn_lambda    = "${data.terraform_remote_state.iam_policy_lambda.outputs.iam_policy_arn}"
  description              = "${var.description}"
  filename                 = "${module.file.path}"
  # iam_policy_arn_lambda= "${aws_iam_instance_profile.my_instance_profile.name}"
  tags = {
    tag_name        = "${var.function_name}"
    tag_owner       = "${var.tag_owner}"
    tag_email       = "${var.tag_email}"
    tag_description = "${var.tag_description}"
  }
  environment             = "${var.environment}"
}
