locals {
  
  config =yamldecode(file("./config.yml"))
  main_vpc = try(local.config["main_vpc"], {} )
  environments = try(local.main_vpc["environment"], {} )

  dev_env = try(local.environments["dev"], {} )
  dev_ec2s = try(local.dev_env["ec2"], {} )

  prod_env = try(local.environments["prod"], {} )
  prod_ec2s = try(local.prod_env["ec2"], {} )
  v4_env_offset = ceil(log(length(local.environments) + 1, 5))

  dev_elb = try(local.dev_env["elb"], {} )
  elb = try(local.prod_env["elb"], {} )

  prod_aws_eips = try(local.main_vpc["prod_aws_eips"], [])
  dev_aws_eips = try(local.main_vpc["dev_aws_eip"], [])

  dev_records = local.dev_env["records"]
  prod_records = local.prod_env["records"]

  prod_launch_configuration = try(local.prod_env["launch_configuration"], {} )


}

# output "output" {
#   value= local.prod_aws_eips
# }