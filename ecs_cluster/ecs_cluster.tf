variable "name" {}
variable "role" {}
variable "etcd_host" {}
variable "etcd_user" {}
variable "etcd_pass" {}
variable "etcd_proto" {}
variable "etcd_cacert" {}

variable "image_id" {
  # default = "ami-a1fa1acc" # Amazon ECS
  default = "ami-6160910c" # CoreOS
}
variable "instance_type" {
  default = "m3.xlarge"
}
variable "asg_min_size" {
  default = "1"
}
variable "asg_max_size" {
  default = "1"
}
variable "desired_capacity" {
  default = "1"
}
variable "availability_zones" {
  default = ["us-east-1a", "us-east-1c", "us-east-1e"]
}
variable "key_name" {
  default = ""
}
variable "discovery_enabled" {
  default = true
}

resource "aws_ecs_cluster" "cluster" {
  name = "${var.name}"
}

variable "logspout_dest" {
  description = "(optional) i.e. syslog://logs.papertrailapp.com:12345"
  default = ""
}
variable "docker_login_url" {
  default = "uniiverse/ecr-login:latest"
}
variable "docker_register_url" {
  default = "uniiverse/docker-register:latest"
}

resource "aws_launch_configuration" "cluster" {
  name_prefix = "${var.name} - "
  image_id = "${var.image_id}"
  instance_type = "${var.instance_type}"
  iam_instance_profile = "${module.ecs_iam_instance.name}"
  security_groups = ["${aws_security_group.cluster.name}"]
  key_name = "${var.key_name}"

  user_data = "${data.template_file.cloud_config.rendered}"
}

data "template_file" "cloud_config" {
  template = <<EOF
#cloud-config
coreos:
 units:
   -
     name: amazon-ecs-agent.service
     command: start
     runtime: true
     content: |
       [Unit]
       Description=AWS ECS Agent
       Documentation=https://docs.aws.amazon.com/AmazonECS/latest/developerguide/
       Requires=docker.socket
       After=docker.socket

       [Service]
       Restart=on-failure
       RestartSec=30
       RestartPreventExitStatus=5
       SyslogIdentifier=ecs-agent
       ExecStartPre=-/bin/mkdir -p /var/log/ecs /var/ecs-data /etc/ecs
       ExecStartPre=-/usr/bin/touch /etc/ecs/ecs.config
       ExecStartPre=-/usr/bin/docker kill ecs-agent
       ExecStartPre=-/usr/bin/docker rm ecs-agent
       ExecStartPre=/usr/bin/docker pull amazon/amazon-ecs-agent:latest
       ExecStart=/usr/bin/docker run --name ecs-agent \
                                     --env-file=/etc/ecs/ecs.config \
                                     --volume=/var/run/docker.sock:/var/run/docker.sock \
                                     --volume=/var/log/ecs:/log \
                                     --volume=/var/ecs-data:/data \
                                     --volume=/sys/fs/cgroup:/sys/fs/cgroup:ro \
                                     --volume=/run/docker/execdriver/native:/var/lib/docker/execdriver/native:ro \
                                     --publish=127.0.0.1:51678:51678 \
                                     --env=ECS_LOGFILE=/log/ecs-agent.log \
                                     --env=ECS_LOGLEVEL=info \
                                     --env=ECS_DATADIR=/data \
                                     --env=ECS_CLUSTER=$${cluster_name} \
                                     amazon/amazon-ecs-agent:latest
   -
     name: docker-register.service
     command: $${service_command}
     runtime: true
     mask: $${service_mask}
     content: |
       [Unit]
       Description=docker-register
       After=docker.service

       [Service]
       EnvironmentFile=/etc/environment
       TimeoutStartSec=0
       Restart=always
       ExecStartPre=-/usr/bin/docker kill docker-register
       ExecStartPre=-/usr/bin/docker rm docker-register
       ExecStartPre=/bin/sh -c "`/usr/bin/docker run --rm $${docker_login_url}`"
       ExecStartPre=/bin/sh -c "/usr/bin/docker pull $${docker_register_url}"
       ExecStart=/bin/sh -c "/usr/bin/docker run --name docker-register \
                                     --rm \
                                     -e HOST_IP=`curl http://169.254.169.254/latest/meta-data/local-ipv4` \
                                     -e ETCD_HOST=$${etcd_host} \
                                     -e ETCD_USER=$${etcd_user} \
                                     -e ETCD_PASS=$${etcd_pass} \
                                     -e ETCD_PROTO=$${etcd_proto} \
                                     -e ETCD_CACERT=$${etcd_cacert} \
                                     -v /var/run/docker.sock:/var/run/docker.sock \
                                     $${docker_register_url}"
       ExecStop=/usr/bin/docker stop docker-register

       [X-Fleet]
       Global=true
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
    service_command = "${replace(replace(var.discovery_enabled, 0, "stop"), 1, "start")}"
    service_mask = "${replace(replace(var.discovery_enabled, 0, "1"), 1, "0")}"
    docker_login_url = "${var.docker_login_url}"
    docker_register_url = "${var.docker_register_url}"
    cluster_name = "${aws_ecs_cluster.cluster.name}"
    etcd_host = "${var.etcd_host}"
    etcd_user = "${var.etcd_user}"
    etcd_pass = "${var.etcd_pass}"
    etcd_proto = "${var.etcd_proto}"
    etcd_cacert = "${var.etcd_cacert}"
    logspout_command = "${coalesce(replace(var.logspout_dest, "/.+/", "start"), "stop")}"
    logspout_dest = "${var.logspout_dest}"
  }
}

resource "aws_autoscaling_group" "cluster" {
  name = "${var.name}"
  min_size = "${var.asg_min_size}"
  max_size = "${var.asg_max_size}"
  desired_capacity = "${var.desired_capacity}"
  availability_zones = ["${var.availability_zones}"]
  termination_policies = ["OldestInstance"]
  health_check_grace_period = 300
  health_check_type = "EC2"
  force_delete = true
  launch_configuration = "${aws_launch_configuration.cluster.name}"

  tag {
    key = "Name"
    value = "${var.name}"
    propagate_at_launch = true
  }

  tag {
    key = "Role"
    value = "${var.role}"
    propagate_at_launch = true
  }
}

resource "aws_security_group" "cluster" {
  name = "${var.name}"
  description = "${var.name}"

  ingress {
    from_port = 0
    to_port = 65535
    protocol = "tcp"
    security_groups = ["amazon-elb/amazon-elb-sg"]
  }

  ingress {
    from_port = 0
    to_port = 65535
    protocol = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "ecs_iam_instance" {
  source = "../ecs_iam_instance"

  name = "${var.name}"
}

output "id" {
  value = "${aws_ecs_cluster.cluster.id}"
}

output "name" {
  value = "${aws_ecs_cluster.cluster.name}"
}
