terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      #       version = "4.61.0"
    }
  }
}



provider "aws" {
  region = "us-east-1" # Update with appropriate region
}




###########
####    VPC  
###########

####### Create VPC
resource "aws_vpc" "main_vpc" {
  tags = {
    Name = "main-vpc"
  }
  cidr_block = local.main_vpc.cidr

}

# Create Subnets
data "aws_availability_zones" "az" {
  state = "available"
}
resource "aws_subnet" "prod_subnet" {
  count = length(local.prod_ec2s)

  cidr_block        = "10.0.${count.index}.0/24" #cidrsubnet(local.main_vpc.cidr, local.v4_env_offset+count.index,0) 
  vpc_id            = aws_vpc.main_vpc.id
  availability_zone = data.aws_availability_zones.az.names[count.index]

  tags = {
    Name = "prod-${count.index + 1}"
  }
}

resource "aws_subnet" "dev_subnet" {
  count = length(local.dev_ec2s)

  cidr_block        = "10.0.${count.index + length(local.prod_ec2s)}.0/24" #cidrsubnet(cidrsubnet(local.main_vpc.cidr, local.v4_env_offset,0), local.v4_env_offset+count.index,0) 
  vpc_id            = aws_vpc.main_vpc.id
  availability_zone = data.aws_availability_zones.az.names[count.index]

  tags = {
    Name = "dev-${count.index + 1}"
  }
}


resource "aws_internet_gateway" "main_ig" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "main Internet Gateway"
  }
}


resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_ig.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.main_ig.id
  }

  tags = {
    Name = "Public Route Table"
  }
}

resource "aws_route_table_association" "public_dev_rt_a" {
  count          = length(local.dev_ec2s)
  subnet_id      = aws_subnet.dev_subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_prod_rt_a" {
  count          = length(local.prod_ec2s)
  subnet_id      = aws_subnet.prod_subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}




###########
####    EC2 Role 
###########

#######Create an IAM Policy and Role for ECR
resource "aws_iam_policy" "ecr-policy" {
  name        = "ECR--policy"
  description = "Provides permission to access ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Action" : [
          "ecr:*"
        ]
        Effect = "Allow"
        Resource : "*"
      },
    ]
  })
}

