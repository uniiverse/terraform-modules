resource "aws_iam_role" "mongodb" {
  name = "universe-mongodb-config"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "mongodb" {
  name = "${aws_iam_role.mongodb.name}"
  role = "${aws_iam_instance_profile.mongodb.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:Get*",
        "s3:List*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "mongodb" {
  name = "${aws_iam_role.mongodb.name}"
  roles = ["${aws_iam_role.mongodb.name}"]
}

output "instance_profile_name" {
  value = "${aws_iam_instance_profile.mongodb.name}"
}
