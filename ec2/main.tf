variable "name" {}
variable "settings" {}
variable "subnets" {}
variable "iam_instance_profile" {}
variable "vpc_security_group_ids" {}
variable "user_data" {}





# Create EC2 Instances
resource "aws_instance" "ec2_instance" {
  count = var.settings.amount 

  key_name =  var.settings.key_name 
  ami           = var.settings.ami  # Update with appropriate AMI ID
  instance_type =  var.settings.type  # Update with appropriate instance type
  associate_public_ip_address = true
  subnet_id     = var.subnets[count.index].id 
  tags = {
    Name = var.name
  }
#Add IAM role to read images from ECR
  iam_instance_profile = var.iam_instance_profile
  vpc_security_group_ids      = var.vpc_security_group_ids 
  user_data = var.user_data

}




