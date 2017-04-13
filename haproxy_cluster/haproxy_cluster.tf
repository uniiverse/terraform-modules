variable "name" {}
variable "etcd_host" {}
variable "etcd_user" {}
variable "etcd_pass" {}
variable "etcd_proto" {}
variable "etcd_cacert" {}

variable "etcd_key_prefix" {
  description = "i.e. /backends/<prefix>/universe/<service>/"
}

variable "haproxy_docker_url" {
  description = "haproxy + confd docker image"
  default = "uniiverse/haproxy"
}

variable "image_id" {
  default = "ami-6160910c" # CoreOS
}
variable "iam_instance_profile" {
  default = ""
}
variable "key_name" {
  default = ""
}
variable "instance_type" {
  default = "m3.xlarge"
}
variable "min_size" {
  default = 1
}
variable "max_size" {
  default = 1
}
variable "desired_capacity" {
  default = 1
}
variable "availability_zones" {
  default = ["us-east-1a", "us-east-1c", "us-east-1e"]
}
variable "load_balancer_names" {
  default = []
}
variable "load_balancer_sgs" {
  default = []
}
variable "docker_login_url" {
  default = "uniiverse/ecr-login:latest"
}
variable "logspout_dest" {
  description = "i.e. syslog://logs.papertrailapp.com:12345"
  default = ""
}

resource "aws_security_group" "haproxy_cluster" {
  name = "${var.name}"
  description = "${var.name}"

  ingress {
    from_port = 0
    to_port = 65535
    protocol = "tcp"
    security_groups = ["${var.load_balancer_sgs}"]
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_configuration" "haproxy_cluster" {
  name_prefix = "${var.name} - "
  image_id = "${var.image_id}"
  instance_type = "${var.instance_type}"
  iam_instance_profile = "${aws_iam_instance_profile.haproxy_cluster.name}"
  key_name = "${var.key_name}"
  security_groups = ["${aws_security_group.haproxy_cluster.name}"]
  user_data = "${data.template_file.cloud_config.rendered}"

  root_block_device {
    volume_size = 64
    volume_type = "gp2"
    delete_on_termination = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "haproxy_cluster" {
  name = "${var.name}"
  launch_configuration = "${aws_launch_configuration.haproxy_cluster.name}"
  min_size = "${var.min_size}"
  max_size = "${var.max_size}"
  desired_capacity = "${var.desired_capacity}"
  availability_zones = ["${var.availability_zones}"]
  termination_policies = ["OldestInstance"]
  load_balancers = ["${var.load_balancer_names}"]

  tag {
    key = "Name"
    value = "${var.name}"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "haproxy_cluster" {
  name = "${var.name}-instance"
  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role_policy" "haproxy_cluster" {
  name = "${aws_iam_role.haproxy_cluster.name}"
  role = "${aws_iam_role.haproxy_cluster.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    }
  ]
}
EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_instance_profile" "haproxy_cluster" {
  name = "${aws_iam_role.haproxy_cluster.name}"
  roles = ["${aws_iam_role.haproxy_cluster.name}"]

  lifecycle {
    create_before_destroy = true
  }
}

data "template_file" "cloud_config" {
  template = <<EOF
#cloud-config
coreos:
 units:
   -
     name: haproxy.service
     command: start
     runtime: true
     content: |
       [Unit]
       Description=haproxy
       Requires=docker.socket
       After=docker.service

       [Service]
       User=core
       TimeoutStartSec=0
       Restart=always
       ExecStartPre=-/usr/bin/docker stop haproxy
       ExecStartPre=-/usr/bin/docker rm haproxy
       ExecStartPre=/bin/bash -c "eval $(docker run --rm $${docker_login_url})"
       ExecStartPre=/bin/bash -c "docker pull $${haproxy_docker_url}"
       ExecStart=/bin/bash -c "docker run --name haproxy \
                                                   --rm \
                                                   -p 8080:8080 \
                                                   -p 1000:1000 \
                                                   -e ETCD_KEY_PREFIX=$${etcd_key_prefix} \
                                                   -e ETCD_NODE=$${etcd_proto}://$${etcd_host} \
                                                   -e ETCD_USER=$${etcd_user} \
                                                   -e ETCD_PASS=$${etcd_pass} \
                                                   -e ETCD_CACERT=$${etcd_cacert} \
                                                   $${haproxy_docker_url}"
       ExecStop=/usr/bin/docker stop haproxy
   -
     name: logspout.service
     command: $${logspout_command}
     runtime: true
     content: |
       [Unit]
       Description=logspout
       Requires=docker.socket
       After=docker.socket

       [Service]
       ExecStart=/usr/bin/docker run --restart=always \
                                     -d \
                                     -v=/var/run/docker.sock:/var/run/docker.sock \
                                     gliderlabs/logspout \
                                     $${logspout_dest}
EOF

  vars {
    etcd_host = "${var.etcd_host}"
    etcd_user = "${var.etcd_user}"
    etcd_pass = "${var.etcd_pass}"
    etcd_proto = "${var.etcd_proto}"
    etcd_cacert = "${var.etcd_cacert}"
    etcd_key_prefix = "${var.etcd_key_prefix}"
    logspout_command = "${coalesce(replace(var.logspout_dest, "/.+/", "start"), "stop")}"
    logspout_dest = "${coalesce(var.logspout_dest, "disabled")}"
    docker_login_url = "${var.docker_login_url}"
    haproxy_docker_url = "${var.haproxy_docker_url}"
  }
}
