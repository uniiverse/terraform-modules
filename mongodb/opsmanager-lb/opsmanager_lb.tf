variable "route53_zone_id"      {}
variable "opsmanager_subdomain" {}
variable "instance_ids"         {}
variable "ssl_certificate_id"   {}
variable "subnets"              {}
variable "vpc_id"               {}

resource "aws_elb" "opsmanager" {
  name      = "OpsManager"
  instances = ["${split(",", var.instance_ids)}"]
  subnets   = ["${split(",", var.subnets)}"]
  cross_zone_load_balancing = true

  listener {
    instance_port = 8080
    instance_protocol = "http"
    lb_port = 443
    lb_protocol = "https"
    ssl_certificate_id = "${var.ssl_certificate_id}"
  }

  listener {
    instance_port = 8080
    instance_protocol = "http"
    lb_port = 8080
    lb_protocol = "http"
  }

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 2
    target = "HTTP:8080/user/login"
    interval = 5
  }

  security_groups = ["${aws_security_group.opsmanager-lb.id}"]
}

resource "aws_security_group" "opsmanager-lb" {
  name = "opsmanager-lb"
  description = "opsmanager-lb"
  vpc_id = "${var.vpc_id}"

  ingress {
      from_port = 443
      to_port = 443
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
      from_port = 8080
      to_port = 8080
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_route53_record" "opsmanager-lb" {
  zone_id = "${var.route53_zone_id}"
  name = "${var.opsmanager_subdomain}"
  type = "CNAME"
  records = ["${aws_elb.opsmanager.dns_name}"]
  ttl = 60
}
