# ArgoCD GitOps 工作流程文档

## 1. 概述

本文档描述 ArgoCD 如何检测新的构建并自动更新 Kubernetes 应用，以及如何在 EKS 环境中实现完整的 GitOps 流程。

## 2. ArgoCD 核心原理：GitOps

```
┌─────────────────────────────────────────────────────────────────┐
│  ArgoCD GitOps 流程                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  开发者 → CI Pipeline → 构建镜像 → 更新 Manifest → Git Repo     │
│                              ↓                                  │
│  ArgoCD 检测 Git 变更                                           │
│                              ↓                                  │
│  ArgoCD 对比 Git vs 集群状态                                      │
│                              ↓                                  │
│  发现差异 (OutOfSync) → 自动/手动同步到目标状态                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### GitOps 四大原则

1. **声明式配置** - 系统期望状态以声明式方式描述
2. **版本化存储** - 配置存储在版本控制的 Git 仓库中
3. **自动同步** - 软件代理自动将实际状态同步到期望状态
4. **持续校准** - 软件代理持续监控并纠正状态漂移

## 3. ArgoCD 检测机制

ArgoCD 通过以下方式检测新的构建版本：

| 检测方式 | 说明 | 优点 | 缺点 |
|----------|------|------|------|
| **轮询 Git 仓库** | 定期 (默认 3 分钟) 检查 Git 仓库的 manifest 变化 | 简单可靠 | 有延迟 |
| **Webhook 触发** | Git 平台 (GitHub/GitLab) 推送时通知 ArgoCD | 实时响应 | 需要配置 Webhook |
| **手动刷新** | 用户点击 UI 或调用 API 触发刷新 | 灵活控制 | 非自动化 |

### 3.1 轮询机制配置

```yaml
# argocd-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  # 状态对比间隔 (默认 3 分钟)
  timeout.reconciliation: 180s
  
  # 操作处理超时
  operation.processing.timeout: 180s
```

### 3.2 Webhook 配置

#### GitHub Webhook

```
Webhook URL: https://<argocd-server>/api/webhook
Content Type: application/json
Secret: <webhook-secret>
Events: Push events
```

#### GitLab Webhook

```
Webhook URL: https://<argocd-server>/api/webhook
Secret Token: <webhook-secret>
Trigger: Push events
```

#### 配置 Webhook Secret

```bash
# 生成 webhook secret
kubectl -n argocd create secret generic argocd-webhook-secret \
  --from-literal=webhookSecret=<your-secret>
```

## 4. 详细执行流程

### 步骤 1: 应用清单存储在 Git

```
git-repository/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── configmap.yaml
├── overlays/
│   ├── development/
│   │   └── kustomization.yaml
│   ├── staging/
│   │   └── kustomization.yaml
│   └── production/
│       └── kustomization.yaml
└── helm-values/
    ├── development-values.yaml
    ├── staging-values.yaml
    └── production-values.yaml
```

### 步骤 2: ArgoCD 拉取最新清单

```
┌─────────────────────────────────────┐
│  ArgoCD Repo Server                 │
│                                     │
│  - 克隆 Git 仓库                     │
│  - 渲染 Helm Chart                  │
│  - 渲染 Kustomize                   │
│  - 生成 Kubernetes Manifest         │
│  - 缓存渲染结果                      │
└─────────────────────────────────────┘
```

### 步骤 3: 对比状态

```
┌─────────────────────────────────────┐
│  ArgoCD Application Controller      │
│                                     │
│  Git 状态 (期望状态)                  │
│         vs                          │
│  集群状态 (实际状态)                  │
│                                     │
│  对比结果：                          │
│  - Synced (已同步)                   │
│  - OutOfSync (不同步)                │
│  - Degraded (降级)                   │
│  - Missing (缺失)                    │
│  - Unknown (未知)                    │
└─────────────────────────────────────┘
```

### 步骤 4: 同步 (Sync)

```
┌─────────────────────────────────────┐
│  同步策略：                          │
│  - 自动同步 (autoSync: true)         │
│  - 手动同步 (用户点击 Sync)           │
│                                     │
│  同步选项：                          │
│  - Prune: 删除额外资源               │
│  - Self-Heal: 自动修复漂移           │
│  - Create Namespace: 创建命名空间    │
└─────────────────────────────────────┘
```

## 5. ArgoCD Application 配置

### 5.1 基础 Application 配置

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  # Git 仓库配置
  source:
    repoURL: https://github.com/myorg/myapp-manifests.git
    targetRevision: HEAD
    path: overlays/production
    
  # 目标集群配置
  destination:
    server: https://kubernetes.default.svc
    namespace: production
    
  # 项目配置
  project: default
  
  # 自动同步配置
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
      - ApplyOutOfSyncOnly=true
      
  # 忽略差异配置
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
    - group: apps
      kind: StatefulSet
      jsonPointers:
        - /spec/replicas
```

