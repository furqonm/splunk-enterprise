provider "aws" {
  region = "us-east-1"  # Set your desired region
}

# Define an IAM role for SSM access
resource "aws_iam_role" "ssm_role" {
  name = "ssm_role"

  # Policy that allows EC2 to assume the SSM role
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

# Attach a policy to allow SSM Session Manager access to the EC2 instance
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Define a security group for Splunk (no SSH access)
resource "aws_security_group" "splunk_sg" {
  name = "splunk-security-group"

  # Allow inbound HTTP traffic for Splunk (default port 8000)
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Open to all IPs, consider restricting access in production
  }

  # Allow inbound traffic for Splunk forwarders (default port 9997)
  ingress {
    from_port   = 9997
    to_port     = 9997
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Open to all IPs, should be restricted in production
  }

  # Allow inbound traffic for splunkd management (default port 8089)
  ingress {
    from_port   = 8089
    to_port     = 8089
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Open to all IPs, restrict for production use
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  # Allow all outbound traffic
  }
}

# Define an EC2 instance with SSM role and 50GB EBS volume
resource "aws_instance" "splunk_vm" {
  ami           = "ami-0e54eba7c51c234f6"  # Amazon Linux 2023 AMI
  instance_type = "c5a.xlarge"  # Instance type to meet Splunk's resource needs

  # Attach the security group
  vpc_security_group_ids = [aws_security_group.splunk_sg.id]

  # Attach IAM role for SSM access
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.id

  # Specify the root block device with a 50GB volume
  root_block_device {
    volume_size = 50  # 50 GB volume size
    volume_type = "gp2"  # General Purpose SSD for fast I/O
  }

  # User data to install Splunk and configure cron job for shutdown
  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install -y wget net-tools

    # Download the Splunk installer
    wget -O splunk-9.3.1-0b8d769cb912.x86_64.rpm "https://download.splunk.com/products/splunk/releases/9.3.1/linux/splunk-9.3.1-0b8d769cb912.x86_64.rpm"

    # Retry mechanism to wait for the RPM lock to be released
    RETRY_COUNT=0
    MAX_RETRIES=5
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
      sudo rpm -i splunk-9.3.1-0b8d769cb912.x86_64.rpm && break
      RETRY_COUNT=$((RETRY_COUNT+1))
      echo "Waiting for RPM lock to be released... Retry $RETRY_COUNT/$MAX_RETRIES"
      sleep 10
    done

    # If Splunk is successfully installed, configure and start it
    if [ -x /opt/splunk/bin/splunk ]; then
      sudo /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt --seed-passwd hambaAllah
      sudo /opt/splunk/bin/splunk enable boot-start
    else
      echo "Splunk installation failed."
      exit 1
    fi

    # Ensure 'atd' is enabled and running
    systemctl enable atd
    systemctl start atd

    # Create the monitoring script
    cat << 'SCRIPT_EOF' > /usr/local/bin/monitor_splunk_idle.sh
    #!/bin/bash
    PORT=8000
    IDLE_THRESHOLD=3600
    LOG_FILE="/var/log/splunk_idle_monitor.log"
    SPLUNK_CMD="/opt/splunk/bin/splunk"

    is_port_active() {
      netstat -an | grep ":$PORT " | grep ESTABLISHED > /dev/null
      return $?
    }

    if [ ! -f "/tmp/last_active_time" ]; then
      date +%s > /tmp/last_active_time
    fi

    last_active_time=$(cat /tmp/last_active_time)

    if is_port_active; then
      echo "$(date) - Port $PORT is active." >> "$LOG_FILE"
      date +%s > /tmp/last_active_time
    else
      echo "$(date) - Port $PORT is idle." >> "$LOG_FILE"
    fi

    current_time=$(date +%s)
    idle_time=$((current_time - last_active_time))

    if [ $idle_time -ge $IDLE_THRESHOLD ]; then
      echo "$(date) - Port $PORT has been idle for $IDLE_THRESHOLD seconds. Shutting down Splunk server..." >> "$LOG_FILE"
      $SPLUNK_CMD stop >> "$LOG_FILE" 2>&1
    fi
    SCRIPT_EOF

    # Make the script executable
    chmod +x /usr/local/bin/monitor_splunk_idle.sh

    # Schedule the cron job
    (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/monitor_splunk_idle.sh") | crontab -

    # Restart cron to apply changes
    systemctl restart crond
  EOF

  # Tags to identify the instance
  tags = {
    Name = "Splunk-Instance"
  }
}

# IAM Instance Profile for EC2 instance to use SSM role
resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "ssm_instance_profile"
  role = aws_iam_role.ssm_role.name
}

# Output the public IP of the Splunk server
output "public_ip" {
  description = "Public IP of the Splunk server"
  value       = aws_instance.splunk_vm.public_ip
}

# Output the URL to access Splunk's web interface
output "splunk_url" {
  description = "URL to access Splunk"
  value       = format("http://%s:8000", aws_instance.splunk_vm.public_ip)
}
