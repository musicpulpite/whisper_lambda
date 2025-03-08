terraform {
  required_version = ">= 1.8.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.75.0"
    }
  }

  backend "s3" {
    bucket = "terraform-remote-state-wkm-projects"
    key    = "whisper-lambda/cloudflare/state.tfstate"
    region = "us-east-2"
    dynamodb_table = "terraform-remote-state-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-2"

  assume_role {
    role_arn     = "arn:aws:iam::539247471671:role/tf-execution-role"
    session_name = "opentofu-execution-session"
  }

  default_tags {
     tags = {
        TfWorkingDir = path.cwd
     }
  }
}

provider cloudflare {
  api_token = var.cloudflare_api_token
}