### 5.2 Helm 应用配置

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-helm-app
  namespace: argocd
spec:
  source:
    repoURL: https://charts.bitnami.com/bitnami
    chart: nginx
    targetRevision: 15.0.0
    helm:
      releaseName: my-nginx
      values: |
        replicaCount: 3
        service:
          type: LoadBalancer
      valueFiles:
        - values-production.yaml
        
  destination:
    server: https://kubernetes.default.svc
    namespace: production
    
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 5.3 Kustomize 应用配置

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-kustomize-app
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/myorg/myapp-manifests.git
    targetRevision: HEAD
    path: overlays/production
    
  destination:
    server: https://kubernetes.default.svc
    namespace: production
    
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## 6. CI/CD 集成流程

### 6.1 GitLab CI 完整示例

```yaml
# .gitlab-ci.yml
stages:
  - build
  - deploy

variables:
  IMAGE_REGISTRY: "${CI_REGISTRY}"
  IMAGE_NAME: "${CI_PROJECT_PATH}"
  IMAGE_TAG: "${CI_COMMIT_SHA}"
  LATEST_TAG: "latest"
  MANIFEST_REPO: "git@github.com:myorg/myapp-manifests.git"
  MANIFEST_BRANCH: "main"

build:
  stage: build
  image: docker:24.0
  services:
    - docker:24.0-dind
  script:
    # 登录镜像仓库
    - docker login -u ${CI_REGISTRY_USER} -p ${CI_REGISTRY_PASSWORD} ${IMAGE_REGISTRY}
    
    # 构建并推送镜像
    - docker build -t ${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} .
    - docker push ${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
    
    # 推送 latest 标签
    - docker tag ${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_REGISTRY}/${IMAGE_NAME}:${LATEST_TAG}
    - docker push ${IMAGE_REGISTRY}/${IMAGE_NAME}:${LATEST_TAG}
  only:
    - main

update-manifest:
  stage: deploy
  image: alpine/git
  script:
    # 克隆 manifest 仓库
    - git clone ${MANIFEST_REPO} manifests
    - cd manifests
    
    # 配置 Git
    - git config user.name "GitLab CI"
    - git config user.email "ci@gitlab.com"
    
    # 更新镜像标签
    - sed -i "s|image: ${IMAGE_REGISTRY}/${IMAGE_NAME}:.*|image: ${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}|" deployment.yaml
    
    # 提交并推送
    - git add deployment.yaml
    - git commit -m "Update image to ${IMAGE_TAG} [skip ci]"
    - git push ${MANIFEST_REPO} HEAD:${MANIFEST_BRANCH}
  only:
    - main
```

### 6.2 使用 ArgoCD Image Updater

```yaml
# 安装 ArgoCD Image Updater
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd-image-updater argo/argocd-image-updater \
  -n argocd \
  --create-namespace

# Image Updater 配置
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: argocd
data:
  registries.conf: |
    registries:
      - name: Docker Hub
        api_url: https://registry-1.docker.io
        prefix: docker.io
        credentials: secret:argocd-image-updater/dockerhub-creds
      - name: GitLab Registry
        api_url: https://gitlab.com
        prefix: registry.gitlab.com
        credentials: secret:argocd-image-updater/gitlab-creds
```

