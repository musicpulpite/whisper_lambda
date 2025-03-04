resource "aws_efs_file_system" "whisper_lambda_models" {
  encrypted = false
  
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  
  tags = {
    Name = "whisper-lambda-models"
  }
}


