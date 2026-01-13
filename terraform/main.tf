# # --- NETWORKING ---
# resource "aws_vpc" "main" {
#   cidr_block           = "10.0.0.0/16"
#   enable_dns_hostnames = true
#   tags                 = { Name = "MainVPC" }
# }

# # Internet Gateway for VPC
# resource "aws_internet_gateway" "main" {
#   vpc_id = aws_vpc.main.id
#   tags   = { Name = "MainIGW" }
# }

# # --- DATA SOURCES ---
# # Get latest Amazon Linux 2023 AMI
# data "aws_ami" "amazon_linux_2023" {
#   most_recent = true
#   owners      = ["amazon"]

#   filter {
#     name   = "name"
#     values = ["al2023-ami-*"]
#   }

#   filter {
#     name   = "root-device-type"
#     values = ["ebs"]
#   }

#   filter {
#     name   = "virtualization-type"
#     values = ["hvm"]
#   }
# }

# # --- STORAGE (1/2): S3 Bucket ---
# resource "aws_s3_bucket" "app_storage" {
#   bucket = "my-app-data-2025-storage"
# }

# resource "aws_s3_bucket_logging" "app_storage_logging" {
#   bucket = aws_s3_bucket.app_storage.id

#   target_bucket = aws_s3_bucket.app_storage.id
#   target_prefix = "access-logs/"
# }

# # --- STORAGE (2/2): EFS File System ---
# resource "aws_efs_file_system" "shared_drive" {
#   creation_token = "shared-drive"
#   tags           = { Name = "SharedEFS" }
# }

# # --- COMPUTE (1/2): EC2 Instance ---
# resource "aws_instance" "app_server" {
#   ami           = data.aws_ami.amazon_linux_2023.id
#   instance_type = "t3.micro"
#   iam_instance_profile = aws_iam_instance_profile.ec2_cloudwatch_profile.name
#   user_data = base64encode(<<-EOF
#               #!/bin/bash
#               set -e
#               echo "Starting EC2 setup..."
              
#               # Update system
#               yum update -y
#               yum install -y amazon-cloudwatch-agent
              
#               # Get instance ID
#               INSTANCE_ID=$(ec2-metadata --instance-id | cut -d" " -f2)
#               echo "Instance ID: $INSTANCE_ID"
              
#               # Create CloudWatch agent configuration
#               cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOL'
#               {
#                 "agent": {
#                   "metrics_collection_interval": 60,
#                   "run_as_user": "root"
#                 },
#                 "logs": {
#                   "logs_collected": {
#                     "files": {
#                       "collect_list": [
#                         {
#                           "file_path": "/var/log/messages",
#                           "log_group_name": "/aws/ec2/app-server/system",
#                           "log_stream_name": "{instance_id}",
#                           "timestamp_format": "%b %d %H:%M:%S"
#                         },
#                         {
#                           "file_path": "/var/log/secure",
#                           "log_group_name": "/aws/ec2/app-server/security",
#                           "log_stream_name": "{instance_id}",
#                           "timestamp_format": "%b %d %H:%M:%S"
#                         }
#                       ]
#                     }
#                   }
#                 }
#               }
#               EOL
              
#               # Create log groups first
#               echo "Creating log groups..."
#               aws logs create-log-group --log-group-name /aws/ec2/app-server/system --region us-west-2 2>/dev/null || echo "Log group system already exists"
#               aws logs create-log-group --log-group-name /aws/ec2/app-server/security --region us-west-2 2>/dev/null || echo "Log group security already exists"
              
#               # Set retention policy
#               aws logs put-retention-policy --log-group-name /aws/ec2/app-server/system --retention-in-days 7 --region us-west-2 2>/dev/null || true
#               aws logs put-retention-policy --log-group-name /aws/ec2/app-server/security --retention-in-days 7 --region us-west-2 2>/dev/null || true
              
#               # Create log streams explicitly
#               echo "Creating log streams..."
#               INSTANCE_ID_FOR_STREAM=$(ec2-metadata --instance-id | cut -d" " -f2)
#               aws logs create-log-stream --log-group-name /aws/ec2/app-server/system --log-stream-name $INSTANCE_ID_FOR_STREAM --region us-west-2 2>/dev/null || echo "Log stream already exists"
#               aws logs create-log-stream --log-group-name /aws/ec2/app-server/security --log-stream-name $INSTANCE_ID_FOR_STREAM --region us-west-2 2>/dev/null || echo "Log stream already exists"
              
