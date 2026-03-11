# GitLab CI/CD 工作流程文档

## 1. 概述

本文档描述 GitLab CI/CD 的完整工作流程，以及如何在 EKS/Terraform 项目中使用 GitLab CI 实现自动化部署。

## 2. GitLab CI/CD 整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│  GitLab CI/CD 流程                                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. 开发者推送代码                                              │
│     git push → GitLab Repository                                │
│                    ↓                                            │
│  2. GitLab 检测到 .gitlab-ci.yml                                │
│     自动触发 Pipeline                                           │
│                    ↓                                            │
│  3. GitLab Runner 注册与监听                                    │
│     Runner 轮询 GitLab API 获取任务                              │
│                    ↓                                            │
│  4. 执行 Job                                                    │
│     Runner 拉取代码 → 执行脚本 → 上报结果                        │
│                    ↓                                            │
│  5. 结果展示                                                    │
│     GitLab UI 显示 Pipeline/Job 状态                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 3. 核心组件

| 组件 | 作用 |
|------|------|
| **GitLab Server** | 存储代码、配置，管理 Pipeline 状态 |
| **.gitlab-ci.yml** | 定义 Pipeline 结构、Jobs、执行逻辑 |
| **GitLab Runner** | 实际执行 Job 的工作节点 |
| **Executor** | Runner 内部组件，决定如何运行 Job（Docker、Kubernetes 等） |

## 4. 详细执行流程

### 步骤 1: 代码推送

```
开发者执行 git push
     ↓
GitLab 仓库接收推送
     ↓
检测到 .gitlab-ci.yml 文件
```

### 步骤 2: Pipeline 创建

```
GitLab 解析 .gitlab-ci.yml
     ↓
生成 Pipeline 结构（Stages → Jobs）
     ↓
Jobs 进入 pending 状态，等待 Runner 执行
```

### 步骤 3: Runner 调度

```
GitLab Runner 轮询 API (GET /api/v4/jobs/request)
     ↓
Runner 匹配标签 (tags) 和可用资源
     ↓
GitLab 分配 Job 给匹配的 Runner
     ↓
Job 状态变为 running
```

### 步骤 4: Job 执行

```
Runner 克隆/拉取代码 (git clone/fetch)
     ↓
准备执行环境 (Docker 容器/Shell)
     ↓
执行 before_script → script → after_script
     ↓
收集 artifacts/logs
```

### 步骤 5: 结果上报

```
Runner 将状态/日志发送回 GitLab
     ↓
GitLab 更新 UI 显示
     ↓
Pipeline/Job 状态更新 (success/failed/canceled)
```

## 5. .gitlab-ci.yml 配置示例

### 5.1 基础示例

```yaml
stages:
  - build
  - test
  - deploy

variables:
  TERRAFORM_VERSION: "1.5.0"

build:
  stage: build
  image: hashicorp/terraform:${TERRAFORM_VERSION}
  script:
    - terraform init
    - terraform validate
  tags:
    - docker

test:
  stage: test
  image: hashicorp/terraform:${TERRAFORM_VERSION}
  script:
    - terraform plan
  tags:
    - docker
  only:
    - merge_requests

deploy:
  stage: deploy
  image: hashicorp/terraform:${TERRAFORM_VERSION}
  script:
    - terraform apply -auto-approve
  tags:
    - docker
  only:
    - main
  when: manual
```

### 5.2 EKS/Terraform 项目示例