### 6.3 应用注解配置 (Image Updater)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: production
  annotations:
    # 镜像列表
    argocd-image-updater.argoproj.io/image-list: myregistry/myapp
    
    # 更新策略
    argocd-image-updater.argoproj.io/update-strategy: latest
    
    # 写回方法 (git/argocd)
    argocd-image-updater.argoproj.io/write-back-method: git
    
    # Git 仓库配置
    argocd-image-updater.argoproj.io/git-repository: git@github.com:myorg/myapp-manifests.git
    argocd-image-updater.argoproj.io/git-branch: main
    
    # 镜像名称
    argocd-image-updater.argoproj.io/myapp.image-name: myregistry/myapp
    
    # 允许标签
    argocd-image-updater.argoproj.io/myapp.allow-tags: regexp:^v[0-9]+\.[0-9]+\.[0-9]+$
    
    # 更新频率
    argocd-image-updater.argoproj.io/myapp.update-strategy: semver
```

## 7. 镜像更新自动化方案对比

### 方案 A: ArgoCD Image Updater (推荐)

| 特性 | 说明 |
|------|------|
| **自动发现** | 自动扫描镜像仓库发现新标签 |
| **策略驱动** | 支持 latest/semver/regexp 等策略 |
| **写回 Git** | 自动提交 manifest 变更 |
| **多仓库支持** | 支持 Docker Hub、GitLab、ECR 等 |

### 方案 B: CI 更新 Manifest

| 特性 | 说明 |
|------|------|
| **简单直接** | CI 脚本直接更新 Git 文件 |
| **完全控制** | 可自定义更新逻辑 |
| **无需额外组件** | 只需 Git 仓库 |

### 方案 C: Kustomize Image 更新

```yaml
# kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

images:
  - name: myregistry/myapp
    newTag: v1.2.3
    newName: myregistry/myapp
    digest: sha256:abc123...

resources:
  - deployment.yaml
```

### 方案 D: Helm Values 更新

```yaml
# values.yaml
image:
  repository: myregistry/myapp
  tag: v1.2.3
  pullPolicy: IfNotPresent
```

## 8. 状态说明

| 状态 | 说明 | 处理方式 |
|------|------|----------|
| **Synced** | Git 与集群状态一致 | 无需操作 |
| **OutOfSync** | 检测到差异 | 自动/手动同步 |
| **Degraded** | 应用健康检查失败 | 检查日志/事件 |
| **Missing** | 资源不存在 | 同步创建 |
| **Unknown** | 无法确定状态 | 手动检查 |
| **Suspended** | 应用已暂停 | 恢复应用 |

## 9. 常见问题排查

### 9.1 应用一直处于 OutOfSync 状态

```bash
# 查看应用详情
argocd app get <app-name>

# 查看应用日志
argocd app logs <app-name>

# 强制刷新
argocd app get <app-name> --refresh

# 强制同步
argocd app sync <app-name> --force
```

### 9.2 Webhook 不工作

```bash
# 检查 Webhook 配置
kubectl -n argocd get secret argocd-webhook-secret

# 查看 ArgoCD server 日志
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-server

# 测试 Webhook
curl -X POST https://<argocd-server>/api/webhook \
  -H "Content-Type: application/json" \
  -d '{"ref": "refs/heads/main"}'
```

### 9.3 镜像不更新

```bash
# 检查 Image Updater 状态
kubectl -n argocd get pods -l app.kubernetes.io/name=argocd-image-updater

# 查看 Image Updater 日志
kubectl -n argocd logs -l app.kubernetes.io/name=argocd-image-updater

# 检查应用注解
kubectl get application <app-name> -n argocd -o yaml
```

## 10. 最佳实践

### 10.1 Git 仓库结构

```
manifests/
├── apps/
│   ├── app1/
│   │   ├── base/
│   │   └── overlays/
│   │       ├── development/
│   │       ├── staging/
│   │       └── production/
│   └── app2/
├── clusters/
│   ├── cluster1/
│   └── cluster2/
└── argocd/
    └── applications/
