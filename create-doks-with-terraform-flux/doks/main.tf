terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.10.1"
    }
  }
}

resource "random_id" "cluster_name" {
  byte_length = 5
}

locals {
  cluster_name = "tf-k8s-${random_id.cluster_name.hex}"
}

resource "digitalocean_kubernetes_cluster" "primary" {
  name    = local.cluster_name
  region  = var.cluster_region
  version = var.cluster_version

  node_pool {
    name       = "${var.cluster_name}-pool"
    size       = var.cluster_pool_size
    node_count = var.cluster_pool_node_count
  }
}
