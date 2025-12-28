# --- NETWORKING ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "MainVPC" }
}

# --- STORAGE (1/2): S3 Bucket ---
resource "aws_s3_bucket" "app_storage" {
  bucket = "my-app-data-2025-storage"
}

resource "aws_s3_bucket_logging" "app_storage_logging" {
  bucket = aws_s3_bucket.app_storage.id

  target_bucket = aws_s3_bucket.app_storage.id
  target_prefix = "access-logs/"
}

# --- STORAGE (2/2): EFS File System ---
resource "aws_efs_file_system" "shared_drive" {
  creation_token = "shared-drive"
  tags           = { Name = "SharedEFS" }
}

# --- COMPUTE (1/2): EC2 Instance ---
# resource "aws_instance" "app_server" {
#   ami           = "ami-0c7217cdde317cfec" # Amazon Linux 2023
#   instance_type = "t3.micro"
#   iam_instance_profile = aws_iam_instance_profile.ec2_cloudwatch_profile.name
#   user_data = <<-EOF
#               #!/bin/bash
#               yum update -y
#               yum install -y amazon-cloudwatch-agent
#               cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOL'
#               {
#                 "logs": {
#                   "logs_collected": {
#                     "files": {
#                       "collect_list": [
#                         {
#                           "file_path": "/var/log/messages",
#                           "log_group_name": "EC2-AppServer-SystemLogs",
#                           "log_stream_name": "{instance_id}"
#                         },
#                         {
#                           "file_path": "/var/log/secure",
#                           "log_group_name": "EC2-AppServer-SecurityLogs",
#                           "log_stream_name": "{instance_id}"
#                         }
#                       ]
#                     }
#                   }
#                 }
#               }
#               EOL
#               systemctl enable amazon-cloudwatch-agent
#               systemctl start amazon-cloudwatch-agent
#               EOF
#   tags          = { Name = "Compute-EC2" }
# }

# --- COMPUTE (2/2): Lambda Function ---
resource "aws_lambda_function" "processor" {
  function_name = "data-processor"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  
  # Note: You need a dummy 'function.zip' in your repo or S3
  filename      = "function.zip" 
}

# --- DATABASE (1/2): RDS PostgreSQL ---
resource "aws_db_instance" "postgres" {
  allocated_storage   = 20
  engine              = "postgres"
  engine_version      = "15"
  instance_class      = "db.t3.micro"
  db_name             = "appdb"
  username            = "dbadmin"
  password            = var.db_password
  skip_final_snapshot = true
  enabled_cloudwatch_logs_exports = ["postgresql"]
}

# --- DATABASE (2/2): DynamoDB ---
resource "aws_dynamodb_table" "app_logs" {
  name           = "ApplicationLogs"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LogId"

  attribute {
    name = "LogId"
    type = "S"
  }
}

# Supporting IAM Role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# IAM Role for EC2 CloudWatch Agent
resource "aws_iam_role" "ec2_cloudwatch_role" {
  name = "ec2_cloudwatch_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_policy" {
  role       = aws_iam_role.ec2_cloudwatch_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_cloudwatch_profile" {
  name = "ec2_cloudwatch_profile"
  role = aws_iam_role.ec2_cloudwatch_role.name
}