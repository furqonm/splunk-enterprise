provider "aws" {
  region = var.region
}

resource "aws_instance" "web" {
  ami           = var.ami  # Amazon Linux 2023 AMI
  instance_type = var.instance_type

  user_data = <<-EOF
    #!/bin/bash
    # Update the instance
    yum update -y

    # Install Apache HTTPD and Git
    yum install -y httpd git
    
    # Install Fluentd
    ## add GPG key
    rpm --import https://packages.treasuredata.com/GPG-KEY-td-agent

    ## add treasure data repository to yum
    cat >/etc/yum.repos.d/td.repo <<'EOF';
[treasuredata]
name=TreasureData
baseurl=http://packages.treasuredata.com/4/amazon/2/\$basearch
gpgcheck=1
gpgkey=https://packages.treasuredata.com/GPG-KEY-td-agent
EOF

    # Install Fluentd and Splunk plugin
    yum install -y td-agent
    /usr/sbin/td-agent-gem install fluent-plugin-splunk-hec

    # Configure Fluentd
    cat <<EOT > /etc/td-agent/td-agent.conf
      <source>
        @type tail
        path /var/log/httpd/access_log
        pos_file /var/log/td-agent/apache-access-log.pos
        tag apache.access
        <parse>
          @type apache2
        </parse>
      </source>

      <source>
        @type tail
        path /var/log/httpd/error_log
        pos_file /var/log/td-agent/apache-error-log.pos
        tag apache.error
        <parse>
          @type none
        </parse>
      </source>

      <match apache.access>
        @type splunk_hec
        host ${var.splunk_hec_host}
        port 8088
        protocol https
        token ${var.splunk_hec_token}
        index ${var.splunk_index}
        source apache
        sourcetype _json
      </match>

      <match apache.error>
        @type splunk_hec
        host ${var.splunk_hec_host}
        port 8088
        protocol https
        token ${var.splunk_hec_token}
        index ${var.splunk_index}
        source apache
        sourcetype _json
      </match>
      EOT

    # Start and enable Apache HTTPD, and restart fluentd agent
    systemctl start httpd
    systemctl enable httpd
    systemctl restart td-agent

    # Clone the Git repository
    cd /var/www/html
    git clone https://github.com/furqonm/packer-aws.git .
EOF

  tags = {
    Name = "terraform-ec2"
  }

  # Define a security group to allow HTTP and SSH access
  vpc_security_group_ids = [aws_security_group.web_sg.id]
}

resource "aws_security_group" "web_sg" {
  name_prefix = "web-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-sg"
  }
}

output "instance_ip" {
  description = "The public IP address of the EC2 instance"
  value       = aws_instance.web.public_ip
}
