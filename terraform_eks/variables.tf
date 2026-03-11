variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-southeast-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "fp-platform"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.50.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for subnets"
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs of public subnets"
  type        = list(string)
  default     = ["10.50.1.0/24", "10.50.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs of private subnets"
  type        = list(string)
  default     = ["10.50.11.0/24", "10.50.12.0/24"]
}

variable "cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "node_instance_types" {
  description = "Managed Linux node instance types"
  type        = list(string)
  default     = ["t3.micro"]
}

variable "node_min_size" {
  description = "Minimum Linux node count"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum Linux node count"
  type        = number
  default     = 3
}

variable "node_desired_size" {
  description = "Desired Linux node count"
  type        = number
  default     = 2
}

variable "prometheus_namespace" {
  description = "Namespace for Prometheus deployment"
  type        = string
  default     = "monitoring"
}

variable "grafana_admin_username" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "monitoring_basic_auth_htpasswd" {
  description = "htpasswd-formatted credentials for ingress basic auth, for example: user:{SHA}..."
  type        = string
  default     = "admin:{SHA}0DPiKuNIrrVmD8IUCuw1hQxNqZc="
  sensitive   = true
}

variable "use_local_helm_charts" {
  description = "Set true to install charts from local .tgz files instead of remote repositories"
  type        = bool
  default     = false
}

variable "ingress_nginx_chart_repository" {
  description = "Repository URL for ingress-nginx chart"
  type        = string
  default     = "https://kubernetes.github.io/ingress-nginx"
}

variable "ingress_nginx_chart_name" {
  description = "Chart name for ingress-nginx"
  type        = string
  default     = "ingress-nginx"
}

variable "ingress_nginx_chart_version" {
  description = "Chart version for ingress-nginx"
  type        = string
  default     = "4.12.1"
}

variable "ingress_nginx_local_chart_path" {
  description = "Local path to ingress-nginx chart tgz"
  type        = string
  default     = "./charts/ingress-nginx-4.12.1.tgz"
}

variable "kube_prometheus_stack_chart_repository" {
  description = "Repository URL for kube-prometheus-stack chart"
  type        = string
  default     = "https://prometheus-community.github.io/helm-charts"
}

variable "kube_prometheus_stack_chart_name" {
  description = "Chart name for kube-prometheus-stack"
  type        = string
  default     = "kube-prometheus-stack"
}

variable "kube_prometheus_stack_chart_version" {
  description = "Chart version for kube-prometheus-stack"
  type        = string
  default     = "82.1.1"
}

variable "kube_prometheus_stack_local_chart_path" {
  description = "Local path to kube-prometheus-stack chart tgz"
  type        = string
  default     = "./charts/kube-prometheus-stack-82.10.1.tgz"
}
