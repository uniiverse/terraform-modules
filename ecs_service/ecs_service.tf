variable "name" {}
variable "cluster" {}
variable "namespace" {
  description = "i.e. staging, production, or an ad-hoc group of services"
}
variable "task_definition_template" {}
variable "docker_image_url" {}
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
    docker_image_url = "${var.docker_image_url}"
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
