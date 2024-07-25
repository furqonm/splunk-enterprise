resource "aws_instance" "web" {
  ami           = var.ami  # Amazon Linux 2023 AMI
  instance_type = var.instance_type

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd git
    systemctl start httpd
    systemctl enable httpd

    cd /var/www/html
    git clone https://github.com/furqonm/packer-aws.git .

    curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh | sh

    EOF

  tags = {
    Name = "terraform-ec2"
  }

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
