# =========================== GIT ==============================
data "github_repository" "main" {
  name = var.git_repository_name
}
# ==============================================================

# =========================== FLUX CD ===========================
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
# =================================================================