```yaml
# .gitlab-ci.yml
stages:
  - plan
  - apply

variables:
  TF_ROOT: "${CI_PROJECT_DIR}/terraform_eks"
  TF_VAR_project_name: "fp-platform"
  TF_VAR_environment: "dev"

.terraform_template: &terraform_template
  image: hashicorp/terraform:1.5.0
  before_script:
    - aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
    - aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
    - aws configure set region $AWS_DEFAULT_REGION
    - cd ${TF_ROOT}
  tags:
    - docker

plan:
  <<: *terraform_template
  stage: plan
  script:
    - terraform init
    - terraform plan -out=tfplan
  artifacts:
    paths:
      - terraform_eks/tfplan
    expire_in: 1 hour
  only:
    - merge_requests

apply:
  <<: *terraform_template
  stage: apply
  script:
    - terraform init
    - terraform apply -auto-approve tfplan
  only:
    - main
  when: manual
  environment:
    name: development
```

## 6. Runner 类型

| Runner 类型 | 描述 | 适用场景 |
|------------|------|---------|
| **Shared Runner** | GitLab 实例级别，所有项目可用 | 公共任务、通用构建 |
| **Group Runner** | 组级别，组内项目可用 | 团队共享资源 |
| **Project Runner** | 项目级别，仅特定项目可用 | 项目专用环境 |
| **Specific Runner** | 带特定标签，精确匹配 | 特殊需求（如 EKS 部署） |

## 7. Executor 类型

| Executor | 描述 | 优点 | 缺点 |
|----------|------|------|------|
| **Docker** | 每个 Job 在独立容器中运行 | 隔离性好、环境一致 | 需要 Docker 支持 |
| **Shell** | 直接在 Runner 主机 Shell 执行 | 简单、快速 | 环境污染风险 |
| **Kubernetes** | 在 K8s 集群中创建 Pod 执行 Job | 弹性伸缩、资源隔离 | 配置复杂 |
| **SSH** | 通过 SSH 连接远程服务器执行 | 可复用现有服务器 | 需要 SSH 配置 |
| **Parallels** | 在 Parallels VM 中执行 | 完整 VM 隔离 | 资源消耗大 |

## 8. 安全配置

### 8.1 CI/CD Variables

敏感信息应存储在 GitLab Settings → CI/CD → Variables：

| Variable | 说明 | 建议设置 |
|----------|------|---------|
| `AWS_ACCESS_KEY_ID` | AWS 访问密钥 | Masked, Protected |
| `AWS_SECRET_ACCESS_KEY` | AWS 密钥 | Masked, Protected |
| `AWS_DEFAULT_REGION` | AWS 区域 | - |
| `TF_VAR_grafana_admin_password` | Grafana 密码 | Masked, Protected |

### 8.2 Protected Branches

限制特定分支的 Pipeline 执行：

- `main` / `master`: 仅允许受保护的 Runner 执行
- `release/*`: 需要 Maintainer 权限触发

### 8.3 Protected Runners

仅允许受信任的 Runner 执行敏感任务：

```toml
# config.toml
[[runners]]
  name = "production-runner"
  url = "https://gitlab.example.com/"
  token = "REGISTRATION_TOKEN"
  executor = "docker"
  protected = true
  environment = ["production"]
```

## 9. Runner 注册流程

### 9.1 安装 GitLab Runner

```bash
# Ubuntu/Debian
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
sudo apt-get install gitlab-runner

# CentOS/RHEL
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh | sudo bash
sudo yum install gitlab-runner

# Windows (PowerShell)
New-Item -Path 'C:\GitLabRunner' -ItemType Directory -Force
cd 'C:\GitLabRunner'
wget https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-windows-amd64.zip
Expand-Archive gitlab-runner-windows-amd64.zip -DestinationPath .
.\gitlab-runner.exe install
.\gitlab-runner.exe start
```

### 9.2 注册 Runner

```bash
sudo gitlab-runner register
```

需要输入：

1. **GitLab URL**: 如 `https://gitlab.com/` 或 `https://gitlab.example.com/`
2. **Registration Token**: 从 GitLab UI (Settings → CI/CD → Runners) 获取
3. **Runner 描述**: 如 `docker-runner-01`
4. **Runner 标签**: 如 `docker,terraform,eks`
5. **Executor 类型**: 如 `docker`
6. **Docker 镜像**: 如 `hashicorp/terraform:1.5.0`