```

### 10.2 分支策略

| 策略 | 说明 |
|------|------|
| **单分支** | 所有环境使用同一分支，不同目录 |
| **多分支** | 每个环境使用独立分支 (dev/staging/prod) |
| **多仓库** | 每个环境使用独立仓库 |

### 10.3 安全配置

```yaml
# AppProject 限制
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: production
  namespace: argocd
spec:
  # 允许的 Git 仓库
  sourceRepos:
    - https://github.com/myorg/.*
    
  # 允许的目标集群
  destinations:
    - namespace: production
      server: https://kubernetes.default.svc
      
  # 允许的 K8s 资源
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
    - group: apps
      kind: Deployment
      
  # 禁止的资源
  namespaceResourceBlacklist:
    - group: ''
      kind: Secret
```

### 10.4 健康检查配置

```yaml
# 自定义健康检查
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  resource.customizations.health.argoproj.io_Application: |
    hs = {}
    if obj.status.sync.status == "Synced" then
      hs.status = "Healthy"
      hs.message = "Application is synced"
      return hs
    end
    hs.status = "Progressing"
    hs.message = "Waiting for sync"
    return hs
```

## 11. 监控与告警

### 11.1 Prometheus 指标

```yaml
# ArgoCD 暴露的指标
- argocd_app_info{sync_status="OutOfSync"}
- argocd_app_health_status{health_status="Degraded"}
- argocd_cluster_api_request_total
- argocd_repo_server_cache_hits_total
- argocd_sync_created
```

### 11.2 Grafana 看板

导入 ArgoCD 官方 Dashboard:
- Dashboard ID: 14584
- Dashboard ID: 13943

### 11.3 告警规则

```yaml
# PrometheusRule
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: argocd-rules
  namespace: argocd
spec:
  groups:
    - name: argocd
      rules:
        - alert: ArgoAppOutOfSync
          expr: argocd_app_info{sync_status="OutOfSync"} == 1
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "ArgoCD 应用不同步"
            description: "应用 {{ $labels.name }} 已不同步超过 5 分钟"
            
        - alert: ArgoAppDegraded
          expr: argocd_app_health_status{health_status="Degraded"} == 1
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "ArgoCD 应用降级"
            description: "应用 {{ $labels.name }} 健康状态降级"
```

## 12. 完整示例：从构建到部署

```
┌─────────────────────────────────────────────────────────────┐
│  完整 CI/CD + GitOps 流程                                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. 开发者推送代码                                           │
│     git push origin main                                    │
│                                                             │
│  2. GitLab CI 触发构建                                       │
│     - 构建 Docker 镜像                                        │
│     - 推送到镜像仓库：myregistry/myapp:abc123               │
│     - 更新 Git manifest：deployment.yaml image tag          │
│     - git push 到 manifests 仓库                             │
│                                                             │
│  3. ArgoCD 检测到 Git 变更                                    │
│     - Webhook 触发或轮询发现新 commit                        │
│     - 拉取最新 manifest                                     │
│     - Repo Server 渲染 Helm/Kustomize                       │
│     - 对比集群状态 → OutOfSync                              │
│                                                             │
│  4. ArgoCD 自动同步                                           │
│     - Application Controller 应用新配置                       │
│     - Kubernetes 滚动更新 Pod                                │
│     - 健康检查通过 → Synced                                 │
│                                                             │
│  5. 监控与通知                                                │
│     - Prometheus 记录指标                                    │
│     - Slack/邮件通知部署结果                                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 13. 参考资源

- [ArgoCD 官方文档](https://argo-cd.readthedocs.io/)
- [ArgoCD Image Updater](https://argocd-image-updater.readthedocs.io/)
- [GitOps 原则](https://opengitops.dev/)
- [Argo Helm Charts](https://github.com/argoproj/argo-helm)
- [Kubernetes 官方文档](https://kubernetes.io/docs/)