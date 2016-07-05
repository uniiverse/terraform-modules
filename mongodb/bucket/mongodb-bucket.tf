variable "name" {}

resource "aws_s3_bucket" "mongodb" {
  bucket = "${var.name}"
}

output "name" {
  value = "${var.name}"
}

output "arn" {
  value = "${aws_s3_bucket.mongodb.arn}"
}
