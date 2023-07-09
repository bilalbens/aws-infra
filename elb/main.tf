variable "settings" {}
variable "target" {}
variable "vpc" {}
variable "security_groups" {}
variable "subnets" {}

locals{
    target_group = var.settings.target_group
    listeners = var.settings.listeners
}



# Create a target group
resource "aws_lb_target_group" "front-target-lb" {
  name     = local.target_group.name
  port     = local.target_group.port
  protocol = local.target_group.protocol
  vpc_id   = var.vpc.id
}
# Attach the target group to the AWS instances
resource "aws_lb_target_group_attachment" "attach-lb-ec2" {
  for_each = var.target
  target_group_arn = aws_lb_target_group.front-target-lb.arn
  target_id = var.target[each.key].ec2_instance[0].id
  port             = 80
}

#Create the load balancer
resource "aws_lb" "front-lb" {
  name               = var.settings.name
  internal           = false
  load_balancer_type = var.settings.type
  security_groups    = [var.security_groups.id]
  subnets            = [for subnet in var.subnets : subnet.id]

  enable_deletion_protection = false

  tags = {
    Environment = "elb-${var.settings.env}"
  }
}

# Create a listener
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.front-lb.arn
  port              = local.listeners.port
  protocol          = local.listeners.protocol

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

}
resource "aws_lb_listener" "front_end_https" {
  load_balancer_arn = aws_lb.front-lb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = "arn:aws:acm:us-east-1:829465433345:certificate/f9b4e9c5-0466-468e-9b62-587afcdbd45f"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.front-target-lb.arn
  }
}


