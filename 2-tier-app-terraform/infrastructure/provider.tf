terraform {
  required_providers {

    aws = {
      source  = "hashicorp/aws"
      version = "4.67.0"
    }
  }
  backend "s3" {
    bucket = "monolith-architecture-state"
    key    = "terraform.tfstate"
    region = "eu-west-2"

  }
}

provider "aws" {
  region = "eu-west-2"

}