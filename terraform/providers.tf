terraform {
  required_version = ">= 1.0.0"

  backend "s3" {
    bucket         = "zurichai-test-terraform-state-2025" # Replace with your bucket name
    key            = "prod/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    # dynamodb_table = "terraform-lock" # Optional: prevents concurrent runs
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}