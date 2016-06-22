variable "name" {}

resource "aws_ecr_repository" "ecr_repository" {
  name = "${var.name}"
}

output "url" {
  value = "${aws_ecr_repository.ecr_repository.repository_url}"
}
