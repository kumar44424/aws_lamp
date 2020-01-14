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

variable "public_key_name" {
  description = "Name of the public SSH key used to connect to the servers"
  default     = "cam-public-key"
}

variable "public_key" {
  description = "Public SSH key used to connect to the servers"
}


#########################################################
# Build network
#########################################################
#resource "aws_vpc" "cam_aws" {
#  cidr_block           = "10.0.0.0/16"
#  enable_dns_hostnames = true

#  tags = "${merge(module.camtags.tagsmap, map("Name", "cam-vpc"))}"
#}

#resource "aws_internet_gateway" "cam_inter" {
#  vpc_id = "vpc-0ef19bf9446b5b3f5"

#  tags = "${merge(module.camtags.tagsmap, map("Name", "cam-internet-gateway"))}"
#}

resource "aws_subnet" "cam-primary" {
  vpc_id            = "vpc-0ef19bf9446b5b3f5"
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}b"

  tags = "${merge(module.camtags.tagsmap, map("Name", "cam-subnet"))}"
}

resource "aws_route_table" "cam_aws" {
  vpc_id = "vpc-0ef19bf9446b5b3f5"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "igw-00e938c334abc249e"
  }

  tags = "${merge(module.camtags.tagsmap, map("Name", "cam-route-table"))}"
}

resource "aws_security_group" "cam-sg" {
  name        = "cam-security-group-application"
  description = "Security group which applies to lamp application server"
  vpc_id      = "vpc-0ef19bf9446b5b3f5"

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

  tags = "${merge(module.camtags.tagsmap, map("Name", "cam-security-group-application"))}"
}


##############################################################
# Create user-specified public key in AWS
##############################################################
resource "aws_key_pair" "cam_public_key1" {
  key_name   = "${var.public_key_name}"
  public_key = "${var.public_key}"
}

##############################################################
# Create temp public key for ssh connection
##############################################################
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
}

resource "aws_key_pair" "temp_public_key1" {
  key_name   = "${var.public_key_name1}-temp"
  public_key = "${tls_private_key.ssh.public_key_openssh}"
}

##############################################################
# Create a server for php
##############################################################
resource "aws_instance" "ubntu_aws" {
  instance_type               = "t2.medium"
  ami                         = "ami-018fe598068de4442"
  subnet_id                   = "${aws_subnet.cam-primary.id}"
  vpc_security_group_ids      = ["${aws_security_group.cam-sg.id}"]
  key_name                    = "${aws_key_pair.temp_public_key1.id}"
  associate_public_ip_address = true

  tags = "${merge(module.camtags.tagsmap, map("Name", "cam-aws"))}"

  # Specify the ssh connection
 connection {
   user        = "ubuntu"
   private_key = "${tls_private_key.ssh.private_key_pem}"
   host        = "${self.public_ip}"
   bastion_host        = "${var.bastion_host}"
   bastion_user        = "${var.bastion_user}"
   bastion_private_key = "${ length(var.bastion_private_key) > 0 ? base64decode(var.bastion_private_key) : var.bastion_private_key}"
   bastion_port        = "${var.bastion_port}"
   bastion_host_key    = "${var.bastion_host_key}"
   bastion_password    = "${var.bastion_password}"        
  }

}
#########################################################
# Output
#########################################################

