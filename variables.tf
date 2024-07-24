variable "region" {
  description = "The AWS region to deploy to"
  default     = "us-east-1"
}

variable "instance_type" {
  description = "The type of instance to use"
  default     = "t3a.micro"
}

variable "ami" {
  description = "The AMI ID to use for the instance"
  default     = "ami-0427090fd1714168b"
}

variable "splunk_hec_host" {
  description = "The Splunk HEC endpoint"
  type        = string
}

variable "splunk_hec_token" {
  description = "The Splunk HEC token"
  type        = string
}

variable "splunk_index" {
  description = "The Splunk index to send logs to"
  type        = string
  default     = "main"
}
