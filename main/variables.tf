variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300 # 5 minutes
}

variable "lambda_memory" {
  description = "Lambda function memory allocation in MB"
  type        = number
  default     = 2048 # 2GB
}

variable "create_api_gateway" {
  description = "Whether to create API Gateway endpoint for Lambda function"
  type        = bool
  default     = true
}

variable "image_version" {
  description = "Version tag for the Docker image"
  type        = string
  default     = "1.0.0"
}

variable "whisper_model_size" {
  description = "Size of the Whisper model to use (tiny.en, base.en, small.en, medium.en, large)"
  type        = string
  default     = "tiny.en"

  validation {
    condition     = contains(["tiny.en", "tiny", "base.en", "base", "small.en", "small", "medium.en", "medium", "large", "turbo"], var.whisper_model_size)
    error_message = "The whisper_model_size must be one of: tiny.en, tiny, base.en, base, small.en, small, medium.en, medium, large, turbo."
  }
}

variable "api_quota_limit" {
  description = "Monthly quota limit for API requests"
  type        = number
  default     = 10000  # 10,000 requests per month
}

variable "api_throttle_rate" {
  description = "Rate limit for API requests (requests per second)"
  type        = number
  default     = 10  # 10 requests per second
}

variable "api_throttle_burst" {
  description = "Burst limit for API requests"
  type        = number
  default     = 20  # 20 concurrent requests
}
