terraform {
  required_version = "1.0.2"
}

# SSH
locals {
  known_hosts = "github.com ${var.github_ssh_pub_key}"
}

resource "tls_private_key" "main" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# DOKS
data "digitalocean_kubernetes_cluster" "primary" {
  name = var.doks_cluster_name
  depends_on = [
    digitalocean_kubernetes_cluster.primary
  ]
}

resource "digitalocean_kubernetes_cluster" "primary" {
  name    = var.doks_cluster_name
  region  = var.doks_cluster_region
  version = var.doks_cluster_version

  node_pool {
    name       = "${var.doks_cluster_name}-pool"
    size       = var.doks_cluster_pool_size
    auto_scale = true
    min_nodes  = var.doks_cluster_pool_nodes.min
    max_nodes  = var.doks_cluster_pool_nodes.max
  }
}

# Flux
data "flux_install" "main" {
  target_path = var.github_repository_target_path
}

data "flux_sync" "main" {
  target_path = var.github_repository_target_path
  url         = "ssh://git@github.com/${var.github_owner}/${var.github_repository_name}.git"
  branch      = var.github_repository_branch
}

# Kubernetes
resource "kubernetes_namespace" "flux_system" {
  metadata {
    name = "flux-system"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].labels,
      metadata[0].annotations, # TODO: need to check if this one can be safely ignored
    ]
  }
}

data "kubectl_file_documents" "install" {
  content = data.flux_install.main.content
}

data "kubectl_file_documents" "sync" {
  content = data.flux_sync.main.content
}

locals {
  install = [for v in data.kubectl_file_documents.install.documents : {
    data : yamldecode(v)
    content : v
    }
  ]
  sync = [for v in data.kubectl_file_documents.sync.documents : {
    data : yamldecode(v)
    content : v
    }
  ]
}

resource "kubectl_manifest" "install" {
  for_each   = { for v in local.install : lower(join("/", compact([v.data.apiVersion, v.data.kind, lookup(v.data.metadata, "namespace", ""), v.data.metadata.name]))) => v.content }
  depends_on = [kubernetes_namespace.flux_system]
  yaml_body  = each.value
}

resource "kubectl_manifest" "sync" {
  for_each   = { for v in local.sync : lower(join("/", compact([v.data.apiVersion, v.data.kind, lookup(v.data.metadata, "namespace", ""), v.data.metadata.name]))) => v.content }
  depends_on = [kubernetes_namespace.flux_system]
  yaml_body  = each.value
}

resource "kubernetes_secret" "main" {
  depends_on = [kubectl_manifest.install]

  metadata {
    name      = data.flux_sync.main.secret
    namespace = data.flux_sync.main.namespace
  }

  data = {
    identity       = tls_private_key.main.private_key_pem
    "identity.pub" = tls_private_key.main.public_key_pem
    known_hosts    = local.known_hosts
  }
}

# GitHub
resource "github_repository" "main" {
  name       = var.github_repository_name
  visibility = var.github_repository_visibility
  auto_init  = true
}

resource "github_branch_default" "main" {
  repository = github_repository.main.name
  branch     = var.github_repository_branch
}

resource "github_repository_deploy_key" "main" {
  title      = var.doks_cluster_name
  repository = github_repository.main.name
  key        = tls_private_key.main.public_key_openssh
  read_only  = true
}

resource "github_repository_file" "install" {
  repository = github_repository.main.name
  file       = data.flux_install.main.path
  content    = data.flux_install.main.content
  branch     = var.github_repository_branch
}

resource "github_repository_file" "sync" {
  repository = github_repository.main.name
  file       = data.flux_sync.main.path
  content    = data.flux_sync.main.content
  branch     = var.github_repository_branch
}

resource "github_repository_file" "kustomize" {
  repository = github_repository.main.name
  file       = data.flux_sync.main.kustomize_path
  content    = data.flux_sync.main.kustomize_content
  branch     = var.github_repository_branch
}
