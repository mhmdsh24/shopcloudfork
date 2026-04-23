terraform {
  backend "s3" {
    bucket         = "shopcloud-tfstate-781863099565"
    key            = "global/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "shopcloud-terraform-locks"
  }
}