#Create an IAM Role
resource "aws_iam_role" "ec2-role" {
  name = "ec2--Role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = "RoleForEC2"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy_attachment" "ec2-ecr-attach" {
  name       = "ec2-ecr-attachment"
  roles      = [aws_iam_role.ec2-role.name]
  policy_arn = aws_iam_policy.ecr-policy.arn
}

resource "aws_iam_instance_profile" "ec2-profile" {
  name = "ec2-profile"
  role = aws_iam_role.ec2-role.name
}



##########################################
##########      DEV ENV
###########################################

data "aws_eip" "dev_aws_eip" {
  for_each = local.dev_aws_eips
  id       = local.dev_aws_eips[each.key]
}

#Associate DEV EIP with EC2 Instance
resource "aws_eip_association" "eip-association" {
  for_each      = { for key, value in local.dev_ec2s : key => value if startswith(key, "dev") } // if the ec2 keyname start with "dev", to eliminate the openvpn
  instance_id   = module.dev_ec2[each.key].ec2_instance[0].id
  allocation_id = data.aws_eip.dev_aws_eip[each.key].id
}


resource "aws_security_group" "dev_web_sg" {
  name   = "dev_web_sg"
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${data.aws_eip.dev_aws_eip["openvpn-server"].public_ip}/32"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["${data.aws_eip.dev_aws_eip["openvpn-server"].public_ip}/32"]
  }

  ingress {
    from_port   = 19999
    to_port     = 19999
    protocol    = "tcp"
    cidr_blocks = ["${data.aws_eip.dev_aws_eip["openvpn-server"].public_ip}/32"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}


####### Create EC2 Instances
module "dev_ec2" {
  for_each               = { for key, value in local.dev_ec2s : key => value if startswith(key, "dev") } // if the ec2 keyname start with "dev", to eliminate the openvpn
  source                 = "./ec2"
  name                   = each.key
  settings               = each.value
  subnets                = aws_subnet.dev_subnet
  iam_instance_profile   = aws_iam_instance_profile.ec2-profile.name
  vpc_security_group_ids = [aws_security_group.dev_web_sg.id]
  user_data              = " "

}




##########################################
##########      PROD ENV
###########################################

resource "aws_security_group" "prod_web_sg" {
  name   = "prod_web_sg"
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 19999
    to_port     = 19999
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "prod_ec2" {
  for_each               = local.prod_ec2s
  source                 = "./ec2"
  name                   = each.key
  settings               = each.value
  subnets                = aws_subnet.prod_subnet
  iam_instance_profile   = aws_iam_instance_profile.ec2-profile.name
  vpc_security_group_ids = [aws_security_group.prod_web_sg.id]
  user_data              = " "

}

data "aws_eip" "aws_eip" {
  for_each = local.prod_ec2s
  id       = local.prod_aws_eips[each.key]
}

#Associate EIP with EC2 Instance
resource "aws_eip_association" "aws_eip_association" {
  for_each      = module.prod_ec2
  instance_id   = module.prod_ec2[each.key].ec2_instance[0].id
  allocation_id = data.aws_eip.aws_eip[each.key].id
}


###### elb and  target group
module "elb" {
  source          = "./elb"
  settings        = local.elb
  target          = module.prod_ec2
  vpc             = aws_vpc.main_vpc
  security_groups = aws_security_group.prod_web_sg
  subnets         = aws_subnet.prod_subnet
}



###########
####   route53 
###########

##### route53 record

data "aws_route53_zone" "pocketpropertiesapp" {
  name = "pocketpropertiesapp.com."
}

resource "aws_route53_record" "prod_alias_route53_record" {
  for_each = toset(local.prod_records)
  zone_id  = data.aws_route53_zone.pocketpropertiesapp.zone_id # Replace with your zone ID
  name     = each.value                                        # Replace with your name/domain/subdomain
  type     = "A"

  alias {
    name                   = module.elb.elb.dns_name
    zone_id                = module.elb.elb.zone_id
    evaluate_target_health = true
  }
}

data "aws_eip" "dev_eip" {
  id = local.dev_aws_eips["dev-server-01"]
}
resource "aws_route53_record" "dev_alias_route53_record" {
  for_each = toset(local.dev_records)
  zone_id  = data.aws_route53_zone.pocketpropertiesapp.zone_id # Replace with your zone ID
  name     = each.value                                        # Replace with your name/domain/subdomain
  type     = "A"
  records  = [data.aws_eip.dev_eip.public_ip]
}






############
####### openvpn
############



resource "aws_security_group" "openvpn_sg" {
  name   = "openvpn_security_group"
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    from_port   = 945
    to_port     = 945
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    from_port   = 943
    to_port     = 943
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}
module "openvpn_ec2" {
  for_each               = { for key, value in local.dev_ec2s : key => value if startswith(key, "openvpn") } // only the openvpn server
  source                 = "./ec2"
  name                   = each.key
  settings               = each.value
  subnets                = aws_subnet.dev_subnet
  iam_instance_profile   = ""
  vpc_security_group_ids = [aws_security_group.openvpn_sg.id]
  user_data              = " "

}

data "aws_eip" "openvpn_aws_eip" {
  id = local.dev_aws_eips["openvpn-server"]
}

#Associate DEV EIP with EC2 Instance
resource "aws_eip_association" "openvpn-eip-association" {
  instance_id   = module.openvpn_ec2["openvpn-server"].ec2_instance[0].id
  allocation_id = data.aws_eip.openvpn_aws_eip.id
}
resource "aws_route53_record" "openvpn_racord" {
  zone_id = data.aws_route53_zone.pocketpropertiesapp.zone_id
  name    = "vpn"
  type    = "A"
  ttl     = 60
  records = [data.aws_eip.openvpn_aws_eip.public_ip]
}






# ####### Auto scaling group


# resource "aws_autoscaling_attachment" "example" {
#   autoscaling_group_name = aws_autoscaling_group.prod_asg.id
#   elb                    = aws_elb.example.id
# }


resource "aws_lb" "prod_front_lb" {
  name               = "prod-front-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.prod_web_sg.id]
  subnets            = [for subnet in aws_subnet.prod_subnet : subnet.id]

  enable_deletion_protection = false

}


resource "aws_lb_target_group" "master_http_tg" {
  name     = "master-http"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main_vpc.id

  health_check {
    port     = 80
    protocol = "HTTP"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "lb_http" {
  load_balancer_arn = aws_lb.prod_front_lb.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
  type = "redirect"

  redirect {
    port        = "443"
    protocol    = "HTTPS"
    status_code = "HTTP_301"
  }
}

  # default_action {
  #   target_group_arn = aws_lb_target_group.master_http_tg.id
  #   type             = "forward"
  # }
}

resource "aws_lb_listener" "front_end_https" {
  load_balancer_arn = aws_lb.prod_front_lb.id
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = "arn:aws:acm:us-east-1:829465433345:certificate/f9b4e9c5-0466-468e-9b62-587afcdbd45f"

  default_action {
    target_group_arn = aws_lb_target_group.master_http_tg.id
    type             = "forward"
  }
}




data "local_file" "user_data" {
  filename = "scripts/prod_user_data.sh"
}
# # Create Launch Configuration
resource "aws_launch_configuration" "prod_launch_configuration" {
  name_prefix                 = "prod_server_launch_configuration"
  image_id                    = local.prod_launch_configuration.ami
  instance_type               = local.prod_launch_configuration.type
  associate_public_ip_address = true
  user_data                   = data.local_file.user_data.content
  security_groups             = [aws_security_group.prod_web_sg.id]
  key_name                    = local.prod_launch_configuration.key_name
  iam_instance_profile        = aws_iam_instance_profile.ec2-profile.name

}

# # Create Auto Scaling Group
resource "aws_autoscaling_group" "prod_asg" {
  name                      = "prod-asg"
  min_size                  = 2
  max_size                  = 6
  desired_capacity          = 2
  health_check_grace_period = 60
  launch_configuration      = aws_launch_configuration.prod_launch_configuration.name
  vpc_zone_identifier       = [aws_subnet.prod_subnet[0].id, aws_subnet.prod_subnet[1].id]
  termination_policies      = ["Default"]
  wait_for_capacity_timeout = "10m"
  target_group_arns = [
    aws_lb_target_group.master_http_tg.arn
  ]

}
