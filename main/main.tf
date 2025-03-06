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
      # Login to ECR
      aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${local.ecr_repository_url}
      
      # Configure Docker to use older format compatible with Lambda
      export DOCKER_BUILDKIT=0
      export DOCKER_DEFAULT_PLATFORM=linux/arm64
      
      # Standard Docker build without buildx (more compatible)
      docker build --platform=linux/arm64 \
        -f Containerfile \
        -t ${local.ecr_repository_url}:${var.image_version} .
      
      # Push image
      docker push ${local.ecr_repository_url}:${var.image_version}
      
      # Tag as latest
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
  architectures = ["arm64"] 

  depends_on = [null_resource.docker_build_and_push]

  environment {
    variables = {
      XDG_CACHE_HOME = "/var/task/.cache"
      MODEL_SIZE     = var.whisper_model_size
    }
  }
}

# RESTful V1 API Gateway 
resource "aws_api_gateway_rest_api" "whisper_api" {
  count       = var.create_api_gateway ? 1 : 0
  name        = "whisper-transcription-api"
  description = "Whisper Transcription API with API Key Authorization"
}

# Create a resource for the /transcribe endpoint
resource "aws_api_gateway_resource" "whisper_transcribe" {
  count       = var.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.whisper_api[0].id
  parent_id   = aws_api_gateway_rest_api.whisper_api[0].root_resource_id
  path_part   = "transcribe"
}

# Create a POST method with API key requirement
resource "aws_api_gateway_method" "whisper_post" {
  count         = var.create_api_gateway ? 1 : 0
  rest_api_id   = aws_api_gateway_rest_api.whisper_api[0].id
  resource_id   = aws_api_gateway_resource.whisper_transcribe[0].id
  http_method   = "POST"
  authorization = "NONE"
  api_key_required = true
}

# Create integration with Lambda function
resource "aws_api_gateway_integration" "whisper_lambda" {
  count                   = var.create_api_gateway ? 1 : 0
  rest_api_id             = aws_api_gateway_rest_api.whisper_api[0].id
  resource_id             = aws_api_gateway_resource.whisper_transcribe[0].id
  http_method             = aws_api_gateway_method.whisper_post[0].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.whisper_transcription.invoke_arn
}

# Create method response
resource "aws_api_gateway_method_response" "whisper_response" {
  count       = var.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.whisper_api[0].id
  resource_id = aws_api_gateway_resource.whisper_transcribe[0].id
  http_method = aws_api_gateway_method.whisper_post[0].http_method
  status_code = "200"
}

# Create integration response
resource "aws_api_gateway_integration_response" "whisper_integration_response" {
  count       = var.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.whisper_api[0].id
  resource_id = aws_api_gateway_resource.whisper_transcribe[0].id
  http_method = aws_api_gateway_method.whisper_post[0].http_method
  status_code = aws_api_gateway_method_response.whisper_response[0].status_code

  depends_on = [
    aws_api_gateway_integration.whisper_lambda
  ]
}

# Create deployment
resource "aws_api_gateway_deployment" "whisper_deployment" {
  count       = var.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.whisper_api[0].id
  
  depends_on = [
    aws_api_gateway_integration.whisper_lambda,
    aws_api_gateway_integration_response.whisper_integration_response
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "whisper_stage" {
  count         = var.create_api_gateway ? 1 : 0
  deployment_id = aws_api_gateway_deployment.whisper_deployment[0].id
  rest_api_id   = aws_api_gateway_rest_api.whisper_api[0].id
  stage_name    = "prod"
}

resource "aws_api_gateway_method_settings" "whisper_settings" {
  count       = var.create_api_gateway ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.whisper_api[0].id
  stage_name  = aws_api_gateway_stage.whisper_stage[0].stage_name
  method_path = "*/*"

  settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
    metrics_enabled        = true
  }
}

# Create API Key
resource "aws_api_gateway_api_key" "whisper_api_key" {
  count       = var.create_api_gateway ? 1 : 0
  name        = "whisper-transcription-api-key"
  description = "API Key for Whisper Transcription API"
  enabled     = true
}

# Create Usage Plan
resource "aws_api_gateway_usage_plan" "whisper_usage_plan" {
  count       = var.create_api_gateway ? 1 : 0
  name        = "whisper-transcription-usage-plan"
  description = "Usage plan for Whisper Transcription API"

  api_stages {
    api_id = aws_api_gateway_rest_api.whisper_api[0].id
    stage  = aws_api_gateway_stage.whisper_stage[0].stage_name
  }

  quota_settings {
    limit  = 200
    period = "MONTH"
  }

  throttle_settings {
    burst_limit = 20
    rate_limit  = 10
  }
}

# Associate API Key with Usage Plan
resource "aws_api_gateway_usage_plan_key" "whisper_usage_plan_key" {
  count         = var.create_api_gateway ? 1 : 0
  key_id        = aws_api_gateway_api_key.whisper_api_key[0].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.whisper_usage_plan[0].id
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  count         = var.create_api_gateway ? 1 : 0
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.whisper_transcription.function_name
  principal     = "apigateway.amazonaws.com"
  
  # Update the source_arn to match REST API format
  source_arn    = "${aws_api_gateway_rest_api.whisper_api[0].execution_arn}/*/${aws_api_gateway_method.whisper_post[0].http_method}${aws_api_gateway_resource.whisper_transcribe[0].path}"
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

output "whisper_api_endpoint" {
  value = var.create_api_gateway ? "${aws_api_gateway_stage.whisper_stage[0].invoke_url}/transcribe" : null
}