#               # Start and enable the agent
#               /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
#                 -a fetch-config \
#                 -m ec2 \
#                 -s \
#                 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
              
#               # Verify agent is running
#               sleep 5
#               if systemctl is-active --quiet amazon-cloudwatch-agent; then
#                 echo "CloudWatch agent started successfully"
#               else
#                 echo "ERROR: CloudWatch agent failed to start"
#                 systemctl status amazon-cloudwatch-agent
#                 exit 1
#               fi
              
#               echo "EC2 setup completed successfully"
#               EOF
#   )
#   tags          = { Name = "Compute-EC2" }
#   depends_on    = [aws_iam_role_policy_attachment.ec2_cloudwatch_policy]
# }

# # --- COMPUTE (2/2): Lambda Function ---
# resource "aws_lambda_function" "processor" {
#   function_name = "data-processor"
#   role          = aws_iam_role.lambda_exec.arn
#   handler       = "index.handler"
#   runtime       = "nodejs18.x"
  
#   # Note: You need a dummy 'function.zip' in your repo or S3
#   filename      = "function.zip" 
# }

# # --- DATABASE (1/2): RDS PostgreSQL ---
# resource "aws_db_instance" "postgres" {
#   allocated_storage   = 20
#   engine              = "postgres"
#   engine_version      = "15"
#   instance_class      = "db.t3.micro"
#   db_name             = "appdb"
#   username            = "dbadmin"
#   password            = var.db_password
#   skip_final_snapshot = true
#   enabled_cloudwatch_logs_exports = ["postgresql"]
# }

# # --- DATABASE (2/2): DynamoDB ---
# resource "aws_dynamodb_table" "app_logs" {
#   name           = "ApplicationLogs"
#   billing_mode   = "PAY_PER_REQUEST"
#   hash_key       = "LogId"

#   attribute {
#     name = "LogId"
#     type = "S"
#   }
# }

# # Supporting IAM Role for Lambda
# resource "aws_iam_role" "lambda_exec" {
#   name = "lambda_exec_role"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Action = "sts:AssumeRole"
#       Effect = "Allow"
#       Principal = { Service = "lambda.amazonaws.com" }
#     }]
#   })
# }

# # IAM Role for EC2 CloudWatch Agent
# resource "aws_iam_role" "ec2_cloudwatch_role" {
#   name = "ec2_cloudwatch_role"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Action = "sts:AssumeRole"
#       Effect = "Allow"
#       Principal = { Service = "ec2.amazonaws.com" }
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_policy" {
#   role       = aws_iam_role.ec2_cloudwatch_role.name
#   policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
# }

# resource "aws_iam_role_policy" "ec2_logs_policy" {
#   name = "ec2_logs_policy"
#   role = aws_iam_role.ec2_cloudwatch_role.id
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "logs:CreateLogGroup",
#           "logs:CreateLogStream",
#           "logs:PutLogEvents",
#           "logs:DescribeLogStreams",
#           "logs:PutRetentionPolicy"
#         ]
#         Resource = "arn:aws:logs:*:*:*"
#       }
#     ]
#   })
# }

# resource "aws_iam_instance_profile" "ec2_cloudwatch_profile" {
#   name = "ec2_cloudwatch_profile"
#   role = aws_iam_role.ec2_cloudwatch_role.name
# }

# # --- KUBERNETES (1/3): EKS Cluster ---

# # IAM Role for EKS Cluster
# resource "aws_iam_role" "eks_cluster_role" {
#   name = "eks-cluster-role"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Action = "sts:AssumeRole"
#       Effect = "Allow"
#       Principal = { Service = "eks.amazonaws.com" }
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
#   role       = aws_iam_role.eks_cluster_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
# }

# resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
#   role       = aws_iam_role.eks_cluster_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
# }

# # Security Group for EKS Cluster
# resource "aws_security_group" "eks_cluster" {
#   name        = "eks-cluster-sg"
#   description = "Security group for EKS cluster"
#   vpc_id      = aws_vpc.main.id

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = { Name = "EKSClusterSG" }
# }

