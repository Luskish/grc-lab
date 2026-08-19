terraform {
  required_version = ">= 1.6"
  
  backend "s3" {
    bucket       = "grc-lab-tfstate-novel-pig"   # ← YOUR bucket name
    key          = "02-module-demo/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }

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

module "app_data" {
  source = "../../modules/compliant-bucket"

  name          = "grc-lab-app-data"
  environment   = "dev"
  force_destroy = true
}

module "reports" {
  source = "../../modules/compliant-bucket"

  name                = "grc-lab-reports"
  environment         = "dev"
  data_classification = "confidential"
  force_destroy       = true
}

output "buckets" {
  value = {
    app_data = module.app_data.bucket_id
    reports  = module.reports.bucket_id
  }
}

