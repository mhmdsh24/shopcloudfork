terraform {
  backend "s3" {
    bucket         = "shopcloud-tfstate-781863099565"
    key            = "primary-us-east-1/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "shopcloud-terraform-locks"
  }
}
