terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.10.1"
    }
  }
}

# DOKS
provider "digitalocean" {
  token = var.do_api_token
}

resource "random_id" "cluster_name_suffix" {
  byte_length = 5
}

locals {
  cluster_name = "${var.doks_cluster_name}-${random_id.cluster_name_suffix.hex}"
}

module "doks" {
  source                  = "./doks"
  cluster_name            = local.cluster_name         
  cluster_region          = var.doks_cluster_region
  cluster_version         = var.doks_cluster_version
  cluster_pool_size       = var.doks_cluster_pool_size
  cluster_pool_node_count = var.doks_cluster_pool_node_count
}

module "fluxcd" {
  source                    = "./fluxcd"
  doks_cluster_name         = module.doks.cluster.name
  github_user               = var.github_user
  github_token              = var.github_token
  git_repository_name       = var.git_repository_name
  git_repository_branch     = var.git_repository_branch
  git_repository_sync_path  = var.git_repository_sync_path
}