### 9.3 验证注册

```bash
# 查看 Runner 状态
sudo gitlab-runner status

# 查看日志
sudo gitlab-runner run --debug
```

## 10. EKS 部署场景下的完整配置

### 10.1 项目结构

```
terraform_eks/
├── .gitlab-ci.yml
├── main.tf
├── variables.tf
├── terraform.tfvars
├── outputs.tf
└── .terraform/
```

### 10.2 .gitlab-ci.yml 完整配置

```yaml
image: amazon/aws-cli:latest

variables:
  TF_ROOT: "${CI_PROJECT_DIR}/terraform_eks"
  TF_VAR_project_name: "fp-platform"
  TF_VAR_environment: "dev"
  AWS_DEFAULT_REGION: "us-east-1"

stages:
  - validate
  - plan
  - apply
  - destroy

before_script:
  - pip install terraform-docs tfsec
  - cd ${TF_ROOT}

# 验证阶段
validate:
  stage: validate
  image: hashicorp/terraform:1.5.0
  script:
    - terraform init
    - terraform validate
    - terraform fmt -check
  tags:
    - docker

# 计划阶段
plan:
  stage: plan
  image: hashicorp/terraform:1.5.0
  before_script:
    - aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
    - aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
    - cd ${TF_ROOT}
  script:
    - terraform init
    - terraform plan -out=tfplan
  artifacts:
    paths:
      - terraform_eks/tfplan
    expire_in: 1 hour
  only:
    - merge_requests
  tags:
    - docker

# 应用阶段
apply:
  stage: apply
  image: hashicorp/terraform:1.5.0
  before_script:
    - aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
    - aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
    - cd ${TF_ROOT}
  script:
    - terraform init
    - terraform apply -auto-approve tfplan
  only:
    - main
  when: manual
  environment:
    name: development
    url: https://console.aws.amazon.com/eks
  tags:
    - docker

# 清理资源
destroy:
  stage: destroy
  image: hashicorp/terraform:1.5.0
  before_script:
    - aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
    - aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
    - cd ${TF_ROOT}
  script:
    - terraform init
    - terraform destroy -auto-approve
  only:
    - main
  when: manual
  variables:
    CONFIRM_DESTROY: "yes"
  tags:
    - docker
```

## 11. 常见问题排查

### 11.1 Runner 不执行 Job

```bash
# 检查 Runner 状态
sudo gitlab-runner status

# 查看 Runner 日志
sudo journalctl -u gitlab-runner -f

# 检查标签匹配
# 确保 Job 的 tags 与 Runner 的 tags 匹配
```

### 11.2 AWS 认证失败

```yaml
# 确保 CI/CD Variables 已配置
# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY
# AWS_DEFAULT_REGION

before_script:
  - aws sts get-caller-identity  # 验证认证
```

### 11.3 Terraform State 锁定

```yaml
# 使用远程 State 避免锁定问题
# main.tf
terraform {
  backend "s3" {
    bucket = "my-terraform-state"
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "terraform-locks"
  }
}
```

## 12. 最佳实践

1. **使用远程 State**: 将 Terraform State 存储在 S3 + DynamoDB
2. **最小权限原则**: AWS IAM 角色仅授予必要权限
3. **代码审查**: 所有变更通过 Merge Request 审查
4. **手动确认**: 生产环境部署使用 `when: manual`
5. **日志保留**: 配置 artifacts 过期时间
6. **并行执行**: 独立任务使用 `parallel` 关键字
7. **缓存依赖**: 使用 `cache` 加速重复构建

## 13. 参考资源

- [GitLab CI/CD 官方文档](https://docs.gitlab.com/ee/ci/)
- [GitLab Runner 文档](https://docs.gitlab.com/runner/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS EKS 文档](https://docs.aws.amazon.com/eks/)