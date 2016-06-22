variable "name" {}

resource "aws_iam_role" "ecs_iam_instance" {
  name = "${var.name}-instance"
  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecs_iam_instance" {
  name = "${aws_iam_role.ecs_iam_instance.name}"
  role = "${aws_iam_role.ecs_iam_instance.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:CreateCluster",
        "ecs:DeregisterContainerInstance",
        "ecs:DiscoverPollEndpoint",
        "ecs:Poll",
        "ecs:RegisterContainerInstance",
        "ecs:StartTelemetrySession",
        "ecs:Submit*",
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "ecs_iam_instance" {
  name = "${aws_iam_role.ecs_iam_instance.name}"
  roles = ["${aws_iam_role.ecs_iam_instance.name}"]
}

output "name" {
  value = "${aws_iam_instance_profile.ecs_iam_instance.name}"
}

output "role_arn" {
  value = "${aws_iam_role.ecs_iam_instance.arn}"
}
