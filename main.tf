#################################################################
# Terraform template that will deploy two VMs in AWS with LAMP
#
# Version: 1.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Licensed Materials - Property of IBM
#
# ©Copyright IBM Corp. 2017, 2018.
#
##################################################################

#########################################################
# Define the AWS provider
#########################################################
provider "aws" {
  version = "~> 2.0"
  region  = "${var.aws_region}"
}

#########################################################
# Helper module for tagging
#########################################################
module "camtags" {
  source = "../Modules/camtags"
}

#########################################################
# Define the variables
#########################################################
variable "aws_region" {
  description = "AWS region to launch servers"
  default     = "us-east-1"
}

#Variable : AWS image name
variable "aws_image" {
  type = "string"
  description = "Operating system image id / template that should be used when creating the virtual image"
  default = "ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"
}

variable "aws_ami_owner_id" {
  description = "AWS AMI Owner ID"
  default = "099720109477"
}

# Lookup for AMI based on image name and owner ID
data "aws_ami" "aws_ami" {
  most_recent = true
  filter {
    name = "name"
    values = ["${var.aws_image}*"]
  }
  owners = ["${var.aws_ami_owner_id}"]
}

variable "php_instance_name" {
  description = "The hostname of server with php"
  default     = "lampPhp"
}

variable "db_instance_name" {
  description = "The hostname of server with mysql"
  default     = "lampDb"
}

variable "network_name_prefix" {
  description = "The prefix of names for VPC, Gateway, Subnet and Security Group"
  default     = "opencontent-lamp"
}

variable "public_key_name" {
  description = "Name of the public SSH key used to connect to the servers"
  default     = "cam-public-key-lamp"
}

variable "public_key" {
  description = "Public SSH key used to connect to the servers"
}

variable "cam_user" {
  description = "User to be added into db and sshed into servers"
  default     = "camuser"
}

variable "cam_pwd" {
  description = "Password for cam user (minimal length is 8)"
}


#########################################################
# Build network
#########################################################
resource "aws_vpc" "cam_aws" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = "${merge(module.camtags.tagsmap, map("Name", "${var.network_name_prefix}-vpc"))}"
}

resource "aws_internet_gateway" "cam_inter" {
  vpc_id = "${aws_vpc.cam_aws.id}"

  tags = "${merge(module.camtags.tagsmap, map("Name", "${var.network_name_prefix}-gateway"))}"
}

resource "aws_subnet" "primary" {
  vpc_id            = "${aws_vpc.cam_aws.id}"
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}b"

  tags = "${merge(module.camtags.tagsmap, map("Name", "${var.network_name_prefix}-subnet"))}"
}

resource "aws_route_table" "cam_aws" {
  vpc_id = "${aws_vpc.cam_aws.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.cam_inter.id}"
  }

  tags = "${merge(module.camtags.tagsmap, map("Name", "${var.network_name_prefix}-route-table"))}"
}

resource "aws_security_group" "application" {
  name        = "${var.network_name_prefix}-security-group-application"
  description = "Security group which applies to lamp application server"
  vpc_id      = "${aws_vpc.cam_aws.id}"

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

  tags = "${merge(module.camtags.tagsmap, map("Name", "${var.network_name_prefix}-security-group-application"))}"
}


##############################################################
# Create user-specified public key in AWS
##############################################################
resource "aws_key_pair" "cam_public_key" {
  key_name   = "${var.public_key_name}"
  public_key = "${var.public_key}"
}

##############################################################
# Create temp public key for ssh connection
##############################################################
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
}

resource "aws_key_pair" "temp_public_key" {
  key_name   = "${var.public_key_name}-temp"
  public_key = "${tls_private_key.ssh.public_key_openssh}"
}

##############################################################
# Create a server for php
##############################################################
resource "aws_instance" "ubntu_aws" {
  instance_type               = "t2.micro"
  ami                         = "${data.aws_ami.aws_ami.id}"
  subnet_id                   = "${aws_subnet.primary.id}"
  vpc_security_group_ids      = ["${aws_security_group.application.id}"]
  key_name                    = "${aws_key_pair.temp_public_key.id}"
  associate_public_ip_address = true

  tags = "${merge(module.camtags.tagsmap, map("Name", "${var.php_instance_name}"))}"

  # Specify the ssh connection
 # connection {
 #   user        = "ubuntu"
 #   private_key = "${tls_private_key.ssh.private_key_pem}"
 #   host        = "${self.public_ip}"
 #   bastion_host        = "${var.bastion_host}"
 #   bastion_user        = "${var.bastion_user}"
 #   bastion_private_key = "${ length(var.bastion_private_key) > 0 ? base64decode(var.bastion_private_key) : var.bastion_private_key}"
 #   bastion_port        = "${var.bastion_port}"
 #   bastion_host_key    = "${var.bastion_host_key}"
 #   bastion_password    = "${var.bastion_password}"        
 # }

}
#########################################################
# Output
#########################################################
output "aws_php_address" {
  value = "http://${aws_instance.php_server.public_ip}/test.php"
}

output "mysql_address" {
  value = "${aws_db_instance.mysql.address}"
}
