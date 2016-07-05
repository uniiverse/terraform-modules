variable "size" {
  default = 1000
}
variable "type" {
  default = "gp2"
}
variable "name" {}
variable "availability_zone" {}
variable "instance_id" {}

resource "aws_ebs_volume" "ebs" {
  availability_zone = "${var.availability_zone}"
  size = "${var.size}"
  type = "${var.type}"
  tags {
    Name = "${var.name}"
  }
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_volume_attachment" "ebs" {
  device_name = "/dev/sdz"
  volume_id = "${aws_ebs_volume.ebs.id}"
  instance_id = "${var.instance_id}"
}

output "id" {
  value = "${aws_ebs_volume.ebs.id}"
}
