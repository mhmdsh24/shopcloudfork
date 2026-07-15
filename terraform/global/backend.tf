terraform {
  backend "s3" {
    bucket         = "shopcloud-tfstate-268810572260"
    key            = "global/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "shopcloud-terraform-locks"
  }
}
