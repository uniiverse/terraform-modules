variable "name" {}

resource "aws_iam_role" "ecs_iam_service" {
  name = "${var.name}-service"
  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecs_iam_service" {
  name = "${aws_iam_role.ecs_iam_service.name}"
  role = "${aws_iam_role.ecs_iam_service.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:Describe*",
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
        "ec2:Describe*",
        "ec2:AuthorizeSecurityGroupIngress"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "ecs_iam_service" {
  name = "${aws_iam_role.ecs_iam_service.name}"
  roles = ["${aws_iam_role.ecs_iam_service.name}"]
}

output "role_arn" {
  value = "${aws_iam_role.ecs_iam_service.arn}"
}
