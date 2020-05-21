variable "asg_desired_cap" {
    description = "desired capacity for the asg controlling the drupal ec2s"
    type        = number
}

variable "asg_max" {
    description = "desired max ec2s for the asg controlling the drupal ec2s"
    type        = number
}

variable "asg_min" {
    description = "desired min ec2s for the asg controlling the drupal ec2s"
    type        = number
}

variable "drupal_subdomain" {
    description = "subdomain on the acme r53 hosted zone for the drupal poc"
    type        = string
}

variable "ec2-ingress_cidrs" {
    description = "ingress cidr blocks for the ec2 security group"
    type        = []
}

variable "ec2_instance_type" {
    description = "instance type/size for ec2s launched by this config"
    type        = string
}

variable "key_name" {
    description = "ssh key name"
    type        = string
}

variable "public_key" {
    description = "ssh key itself"
    type        = string
}

variable "ssl_cert_id" {
    description = "id/arn for the ssl cert for 443 listening on the load balancer"
    type        = string
}

variable "vpc_id" {
    description = "vpc id for the workspace deployment"
    type        = string
}