# # Subnets for EKS (two availability zones)
# resource "aws_subnet" "eks_subnet_1" {
#   vpc_id                  = aws_vpc.main.id
#   cidr_block              = "10.0.2.0/24"
#   availability_zone       = "us-west-2a"
#   map_public_ip_on_launch = true
#   tags                    = { Name = "EKSSubnet1" }
# }

# resource "aws_subnet" "eks_subnet_2" {
#   vpc_id                  = aws_vpc.main.id
#   cidr_block              = "10.0.3.0/24"
#   availability_zone       = "us-west-2b"
#   map_public_ip_on_launch = true
#   tags                    = { Name = "EKSSubnet2" }
# }

# # Internet Gateway (already created, reuse)
# resource "aws_route_table" "eks_rt" {
#   vpc_id = aws_vpc.main.id

#   route {
#     cidr_block      = "0.0.0.0/0"
#     gateway_id      = aws_internet_gateway.main.id
#   }
#   tags = { Name = "EKSRT" }
# }

# resource "aws_route_table_association" "eks_rta_1" {
#   subnet_id      = aws_subnet.eks_subnet_1.id
#   route_table_id = aws_route_table.eks_rt.id
# }

# resource "aws_route_table_association" "eks_rta_2" {
#   subnet_id      = aws_subnet.eks_subnet_2.id
#   route_table_id = aws_route_table.eks_rt.id
# }

# # EKS Cluster
# resource "aws_eks_cluster" "main" {
#   name            = "zurichai-cluster"
#   role_arn        = aws_iam_role.eks_cluster_role.arn
#   version         = "1.28"

#   vpc_config {
#     subnet_ids              = [aws_subnet.eks_subnet_1.id, aws_subnet.eks_subnet_2.id]
#     security_groups         = [aws_security_group.eks_cluster.id]
#     endpoint_private_access = true
#     endpoint_public_access  = true
#   }

#   depends_on = [
#     aws_iam_role_policy_attachment.eks_cluster_policy,
#     aws_iam_role_policy_attachment.eks_vpc_resource_controller
#   ]

#   tags = { Name = "ZurichaiCluster" }
# }

# # --- KUBERNETES (2/3): EKS Node Group ---

# # IAM Role for EKS Node Group
# resource "aws_iam_role" "eks_node_role" {
#   name = "eks-node-role"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Action = "sts:AssumeRole"
#       Effect = "Allow"
#       Principal = { Service = "ec2.amazonaws.com" }
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
#   role       = aws_iam_role.eks_node_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
# }

# resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
#   role       = aws_iam_role.eks_node_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
# }

# resource "aws_iam_role_policy_attachment" "eks_registry_policy" {
#   role       = aws_iam_role.eks_node_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
# }

# # Security Group for EKS Node Group
# resource "aws_security_group" "eks_nodes" {
#   name        = "eks-nodes-sg"
#   description = "Security group for EKS nodes"
#   vpc_id      = aws_vpc.main.id

#   ingress {
#     from_port   = 0
#     to_port     = 65535
#     protocol    = "tcp"
#     cidr_blocks = ["10.0.0.0/16"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   tags = { Name = "EKSNodesSG" }
# }

# # EKS Node Group
# resource "aws_eks_node_group" "main" {
#   cluster_name    = aws_eks_cluster.main.name
#   node_group_name = "zurichai-node-group"
#   node_role_arn   = aws_iam_role.eks_node_role.arn
#   subnet_ids      = [aws_subnet.eks_subnet_1.id, aws_subnet.eks_subnet_2.id]

#   scaling_config {
#     desired_size = 2
#     max_size     = 4
#     min_size     = 1
#   }

#   instance_types = ["t3.medium"]

#   tags = { Name = "ZurichaiNodeGroup" }

#   depends_on = [
#     aws_iam_role_policy_attachment.eks_worker_node_policy,
#     aws_iam_role_policy_attachment.eks_cni_policy,
#     aws_iam_role_policy_attachment.eks_registry_policy
#   ]
# }

# # --- KUBERNETES (3/3): CloudWatch Log Group for EKS ---
# resource "aws_cloudwatch_log_group" "eks_logs" {
#   name              = "/aws/eks/zurichai-cluster/cluster"
#   retention_in_days = 7

#   tags = { Name = "EKSLogs" }
# }