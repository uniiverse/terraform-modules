variable "asg_name" {}

variable "scale_out_instance_delta" { default = "1" }
variable "scale_out_evaluation_minutes" { default = "5" }
variable "scale_out_cpu_threshold" { default = "55" }

variable "scale_in_instance_delta" { default = "-1" }
variable "scale_in_evaluation_minutes" { default = "20" }
variable "scale_in_cpu_threshold" { default = "30" }

variable "scale_out_cooldown" { default = "300" } #box launch time
variable "scale_in_cooldown" { default = "300" } #box kill time
