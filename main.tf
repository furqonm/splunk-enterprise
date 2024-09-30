provider "aws" {
  region = "us-east-1"  # Set your desired region
}

# Define an IAM role for SSM access
resource "aws_iam_role" "ssm_role" {
  name = "ssm_role"

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  })
}

# Attach policies that allow SSM Session Manager access
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Define a security group (no SSH access)
resource "aws_security_group" "splunk_sg" {
  name        = "splunk-security-group"

  # Allow inbound HTTP traffic for Splunk (default port 8000)
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Define an EC2 instance with SSM role
resource "aws_instance" "splunk_vm" {
  ami           = "ami-0ebfd941bbafe70c6"  # Amazon Linux 2 AMI
  instance_type = "c5a.large"

  # Attach the security group (no SSH access)
  vpc_security_group_ids = [aws_security_group.splunk_sg.id]

  # Attach IAM role for SSM access
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.id

  # User data to install Splunk
  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y wget
              
              # Install Splunk
              wget -O splunk-9.3.1-0b8d769cb912.x86_64.rpm "https://download.splunk.com/products/splunk/releases/9.3.1/linux/splunk-9.3.1-0b8d769cb912.x86_64.rpm"
              sudo rpm -i splunk-9.3.1-0b8d769cb912.x86_64.rpm
              sudo /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt --seed-passwd hambaAllah
              sudo /opt/splunk/bin/splunk enable boot-start
              
              # Add a cron job to shut down the instance after 3 hours
              echo "sudo shutdown -h now" | at now + 3 hours
              EOF

  tags = {
    Name = "Splunk-Instance"
  }
}

# IAM Instance Profile for EC2 instance to use SSM role
resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "ssm_instance_profile"
  role = aws_iam_role.ssm_role.name
}

output "public_ip" {
  description = "Public IP of the Splunk server"
  value       = aws_instance.splunk_vm.public_ip
}

output "splunk_url" {
  description = "URL to access Splunk"
  value       = format("http://%s:8000", aws_instance.splunk_vm.public_ip)
}
