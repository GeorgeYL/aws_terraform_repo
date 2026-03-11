aws_region   = "ap-southeast-1"
environment  = "dev"
project_name = "fp-platform"

vpc_cidr             = "10.50.0.0/16"
availability_zones   = ["ap-southeast-1a", "ap-southeast-1b"]
public_subnet_cidrs  = ["10.50.1.0/24", "10.50.2.0/24"]
private_subnet_cidrs = ["10.50.11.0/24", "10.50.12.0/24"]

cluster_version     = "1.30"
node_instance_types = ["t3.small"]
node_min_size       = 2
node_max_size       = 3
node_desired_size   = 2

prometheus_namespace = "monitoring"

grafana_admin_username = "admin"
grafana_admin_password = "admin"

monitoring_basic_auth_htpasswd = "admin:{SHA}0DPiKuNIrrVmD8IUCuw1hQxNqZc="

use_local_helm_charts = true

ingress_nginx_chart_repository = "https://kubernetes.github.io/ingress-nginx"
ingress_nginx_chart_name       = "ingress-nginx"
ingress_nginx_chart_version    = "4.12.1"
ingress_nginx_local_chart_path = "./charts/ingress-nginx-4.12.1.tgz"

kube_prometheus_stack_chart_repository = "https://prometheus-community.github.io/helm-charts"
kube_prometheus_stack_chart_name       = "kube-prometheus-stack"
kube_prometheus_stack_chart_version    = "82.1.1"
kube_prometheus_stack_local_chart_path = "./charts/kube-prometheus-stack-82.10.1.tgz"
