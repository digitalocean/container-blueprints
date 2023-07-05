# ======================== DOKS =========================
variable "do_api_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "doks_cluster_name" {
  description = "DOKS cluster name"
  type        = string
}

variable "doks_cluster_region" {
  description = "DOKS cluster region"
  type        = string
}

variable "doks_cluster_version" {
  description = "Kubernetes version provided by DOKS"
  type        = string
  default     = "1.21.3-do.0" # Grab the latest version slug from "doctl kubernetes options versions"
}

variable "doks_cluster_pool_size" {
  description = "DOKS cluster node pool size"
  type        = string
}

variable "doks_cluster_pool_node_count" {
  description = "DOKS cluster worker nodes count"
  type        = number
}
# ===========================================================

# ========================== GIT ============================
variable "github_user" {
  description = "GitHub owner"
  type        = string
}

variable "github_token" {
  description = "GitHub token"
  type        = string
  sensitive   = true
}

variable "github_ssh_pub_key" {
  description = "GitHub SSH public key"
  type        = string
  default     = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="
}

variable "git_repository_name" {
  description = "Git main repository to use for installation"
  type        = string
}

variable "git_repository_branch" {
  description = "Branch name to use on the Git repository"
  type        = string
  default     = "main"
}

variable "git_repository_sync_path" {
  description = "Git repository directory path to use for Flux CD sync"
  type        = string
}
# ========================================================================