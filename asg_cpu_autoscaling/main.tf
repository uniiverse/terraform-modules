resource "aws_cloudwatch_metric_alarm" "asg_cpu_scaleout" {
  alarm_name = "${var.asg_name}appScaleOutCpuUtilization"
  comparison_operator = "GreaterThanThreshold"
  dimensions = {
    AutoScalingGroupName = "${var.asg_name}"
  }
  evaluation_periods = "${var.scale_out_evaluation_minutes}"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "60"
  statistic = "Average"
  threshold = "${var.scale_out_cpu_threshold}"
  alarm_description = "ASG CPU average > ${var.scale_out_cpu_threshold} for ${var.scale_out_evaluation_minutes} minutes"

  actions_enabled = true
  alarm_actions   = ["${aws_autoscaling_policy.asg_scale_out.arn}"]
}

resource "aws_cloudwatch_metric_alarm" "asg_cpu_scalein" {
  alarm_name = "${var.asg_name}appScaleInCpuUtilization"
  comparison_operator = "LessThanThreshold"
  dimensions = {
    AutoScalingGroupName = "${var.asg_name}"
  }
  evaluation_periods = "${var.scale_in_evaluation_minutes}"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "60"
  statistic = "Average"
  threshold = "${var.scale_in_cpu_threshold}"
  alarm_description = "ASG CPU average < ${var.scale_in_cpu_threshold} for ${var.scale_in_evaluation_minutes} minutes"

  actions_enabled = true
  alarm_actions   = ["${aws_autoscaling_policy.asg_scale_in.arn}"]
}

resource "aws_autoscaling_policy" "asg_scale_out" {
  name                     = "${var.asg_name}appScaleOutCpuUtilization"
  autoscaling_group_name   = "${var.asg_name}"
  adjustment_type          = "ChangeInCapacity"
  scaling_adjustment       = "${var.scale_out_instance_delta}"
  cooldown                 = "${var.scale_out_cooldown}"
  policy_type              = "SimpleScaling"
}

# Decrease
resource "aws_autoscaling_policy" "asg_scale_in" {
  name                     = "${var.asg_name}appScaleInCpuUtilization"
  autoscaling_group_name   = "${var.asg_name}"
  adjustment_type          = "ChangeInCapacity"
  scaling_adjustment       = "${var.scale_in_instance_delta}"
  cooldown                 = "${var.scale_in_cooldown}"
  policy_type              = "SimpleScaling"
}
