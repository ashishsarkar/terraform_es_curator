resource "aws_lambda_function" "test_lambda" {
  filename      = "${var.filename}"
  function_name = "${var.function_name}"
  role          = "${aws_iam_role.iam_for_lambda_tf.arn}"
  # role        = "${var.iam_policy_arn_lambda}"
  description   = "${var.description}"
  handler       = "${var.handler}"
  tags          ="${var.tags}"
  runtime       = "${var.runtime}"
    environment {
    variables = {
      vpc_endpoint = "${var.vpc_endpoint}"
      retention_period_in_days = "${var.retention_period_in_days}"
    }
  }
   vpc_config {
    subnet_ids         = "${concat("${var.public_subnet_ids}", "${var.private_subnet_ids}")}"
    security_group_ids = ["${var.instance_security_group}"]
  }
}


resource "aws_iam_role" "iam_for_lambda_tf" {
  name = "lb_lambda_terraform_role_deletionES_${var.environment}"
    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
} 
EOF
}


data "aws_iam_policy" "VPC" {
  arn = "${var.iam_policy_arn_lambda}"
}


resource "aws_iam_role_policy_attachment" "iam" {
  role       = "${aws_iam_role.iam_for_lambda_tf.name}"
  policy_arn = "${data.aws_iam_policy.VPC.arn}"
}



resource "aws_cloudwatch_event_rule" "lambda" {
  schedule_expression = "${var.schedule_expression}"
  depends_on = [
    "aws_lambda_function.test_lambda"
  ]
  name="terraform_IndexDeletionCurator"
}


resource "aws_cloudwatch_event_target" "lambda" {
  target_id = "test_lambda"
  rule  = "${aws_cloudwatch_event_rule.lambda.name}"
  arn   = "${aws_lambda_function.test_lambda.arn}"
}


resource "aws_lambda_permission" "cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.test_lambda.function_name}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.lambda.arn}"
}
