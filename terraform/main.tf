# --- NETWORKING ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "MainVPC" }
}

# --- DATA SOURCES ---
# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
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
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_cloudwatch_profile.name
  user_data = base64encode(<<-EOF
              #!/bin/bash
              set -e
              echo "Starting EC2 setup..."
              
              # Update system
              yum update -y
              yum install -y amazon-cloudwatch-agent
              
              # Get instance ID
              INSTANCE_ID=$(ec2-metadata --instance-id | cut -d" " -f2)
              echo "Instance ID: $INSTANCE_ID"
              
              # Create CloudWatch agent configuration
              cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOL'
              {
                "agent": {
                  "metrics_collection_interval": 60,
                  "run_as_user": "root"
                },
                "logs": {
                  "logs_collected": {
                    "files": {
                      "collect_list": [
                        {
                          "file_path": "/var/log/messages",
                          "log_group_name": "/aws/ec2/app-server/system",
                          "log_stream_name": "system-logs",
                          "retention_in_days": 7
                        },
                        {
                          "file_path": "/var/log/secure",
                          "log_group_name": "/aws/ec2/app-server/security",
                          "log_stream_name": "security-logs",
                          "retention_in_days": 7
                        }
                      ]
                    }
                  }
                }
              }
              EOL
              
              # Start and enable the agent
              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
                -a fetch-config \
                -m ec2 \
                -s \
                -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
              
              # Verify agent is running
              sleep 5
              if systemctl is-active --quiet amazon-cloudwatch-agent; then
                echo "CloudWatch agent started successfully"
              else
                echo "ERROR: CloudWatch agent failed to start"
                systemctl status amazon-cloudwatch-agent
                exit 1
              fi
              
              echo "EC2 setup completed successfully"
              EOF
  )
  tags          = { Name = "Compute-EC2" }
  depends_on    = [aws_iam_role_policy_attachment.ec2_cloudwatch_policy]
}

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

resource "aws_iam_role_policy" "ec2_logs_policy" {
  name = "ec2_logs_policy"
  role = aws_iam_role.ec2_cloudwatch_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_cloudwatch_profile" {
  name = "ec2_cloudwatch_profile"
  role = aws_iam_role.ec2_cloudwatch_role.name
}