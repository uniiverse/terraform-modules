variable "name" {}
variable "cluster" {}
variable "namespace" {
  description = "i.e. staging, production, or an ad-hoc group of services"
}
variable "task_definition_template" {}
variable "repository_name" {}
variable "repository_tag" {
  default = "latest"
}
variable "aws_account_id" {}
variable "desired_count" {
  default = 1
}
variable "container_port" {
  default = 8080
}
variable "subdomain" {
  default = ""
}
variable "discovery_enabled" {
  default = false # true
}

resource "aws_ecs_service" "ecs_service" {
  name = "${var.name}"
  cluster = "${var.cluster}"
  task_definition = "${aws_ecs_task_definition.task_definition.arn}"
  desired_count = "${var.desired_count}"
}

resource "aws_ecs_task_definition" "task_definition" {
  family = "${var.name}"
  container_definitions = "${template_file.task_definition.rendered}"
}

resource "template_file" "task_definition" {
  template = "${var.task_definition_template}"
  vars {
    name = "${var.name}"
    repository_url = "${var.aws_account_id}.dkr.ecr.us-east-1.amazonaws.com/${var.repository_name}:${var.repository_tag}"
    container_port = "${var.container_port}"
    namespace = "${var.namespace}"
    subdomain = "${coalesce(var.subdomain, var.name)}"
    discoverable = "${replace(replace(var.discovery_enabled, 1, "true"), 0, "false")}"
  }
}

output "arn" {
  value = "${aws_ecs_task_definition.task_definition.arn}"
}

output "subdomain" {
  value = "${var.subdomain}"
}
