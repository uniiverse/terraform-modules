variable "vpc_id" {}

resource "aws_security_group" "mongodb" {
  name = "mongodb"
  description = "mongodb"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["10.99.92.0/22", "10.99.96.0/22"]
  }

  ingress {
    from_port = 27000
    to_port = 28000
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # OpsManager non-SSL
  ingress {
    from_port = 8080
    to_port = 8080
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = "0"
    to_port = "65535"
    protocol = "tcp"
    self = true
  }

  ingress {
    from_port = "0"
    to_port = "65535"
    protocol = "udp"
    self = true
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "id" {
  value = "${aws_security_group.mongodb.id}"
}
