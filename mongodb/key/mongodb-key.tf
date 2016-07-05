variable "bucket_name" {}
variable "bucket_arn" {}

resource "aws_s3_bucket_object" "mongodb-key" {
  bucket = "${var.bucket_name}"
  key    = "mongodb.key"
  source = "./mongodb.key"

  lifecycle {
    # works around some weird errors destroying these resources
    prevent_destroy = true
  }
}

output "s3_object" {
  value = "s3://${var.bucket_name}/${aws_s3_bucket_object.mongodb-key.id}"
}
