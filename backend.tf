terraform {
  backend "s3" {
    bucket = "pocket-properties-52437-tf-state"
    key    = "state/terraform.tfstate"
    region = "us-east-1"
  }
}
