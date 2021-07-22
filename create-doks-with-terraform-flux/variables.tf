# DOKS
variable "do_token" {
  type = string
  description = "DigitalOcean API token"
  sensitive = true
}

variable "doks_cluster_name" {
  type = string
  default = "doks-fluxcd-cluster"
  description = "DOKS cluster name"
}

variable "doks_cluster_region" {
  type = string
  default = "lon1"
  description = "DOKS cluster region"
}

variable "doks_cluster_version" {
  type = string
  default = "1.21.2-do.2" # Grab the latest version slug from `doctl kubernetes options versions`
  description = "Kubernetes version provided by DOKS"
}

variable "doks_cluster_pool_size" {
  type = string
  default = "s-2vcpu-4gb"
  description = "DOKS cluster node pool size"
}

variable "doks_cluster_pool_nodes" {
  type = map
  default = {
    min = 3
    max = 5
  }
  description = "DOKS cluster node pool limits"
}

# Github
variable "github_owner" {
  type        = string
  description = "github owner"
}

variable "github_token" {
  type        = string
  description = "github token"
  sensitive = true
}

variable "github_ssh_pub_key" {
  type        = string
  default     = "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ=="
  description = "github ssh public key"
}

variable "github_repository_name" {
  type        = string
  description = "github repository name"
}

variable "github_repository_visibility" {
  type        = string
  default     = "public"
  description = "github repo visibility"
}

variable "github_repository_branch" {
  type        = string
  default     = "main"
  description = "github repository branch name"
}

variable "github_repository_target_path" {
  type        = string
  description = "flux sync target path"
}
