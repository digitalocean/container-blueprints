variable "cluster_name" {
  description = "DOKS cluster name"
  type        = string
}

variable "cluster_region" {
  description = "DOKS cluster region"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version provided by DOKS"
  type        = string
  default     = "1.21.3-do.0" # Grab the latest version slug from "doctl kubernetes options versions"
}

variable "cluster_pool_size" {
  description = "DOKS cluster node pool size"
  type        = string
}

variable "cluster_pool_node_count" {
  description = "DOKS cluster worker nodes count"
  type        = number
}
