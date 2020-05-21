# I am assuming that the network infrastructure and the like are part of a different TF configuration
# Or that it already exists in some form or fashion, and an overhaul for the sake of this PoC would not be recieved well.

# I would not do the RDS DB as part of this config, and for the purpose of the PoC would use their current Dev DB
# I would when appropriate during the PoC work on a seperate config for managing the RDS DB infra

provider "aws" {
    region = "us-west-1"
}

# Get the network to work with
data "aws_vpc" "us-west-vpc" {
  id = var.vpc_id
}

data "aws_subnet_ids" "us-west-subnet-ids" {
  vpc_id = data.aws_vpc.us-west-vpc.id
}

data "aws_subnet" "us-west-subnets" {
  for_each = data.aws_subnet_ids.us-west-subnets.ids
  id       = each.value
}

locals {
    subnet_cidr_blocks = [for s in data.aws_subnet.us-west-subnets : s.cidr_block]
}

# Per the docs, need: ec2 instance, sg, lb, lb-sg, asg, s3 bucket, cloudwatch alarms, and a domain name

resource "aws_launch_template" "drupal-ec2-lt" {

  image_id               = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.us-west-subnets[0].id # If this doesn't exist we have bigger problems
  key_name               = aws_key_pair.drupal-pub-keypair.key_name
  vpc_security_group_ids = [aws_security_group.drupal-ec2-sg.id]

  # Box launch and install scripts placeholder
  user_data = <<EOF
  
  EOF
}

resource "aws_autoscaling_group" "drupal-ec2-asg" {
  vpc_zone_identifier   = data.aws_subnet.us-west-subnets[0].id
  desired_capacity      = var.asg_desired_cap
  max_size              = var.asg_max
  min_size              = var.asg_min

  launch_template {
    id      = aws_launch_template.drupal-ec2-lt.id
    version = "$Latest"
  }
}

# Didn't see an OS specified to use, using Ubuntu
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_key_pair" "drupal-pub-keypair" {
  key_name   = var.key_name
  public_key = var.public_key
}

resource "aws_s3_bucket" "drupal-s3-bucket" {
  bucket = "drupal-s3-bucket"
  acl    = "private"

  tags = {
    Name        = "Drupal App bucket"
  }
}

resource "aws_s3_bucket" "drupal-elb-bucket" {
  bucket = "drupal-elb-bucket"
  acl    = "private"

  tags = {
    Name        = "Drupal ELB bucket"
  }
}

resource "aws_security_group" "drupal-ec2-sg" {
  name        = "drupal-ec2-sg"
  description = "Security group for drupal ec2 in us-west-vpc"
  vpc_id      = data.aws_vpc.us-west-vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# I would have worked with their network team to identify what networks we need ingress from and done those
# As I have no idea in this mock engagement, I am pretending there is a variable with them defined

resource "aws_security_group_rule" "drupal-ec2-ingress-443" {
  description               = "Allow 443 traffic"
  from_port                 = 443
  protocol                  = "tcp"
  security_group_id         = aws_security_group.drupal-ec2-sg.id
  source_security_group_id  = aws_security_group.drupal-elb-sg.id
  to_port                   = 443
  type                      = "ingress"
}

resource "aws_security_group_rule" "drupal-ec2-ingress-80" {
  description               = "Allow 80 traffic"
  from_port                 = 80
  protocol                  = "tcp"
  security_group_id         = aws_security_group.drupal-ec2-sg.id
  source_security_group_id  = aws_security_group.drupal-elb-sg.id
  to_port                   = 80
  type                      = "ingress"
}

resource "aws_security_group_rule" "drupal-ec2-ingress-22" {
  description       = "Allow 22 traffic"
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.drupal-ec2-sg.id
  cidr_blocks       = var.ec2-ingress_cidrs
  to_port           = 22
  type              = "ingress"
}

resource "aws_security_group" "drupal-elb-sg" {
  name        = "drupal-elb-sg"
  description = "Security group for drupal elb in us-west-vpc"
  vpc_id      = data.aws_vpc.us-west-vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "drupal-elb-ingress-443" {
  description       = "Allow 443 traffic"
  from_port         = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.drupal-elb-sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  to_port           = 443
  type              = "ingress"
}

resource "aws_security_group_rule" "drupal-elb-ingress-80" {
  description       = "Allow 80 traffic"
  from_port         = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.drupal-elb-sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  to_port           = 80
  type              = "ingress"
}

resource "aws_elb" "drupal-elb" {
  name               = "drupal-elb"
  subnets            = data.aws_subnet_ids.us-west-subnets.ids

  access_logs {
    bucket        = aws_s3_bucket.drupal-elb-bucket
    bucket_prefix = "logs"
    interval      = 60
  }

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = var.ssl_cert_id
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "drupal-app-elb"
  }
}

resource "aws_autoscaling_attachment" "drupal-ec2-asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.drupal-ec2-asg.id
  elb                    = aws_elb.drupal_elb.id
}

data "aws_route53_zone" "acme_hosted_zone" {
  name         = "acme.com."
}

resource "aws_route53_record" "drupal_r53_record" {
  zone_id = data.aws_route53_zone.acme_hosted_zone.zone_id
  name    = "${var.drupal_subdomain}.${data.aws_route53_zone.acme_hosted_zone.name}"
  type    = "A"
  
  alias {
      name                      = aws_elb.drupal-elb.dns_name
      zone_id                   = aws_elb.drupal-elb.zone_id
      evaluate_target_health    = true
  }
}