# Create ECR Repository for Whisper Lambda image
resource "aws_ecr_repository" "whisper_lambda" {
  name                 = "whisper-lambda"
  image_tag_mutability = "MUTABLE"
}

# IAM Role for Lambda execution
resource "aws_iam_role" "lambda_execution_role" {
  name = "whisper-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Local variables for Docker image
locals {
  ecr_repository_url = "${aws_ecr_repository.whisper_lambda.repository_url}"
}

# Null resource to build and push Docker image
resource "null_resource" "docker_build_and_push" {
  triggers = {
    dockerfile_content = filesha256("${path.module}/Containerfile")
    app_content        = filesha256("${path.module}/app.py")
    requirements       = filesha256("${path.module}/requirements.txt")
  }

  provisioner "local-exec" {
    command = <<EOT
      aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${local.ecr_repository_url}
      docker build -f Containerfile -t ${local.ecr_repository_url}:${var.image_version} .
      docker push ${local.ecr_repository_url}:${var.image_version}
      
      docker tag ${local.ecr_repository_url}:${var.image_version} ${local.ecr_repository_url}:latest
      docker push ${local.ecr_repository_url}:latest
    EOT
  }

  depends_on = [aws_ecr_repository.whisper_lambda]
}

# Lambda function
resource "aws_lambda_function" "whisper_transcription" {
  function_name = "whisper-transcription-service"
  package_type  = "Image"
  image_uri     = "${local.ecr_repository_url}:latest"
  role          = aws_iam_role.lambda_execution_role.arn
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory

  depends_on = [null_resource.docker_build_and_push]

  environment {
    variables = {
      XDG_CACHE_HOME = "/var/task/.cache"
      MODEL_SIZE     = var.whisper_model_size
    }
  }
}

# API Gateway with API Key Authentication
resource "aws_apigatewayv2_api" "whisper_api" {
  count         = var.create_api_gateway ? 1 : 0
  name          = "whisper-transcription-api"
  protocol_type = "HTTP"
}

# API Gateway stage
resource "aws_apigatewayv2_stage" "whisper_api" {
  count       = var.create_api_gateway ? 1 : 0
  api_id      = aws_apigatewayv2_api.whisper_api[0].id
  name        = "$default"
  auto_deploy = true
}


# API Gateway route with API key requirement
resource "aws_apigatewayv2_route" "whisper_api" {
  count     = var.create_api_gateway ? 1 : 0
  api_id    = aws_apigatewayv2_api.whisper_api[0].id
  route_key = "POST /transcribe"
  target    = "integrations/${aws_apigatewayv2_integration.whisper_lambda[0].id}"
  
  # Require API key for this route
  authorization_type = "NONE"
  api_key_required   = true
}

# API Gateway integration with Lambda
resource "aws_apigatewayv2_integration" "whisper_lambda" {
  count              = var.create_api_gateway ? 1 : 0
  api_id             = aws_apigatewayv2_api.whisper_api[0].id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.whisper_transcription.invoke_arn
  integration_method = "POST"
  payload_format_version = "2.0"
}

# API Gateway Lambda permission
resource "aws_lambda_permission" "api_gateway" {
  count         = var.create_api_gateway ? 1 : 0
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.whisper_transcription.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.whisper_api[0].execution_arn}/*/*"
}

# API Gateway API Key
resource "aws_api_gateway_api_key" "whisper_api_key" {
  count = var.create_api_gateway ? 1 : 0
  name  = "whisper-transcription-api-key"
  description = "API key for the Whisper transcription service"
  enabled = true
}

# API Gateway Usage Plan
resource "aws_api_gateway_usage_plan" "whisper_usage_plan" {
  count = var.create_api_gateway ? 1 : 0
  name  = "whisper-transcription-usage-plan"
  
  api_stages {
    api_id = aws_apigatewayv2_api.whisper_api[0].id
    stage  = aws_apigatewayv2_stage.whisper_api[0].name
  }
  
  quota_settings {
    limit  = var.api_quota_limit
    period = "MONTH"
  }
  
  throttle_settings {
    burst_limit = var.api_throttle_burst
    rate_limit  = var.api_throttle_rate
  }
}

# Link API Key to Usage Plan
resource "aws_api_gateway_usage_plan_key" "whisper_usage_plan_key" {
  count         = var.create_api_gateway ? 1 : 0
  key_id        = aws_api_gateway_api_key.whisper_api_key[0].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.whisper_usage_plan[0].id
}

###################################### OUTPUTS #######################################################
output "api_key" {
  value     = var.create_api_gateway ? aws_api_gateway_api_key.whisper_api_key[0].value : null
  sensitive = true
  description = "API key for the Whisper transcription service"
}

output "lambda_function_name" {
  value = aws_lambda_function.whisper_transcription.function_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.whisper_transcription.arn
}

output "api_gateway_url" {
  value = var.create_api_gateway ? "${aws_apigatewayv2_stage.whisper_api[0].invoke_url}/transcribe" : "API Gateway not created"
}
