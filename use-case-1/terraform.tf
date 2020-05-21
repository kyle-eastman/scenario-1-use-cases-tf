terraform {
  backend "remote" {
    hostname = "tfe.acme.com"
    organization = "ACME"

    workspaces {
      name = "drupal-poc"
    }
  }

  required_providers {
    aws = ">= 2.7.0"
  }
}