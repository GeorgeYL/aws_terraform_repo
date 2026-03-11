# Terraform AWS EKS Monitoring Stack

本目录用于创建 AWS EKS 集群，并部署完整监控栈：Ingress、Prometheus、node-exporter、Grafana。

## 实现内容

- 创建 VPC（2 个公有子网 + 2 个私有子网）
- 创建 EKS 集群
                                   Internet
                                      |
                                      v
                         +---------------------------+
                         |  AWS NLB (Public)         |
                         |  ingress-nginx Service    |
                         +---------------------------+
                                      |
                                      v
                         +---------------------------+
                         |  ingress-nginx Controller |
                         |  Namespace: monitoring    |
                         +---------------------------+
                             |                 |
          /prometheus ------+                 +------ /grafana
                             |                 |
                             v                 v
                +-------------------+   +-------------------+
                | Prometheus Server |   | Grafana           |
                | kube-prom-stack   |   | admin/admin       |
                +-------------------+   +-------------------+
                          |
                          v
                +-------------------+
                | node-exporter DS  |
                | on Linux nodes    |
                +-------------------+

   +-------------------------------------------------------------------+
   | EKS Cluster (fp-platform-dev-eks)                                 |
   | - Managed Node Group: linux-ng (desired=2)                        |
   | - Private subnets: worker nodes                                   |
   | - Public subnets: NLB endpoints                                   |
   +-------------------------------------------------------------------+
								  |
								  v
					 +-------------------+
					 | node-exporter DS  |
					 | on Linux nodes    |
					 +-------------------+

	+-------------------------------------------------------------------+
	| EKS Cluster (fp-platform-dev-eks)                                 |
	| - Managed Node Group: linux-ng (desired=2)                        |
	| - Private subnets: worker nodes                                   |
	| - Public subnets: NLB endpoints                                   |
	+-------------------------------------------------------------------+

Security:
- Basic Auth at ingress for /prometheus and /grafana
- NLB health check: HTTP /healthz on port 10254
```

## 快速开始

```bash
cd terraform_eks
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

部署完成后可查看输出：

```bash
terraform output monitoring_ingress_public_endpoint
terraform output prometheus_public_url
terraform output grafana_public_url
```

如果输出为 `PENDING`，通常是 AWS Load Balancer 正在创建，等待几分钟后再次执行 `terraform output`。

## Network-Restricted Fallback (Local Helm Charts)

如果当前环境无法访问 GitHub/Helm 仓库，可使用本地 chart 包部署：

1. 在可联网环境下载以下文件到 `terraform_eks/charts/`：
    - `ingress-nginx-4.12.1.tgz`
    - `kube-prometheus-stack-82.10.1.tgz`
2. 在 `terraform.tfvars` 设置：
    - `use_local_helm_charts = true`
    - 并确认本地路径变量指向上述文件
3. 重新执行：

```bash
terraform plan -out plan-local.tfplan
terraform apply "plan-local.tfplan"
```

## 关键变量

- `node_desired_size`: 期望 Linux 节点数（默认 2）
- `node_min_size`: 最小 Linux 节点数（默认 2）
- `node_max_size`: 最大 Linux 节点数（默认 3）
- `prometheus_namespace`: Prometheus 命名空间（默认 `monitoring`）
- `grafana_admin_username`: Grafana 管理员用户名（默认 `admin`）
- `grafana_admin_password`: Grafana 管理员密码（默认 `admin`）
- `monitoring_basic_auth_htpasswd`: Monitoring 入口 Basic Auth 的 htpasswd 字符串（默认对应 `admin/admin`）

## Prometheus 公网访问说明

本工程使用 `ingress-nginx` 的 `LoadBalancer`（internet-facing NLB）对外提供统一入口。

同时已配置 NLB 健康检查：

- 协议：`HTTP`
- 路径：`/healthz`
- 端口：`10254`（ingress-nginx controller 健康端口）

创建完成后，AWS 会分配一个公网 DNS：

- Prometheus: `http://<LB_DNS>/prometheus`
- Grafana: `http://<LB_DNS>/grafana`

Ingress 已启用 Basic Auth，默认凭据：`admin/admin`。

Grafana 默认数据源已配置为 Prometheus（由 `kube-prometheus-stack` 自动注入）。

## 清理资源

```bash
terraform destroy -var-file=terraform.tfvars
```

## 相关文档

更多详细信息，请参考以下文档：

| 文档 | 描述 |
|------|------|
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | 故障排查指南 |
| [docs/GITLAB_CI_WORKFLOW.md](docs/GITLAB_CI_WORKFLOW.md) | GitLab CI/CD 工作流程 |
| [docs/ARGOCD_WORKFLOW.md](docs/ARGOCD_WORKFLOW.md) | ArgoCD GitOps 工作流程 |

### 文档摘要

#### GitLab CI/CD 工作流程

- **核心组件**: GitLab Server、.gitlab-ci.yml、GitLab Runner、Executor
- **执行流程**: 代码推送 → Pipeline 创建 → Runner 调度 → Job 执行 → 结果上报
- **Runner 类型**: Shared、Group、Project、Specific Runner
- **安全配置**: CI/CD Variables、Protected Branches、Protected Runners

#### ArgoCD GitOps 工作流程

- **检测机制**: 轮询 Git 仓库、Webhook 触发、手动刷新
- **执行流程**: 清单存储 → 拉取清单 → 对比状态 → 同步
- **镜像更新方案**: ArgoCD Image Updater、CI 更新 Manifest、Kustomize、Helm
- **状态说明**: Synced、OutOfSync、Degraded、Missing、Unknown
