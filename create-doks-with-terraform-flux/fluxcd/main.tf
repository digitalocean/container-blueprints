terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.10.1"
    }
    github = {
      source  = "integrations/github"
      version = "~> 4.12.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 3.1.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.3.2"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.11.2"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "~> 0.2.0"
    }
  }
}

data "digitalocean_kubernetes_cluster" "primary" {
  name = var.doks_cluster_name
}

provider "kubernetes" {
  host             = data.digitalocean_kubernetes_cluster.primary.endpoint
  token            = data.digitalocean_kubernetes_cluster.primary.kube_config[0].token
  cluster_ca_certificate = base64decode(
    data.digitalocean_kubernetes_cluster.primary.kube_config[0].cluster_ca_certificate
  )
}

provider "kubectl" {
  host             = data.digitalocean_kubernetes_cluster.primary.endpoint
  token            = data.digitalocean_kubernetes_cluster.primary.kube_config[0].token
  cluster_ca_certificate = base64decode(
    data.digitalocean_kubernetes_cluster.primary.kube_config[0].cluster_ca_certificate
  )
}

# GitHub
provider "github" {
  owner = var.github_user
  token = var.github_token
}

data "github_repository" "main" {
  name = var.git_repository_name
}

# SSH Deploy Key to use by Flux CD
resource "tls_private_key" "main" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "github_repository_deploy_key" "main" {
  title      = var.doks_cluster_name
  repository = data.github_repository.main.name
  key        = tls_private_key.main.public_key_openssh
  read_only  = true
}

resource "github_repository_file" "install" {
  repository = data.github_repository.main.name
  file       = data.flux_install.main.path
  content    = data.flux_install.main.content
  branch     = var.git_repository_branch
}

resource "github_repository_file" "sync" {
  repository = data.github_repository.main.name
  file       = data.flux_sync.main.path
  content    = data.flux_sync.main.content
  branch     = var.git_repository_branch
}

resource "github_repository_file" "kustomize" {
  repository = data.github_repository.main.name
  file       = data.flux_sync.main.kustomize_path
  content    = data.flux_sync.main.kustomize_content
  branch     = var.git_repository_branch
}

# Flux CD
data "flux_install" "main" {
  target_path = var.git_repository_sync_path
}

data "flux_sync" "main" {
  target_path = var.git_repository_sync_path
  url         = "ssh://git@github.com/${var.github_user}/${var.git_repository_name}.git"
  branch      = var.git_repository_branch
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
    known_hosts    = "github.com ${var.github_ssh_pub_key}"
  }
}
