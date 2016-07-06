variable "bucket_name" {}
variable "bucket_arn" {}

resource "aws_s3_bucket_object" "ssl-key" {
  bucket = "${var.bucket_name}"
  key    = "mongodb-ssl.pem"
  source = "./mongodb-ssl.pem"

  lifecycle {
    # works around some weird errors destroying these resources
    prevent_destroy = true
  }
}

output "s3_object" {
  value = "s3://${var.bucket_name}/${aws_s3_bucket_object.ssl-key.id}"
}
