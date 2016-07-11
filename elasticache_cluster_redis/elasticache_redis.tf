variable "cluster_name" {}
variable "app_security_group_name" {}
variable "node_type" {
  default = "cache.m1.small"
}
variable "redis_version" {
  default = "2.8.23"
}
variable "parameter_group_name" {
  default = "default.redis2.8"
}

resource "aws_elasticache_cluster" "elasticache_cluster" {
  cluster_id = "${var.cluster_name}"
  engine = "redis"
  engine_version = "${var.redis_version}"
  node_type = "${var.node_type}"
  port = 6379
  num_cache_nodes = 1
  parameter_group_name = "${var.parameter_group_name}"
  security_group_names = ["${aws_elasticache_security_group.cluster_elasticache_security_group.name}"]
}

resource "aws_elasticache_security_group" "cluster_elasticache_security_group" {
  name = "universe-cache-${var.cluster_name}"
  description = "universe-cache-${var.cluster_name}"
  security_group_names = ["${var.app_security_group_name}"]
}

output "cache_nodes" {
  value = "${aws_elasticache_cluster.elasticache_cluster.cache_nodes}"
}
