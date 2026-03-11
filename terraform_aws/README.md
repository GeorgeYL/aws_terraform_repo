# Terraform AWS EC2 Auto Scaling

本目录包含用于配置 AWS EC2 自动扩容的 Terraform 代码。

## 📁 文件结构

```
terraform_aws/
├── main.tf              # 主要 Terraform 配置
├── terraform.tfvars     # 变量配置文件
├── README.md            # 使用说明文档
└── outputs.tf           # 输出定义 (可选，已包含在 main.tf 中)
```

## 🏗️ 架构概览

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud                                   │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                         VPC (10.0.0.0/16)                          │  │
│  │                                                                     │  │
│  │  ┌─────────────┐                     ┌─────────────┐              │  │
│  │  │  Public     │                     │  Public     │              │  │
│  │  │  Subnet 1   │                     │  Subnet 2   │              │  │
│  │  │  (AZ-a)     │                     │  (AZ-b)     │              │  │
│  │  │             │                     │             │              │  │
│  │  │  ┌───────┐  │    ┌───────────┐    │  ┌───────┐  │              │  │
│  │  │  │  NAT  │  │    │    ALB    │    │  │  NAT  │  │              │  │
│  │  │  │  GW   │  │    │           │    │  │  GW   │  │              │  │
│  │  │  └───────┘  │    └───────────┘    │  └───────┘  │              │  │
│  │  └──────┬──────┘          │          └──────┬──────┘              │  │
│  │         │                 │                 │                      │  │
│  │  ┌──────┴─────────────────┴─────────────────┴──────┐              │  │
│  │  │            Private Subnets (EKS/EC2)            │              │  │
│  │  │  ┌─────────────┐                   ┌─────────┐  │              │  │
│  │  │  │  Private    │                   │ Private │  │              │  │
│  │  │  │  Subnet 1   │                   │ Subnet 2│  │              │  │
│  │  │  │  (AZ-a)     │                   │ (AZ-b)  │  │              │  │
│  │  │  │             │                   │         │  │              │  │
│  │  │  │ ┌────────┐  │                   │ ┌─────┐ │  │              │  │
│  │  │  │ │  EC2   │  │◄───── ASG ───────►│ │EC2  │ │  │              │  │
│  │  │  │ │ (min 2)│  │      Scale        │ │(max │ │  │              │  │
│  │  │  │ └────────┘  │                   │ └─────┘ │  │              │  │
│  │  │  │             │                   │         │  │              │  │
│  │  │  └─────────────┘                   └─────────┘  │              │  │
│  │  └─────────────────────────────────────────────────┘              │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  Auto Scaling Policies:                                            │  │
│  │  • Target Tracking (CPU 70%)                                       │  │
│  │  • Scale Up Alarm (CPU >= 70%)                                     │  │
│  │  • Scale Down Alarm (CPU <= 30%)                                   │  │
│  │  • Scheduled Actions (Optional)                                    │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

## 🚀 快速开始

### 1. 前置条件

- Terraform >= 1.0.0
- AWS CLI 已配置
- AWS 凭证（通过 `~/.aws/credentials` 或环境变量）

### 2. 初始化 Terraform

```bash
cd terraform_aws
terraform init
```

### 3. 配置变量

编辑 `terraform.tfvars` 文件，根据你的环境修改以下参数：

```hcl
environment    = "dev"  # dev, stg, uat, prd
instance_type  = "t3.medium"
min_size       = 2
max_size       = 10
desired_capacity = 3
```

### 4. 预览执行计划

```bash
terraform plan
```

### 5. 应用配置

```bash
terraform apply
```

确认输入 `yes` 后，Terraform 将创建所有资源。

## 📊 多环境部署

为不同环境创建独立的配置文件：

```bash
# 开发环境
terraform plan -var-file=terraform.tfvars -out=tfplan-dev
terraform apply tfplan-dev

# 生产环境（使用不同的 tfvars 文件）
terraform plan -var-file=terraform-prd.tfvars -out=tfplan-prd
terraform apply tfplan-prd
```

### 环境配置示例

| 参数 | DEV | STG | UAT | PRD |
|------|-----|-----|-----|-----|
| `min_size` | 2 | 2 | 3 | 5 |
| `max_size` | 10 | 10 | 15 | 20 |
| `desired_capacity` | 3 | 3 | 5 | 8 |
| `instance_type` | t3.medium | t3.medium | t3.large | t3.xlarge |

## 🔧 扩容策略说明

### 自动扩容（基于 CPU 使用率）

| 策略 | 触发条件 | 操作 | 冷却时间 |
|------|---------|------|---------|
| **Scale Up** | CPU >= 70% (持续 2 个周期) | +1 实例 | 60 秒 |
| **Scale Down** | CPU <= 30% (持续 2 个周期) | -1 实例 | 300 秒 |
| **Target Tracking** | 平均 CPU 偏离 70% | 自动调整 | - |

### 定时扩容（可选）

启用 `enable_asg_scheduled_actions = true` 后：

- **早上 8:00 (SGT)**: 扩容到 `desired_capacity`
- **晚上 10:00 (SGT)**: 缩容到 `min_size`

## 📝 主要资源列表

| 资源类型 | 资源名称 | 说明 |
|---------|---------|------|
| `aws_vpc` | `main` | VPC 网络 |
| `aws_subnet` | `public`, `private` | 公有/私有子网 |
| `aws_internet_gateway` | `main` | 互联网网关 |
| `aws_nat_gateway` | `main` | NAT 网关 |
| `aws_security_group` | `alb`, `ec2` | 安全组 |
| `aws_lb` | `main` | Application Load Balancer |
| `aws_launch_template` | `main` | EC2 启动模板 |
| `aws_autoscaling_group` | `main` | 自动扩缩组 |
| `aws_autoscaling_policy` | `scale_up`, `scale_down`, `target_tracking` | 扩缩容策略 |
| `aws_cloudwatch_metric_alarm` | `cpu_high`, `cpu_low` | CloudWatch 告警 |

## 🔍 查看输出

应用完成后，查看输出信息：

```bash
terraform output
```

输出包括：
- VPC ID
- 子网 ID
- ALB DNS 名称
- ASG 名称和 ARN
- 安全组 ID

## 🧹 清理资源

```bash
# 销毁所有创建的资源
terraform destroy
```

确认输入 `yes` 后，Terraform 将删除所有资源。

## ⚙️ 自定义配置

### 更改实例类型

```hcl
instance_type = "t3.large"  # 或 t3.xlarge, m5.large 等
```

### 使用自定义 AMI

```hcl
ami_id = "ami-0xxxxxxxxx"  # 替换为你的 AMI ID
```

### 配置 SSH 访问

```hcl
ssh_key_name = "your-key-pair-name"
```

然后在 Launch Template 中添加 SSH 访问：

```hcl
# 在 security_group "ec2" 中添加
ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["YOUR_OFFICE_IP/32"]  # 替换为你的 IP
}
```

### 启用详细监控

```hcl
enable_monitoring = true  # 会产生额外费用
```

### 配置 HTTPS 监听器

在 `main.tf` 中取消注释并配置 SSL 证书：

```hcl
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = "arn:aws:acm:region:account-id:certificate/cert-id"
  # ...
}
```

## 📋 最佳实践

1. **多可用区部署**: 确保在至少 2 个可用区部署实例以提高可用性
2. **健康检查**: 使用 ELB 健康检查确保流量只路由到健康的实例
3. **最小权限**: IAM 角色只授予必要的权限
4. **加密**: 启用 EBS 加密保护数据安全
5. **标签策略**: 使用标签进行成本分配和资源管理
6. **状态后端**: 配置 S3 + DynamoDB 用于团队协同

## 🔗 相关文档

- [AWS Auto Scaling 文档](https://docs.aws.amazon.com/autoscaling/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/)
- [EC2 最佳实践](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-best-practices.html)

## 🛠️ 故障排查（本次实践）

### 1. Terraform state lock 获取失败（DynamoDB key schema 不匹配）

**现象**

执行 `terraform plan` 或 `terraform apply` 时出现：

```text
Error acquiring the state lock
ValidationException: Missing the key lockID in the item
ValidationException: The provided key element does not match the schema
```

**原因**

Terraform S3 backend 使用 DynamoDB 做锁时，表的分区键必须是：

- 键名：`LockID`（大小写敏感）
- 类型：`S`（String）

如果表里是 `lockID` / `lockid`，就会报上述错误。

**修复方法**

1. 使用 `terraform_backend` 目录统一管理后端资源（S3 + DynamoDB）。
2. 确保 lock table 使用 `hash_key = "LockID"`。
3. 在业务目录执行：

```bash
cd terraform_aws
terraform init -reconfigure
terraform plan
```

**执行日志（节选）**

```text
Acquiring state lock. This may take a few moments...
Error: Error acquiring the state lock
ValidationException: Missing the key lockID in the item
ValidationException: The provided key element does not match the schema

# 修复后
Initializing the backend...
Successfully configured the backend "s3"!
Acquiring state lock. This may take a few moments...
Plan: 30 to add, 0 to change, 0 to destroy.
Releasing state lock. This may take a few moments...
```

### 2. Auto Scaling Group 创建失败（实例规格不符合 Free Tier）

**现象**

`terraform apply` 过程中 ASG 报错：

```text
The specified instance type is not eligible for Free Tier
```

**原因**

`instance_type = "t3.medium"` 在当前账户策略下不可用（或非 Free Tier 可用规格）。

**修复方法**

在 `terraform.tfvars` 中改为更小规格（例如 `t3.micro`），然后重新 apply：

```hcl
instance_type = "t3.micro"
```

```bash
cd terraform_aws
terraform apply -auto-approve -lock-timeout=60s
```

**执行日志（节选）**

```text
# 失败（t3.medium）
Error: waiting for Auto Scaling Group (finpoints-platform-dev-asg) capacity satisfied
The specified instance type is not eligible for Free Tier

# 修复后（t3.micro）
aws_autoscaling_group.main: Creation complete
Apply complete! Resources: 6 added, 1 changed, 1 destroyed.
```

**当前已验证可用值**

- `instance_type = "t3.micro"`

## 📌 Runbook Timeline

| 时间/阶段 | 执行命令 | 现象/报错 | 处理动作 | 结果 |
|------|------|------|------|------|
| Backend 初始化阶段 | `terraform init` / `terraform plan` | `Error acquiring the state lock` + `Missing the key lockID in the item` | 修正 DynamoDB 锁表 schema 为 `LockID` (String)，并执行 `terraform init -reconfigure` | 锁获取恢复正常，`plan` 可执行 |
| 首次资源部署阶段 | `terraform apply -auto-approve -lock-timeout=60s` | ASG 报错：`instance type is not eligible for Free Tier` | 将 `terraform.tfvars` 中 `instance_type` 从 `t3.medium` 调整为 `t3.micro` | ASG 创建成功 |
| 修复后复验阶段 | `terraform apply -auto-approve -lock-timeout=60s` | 无阻塞错误 | 保持后端与实例规格修复配置 | `Apply complete! Resources: 6 added, 1 changed, 1 destroyed.` |

---

*Last Updated: March 2026*