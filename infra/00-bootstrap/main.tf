terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "tofu_state" {
  source = "../../modules/compliant-bucket"

  name                = "grc-lab-tfstate"
  environment         = "prod"
  data_classification = "confidential"
  force_destroy       = true
}

output "state_bucket" {
  value = module.tofu_state.bucket_id
}
