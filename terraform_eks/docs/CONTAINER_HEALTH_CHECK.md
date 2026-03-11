# 容器健康检查指南

本文档详细介绍容器健康检查的实现方式，包括 Docker 和 Kubernetes 环境下的健康检查配置。

## 目录

1. [Docker 健康检查](#docker-健康检查)
2. [Kubernetes 探针](#kubernetes-探针)
3. [应用端点实现](#应用端点实现)
4. [配置示例](#配置示例)
5. [测试方法](#测试方法)

---

## Docker 健康检查

### HEALTHCHECK 指令

在 Dockerfile 中使用 `HEALTHCHECK` 指令配置健康检查：

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1
```

### 参数说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--interval` | 两次健康检查之间的时间间隔 | 30s |
| `--timeout` | 健康检查命令的超时时间 | 30s |
| `--start-period` | 容器启动后的宽限期（不计算失败） | 0s |
| `--retries` | 连续失败多少次后标记为不健康 | 3 |

### 健康检查状态

- `starting`：容器启动初期
- `healthy`：健康检查通过
- `unhealthy`：健康检查失败

### 查看健康状态

```bash
# 查看容器健康状态
docker inspect --format='{{.State.Health.Status}}' <container_id>

# 查看详细健康信息
docker inspect --format='{{json .State.Health}}' <container_id> | jq
```

---

## Kubernetes 探针

Kubernetes 提供三种类型的探针来管理容器生命周期。

### 1. Liveness Probe（存活探针）

**作用**：判断容器是否运行正常，失败则重启容器。

**适用场景**：
- 检测死锁进程
- 检测内存泄漏
- 检测无法恢复的错误

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 15
  periodSeconds: 10
  timeoutSeconds: 1
  failureThreshold: 3
  successThreshold: 1
```

### 2. Readiness Probe（就绪探针）

**作用**：判断容器是否可接收流量，失败则从 Service 后端移除。

**适用场景**：
- 应用启动需要预热
- 依赖的外部服务暂时不可用
- 需要临时停止接收流量

```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 1
  failureThreshold: 3
  successThreshold: 1
```

### 3. Startup Probe（启动探针）

**作用**：判断应用是否已完成启动，用于慢启动应用。

**适用场景**：
- 应用启动时间较长
- 避免 Liveness Probe 过早杀死正在启动的容器

```yaml
startupProbe:
  httpGet:
    path: /healthz
    port: 8080
  failureThreshold: 30
  periodSeconds: 10
```

### 探针参数详解

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `initialDelaySeconds` | 容器启动后等待多久开始检查 | 0 |
| `periodSeconds` | 检查间隔时间 | 10 |
| `timeoutSeconds` | 检查超时时间 | 1 |
| `failureThreshold` | 失败多少次判定为失败 | 3 |
| `successThreshold` | 成功多少次判定为成功 | 1 |

### 检查方式

#### httpGet

通过 HTTP GET 请求检查：

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
    scheme: HTTP  # 或 HTTPS
    host: 127.0.0.1  # 可选，默认为 Pod IP
    httpHeaders:
    - name: X-Custom-Header
      value: health-check
```

#### tcpSocket

通过 TCP 端口连接检查：

```yaml
livenessProbe:
  tcpSocket:
    port: 3306  # 检查 MySQL 端口
```

#### exec

在容器内执行命令检查：

```yaml
livenessProbe:
  exec:
    command:
    - cat
    - /tmp/healthy
```

#### gRPC（Kubernetes 1.24+）

通过 gRPC 健康检查：

```yaml
livenessProbe:
  grpc:
    port: 50051
    service: "myapp.Health"
```

---

## 应用端点实现

### Node.js / Express

```javascript
const express = require('express');
const app = express();

// 基础健康检查
app.get('/healthz', (req, res) => {
  res.status(200).json({ 
    status: 'healthy',
    timestamp: new Date().toISOString()
  });
});

// 详细健康检查（包含依赖检查）
app.get('/health', async (req, res) => {
  try {
    const checks = {
      database: await checkDatabase(),
      cache: await checkCache(),
      externalApi: await checkExternalApi()
    };
    
    const allHealthy = Object.values(checks).every(c => c.status === 'healthy');
    res.status(allHealthy ? 200 : 503).json({
      status: allHealthy ? 'healthy' : 'unhealthy',
      checks
    });
  } catch (error) {
    res.status(503).json({ status: 'unhealthy', error: error.message });
  }
});

app.listen(8080);
```

### Python / Flask

```python
from flask import Flask, jsonify
import datetime

app = Flask(__name__)

@app.route('/healthz')
def health():
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.datetime.utcnow().isoformat()
    }), 200

@app.route('/ready')
def ready():
    # 检查依赖服务
    if not is_database_ready():
        return jsonify({'status': 'not ready'}), 503
    return jsonify({'status': 'ready'}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

### Go

```go
package main

import (
    "encoding/json"
    "net/http"
    "time"
)

type HealthStatus struct {
    Status    string    `json:"status"`
    Timestamp time.Time `json:"timestamp"`
}

func main() {
    http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Content-Type", "application/json")
        w.WriteHeader(http.StatusOK)
        json.NewEncoder(w).Encode(HealthStatus{
            Status:    "healthy",
            Timestamp: time.Now(),
        })
    })
    
    http.ListenAndServe(":8080", nil)
}
```

### Spring Boot (Java)

```java
import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.http.ResponseEntity;
import java.util.HashMap;
import java.util.Map;

@RestController
public class HealthController {

    @GetMapping("/healthz")
    public ResponseEntity<Map<String, Object>> health() {
        Map<String, Object> response = new HashMap<>();
        response.put("status", "healthy");
        response.put("timestamp", System.currentTimeMillis());
        return ResponseEntity.ok(response);
    }
    
    @GetMapping("/ready")
    public ResponseEntity<Map<String, Object>> ready() {
        // 检查依赖
        if (!isDependencyAvailable()) {
            return ResponseEntity.status(503).build();
        }
        return ResponseEntity.ok(Map.of("status", "ready"));
    }
}
```

---

## 配置示例

### 完整的 Deployment 配置

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  labels:
    app: my-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: my-app:latest
        ports:
        - containerPort: 8080
          name: http
        # Liveness Probe
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 15
          periodSeconds: 10
          timeoutSeconds: 1
          failureThreshold: 3
          successThreshold: 1
        # Readiness Probe
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 1
          failureThreshold: 3
          successThreshold: 1
        # Startup Probe（用于慢启动应用）
        startupProbe:
          httpGet:
            path: /healthz
            port: 8080
          failureThreshold: 30
          periodSeconds: 10
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
```

### Helm Chart values.yaml 配置

```yaml
# values.yaml
healthCheck:
  enabled: true
  liveness:
    path: /healthz
    port: 8080
    initialDelaySeconds: 15
    periodSeconds: 10
    timeoutSeconds: 1
    failureThreshold: 3
  readiness:
    path: /ready
    port: 8080
    initialDelaySeconds: 5
    periodSeconds: 5
    timeoutSeconds: 1
    failureThreshold: 3
```

### Helm Template 配置

```yaml
# templates/deployment.yaml
{{- if .Values.healthCheck.enabled }}
livenessProbe:
  httpGet:
    path: {{ .Values.healthCheck.liveness.path }}
    port: {{ .Values.healthCheck.liveness.port }}
  initialDelaySeconds: {{ .Values.healthCheck.liveness.initialDelaySeconds }}
  periodSeconds: {{ .Values.healthCheck.liveness.periodSeconds }}
  timeoutSeconds: {{ .Values.healthCheck.liveness.timeoutSeconds }}
  failureThreshold: {{ .Values.healthCheck.liveness.failureThreshold }}
readinessProbe:
  httpGet:
    path: {{ .Values.healthCheck.readiness.path }}
    port: {{ .Values.healthCheck.readiness.port }}
  initialDelaySeconds: {{ .Values.healthCheck.readiness.initialDelaySeconds }}
  periodSeconds: {{ .Values.healthCheck.readiness.periodSeconds }}
  timeoutSeconds: {{ .Values.healthCheck.readiness.timeoutSeconds }}
  failureThreshold: {{ .Values.healthCheck.readiness.failureThreshold }}
{{- end }}
```

---

## 测试方法

### 在容器内测试

```bash
# 进入容器
kubectl exec -it <pod-name> -- /bin/sh

# 使用 curl 测试
curl -v http://localhost:8080/healthz

# 使用 wget 测试
wget -O - http://localhost:8080/healthz

# 测试 Readiness 端点
curl http://localhost:8080/ready
```

### 从外部测试

```bash
# 端口转发
kubectl port-forward <pod-name> 8080:8080

# 在新终端访问
curl http://localhost:8080/healthz
```

### 查看探针状态

```bash
# 查看 Pod 详细信息，包括探针状态
kubectl describe pod <pod-name>

# 查看 Pod 状态（JSON 格式）
kubectl get pod <pod-name> -o json | jq '.status.conditions'

# 查看 Liveness 和 Readiness 状态
kubectl get pod <pod-name> -o jsonpath='{.status.containerStatuses[*].ready}'
```

### 模拟故障测试

```bash
# 创建一个会失败的端点（用于测试 Liveness）
kubectl exec -it <pod-name> -- sh -c 'echo "unhealthy" > /tmp/unhealthy'

# 观察 Pod 是否被重启
kubectl get pod <pod-name> -w
```

---

## 最佳实践

### 1. 区分 Liveness 和 Readiness

- **Liveness**：检查进程是否存活，应该简单快速
- **Readiness**：检查是否能处理请求，可以包含依赖检查

```yaml
livenessProbe:
  httpGet:
    path: /healthz  # 只检查进程
  failureThreshold: 3
  
readinessProbe:
  httpGet:
    path: /ready  # 检查所有依赖
  failureThreshold: 1  # 更敏感
```

### 2. 设置合理的超时和阈值

```yaml
# 推荐配置
livenessProbe:
  initialDelaySeconds: 15  # 给应用启动时间
  periodSeconds: 10        # 不要太频繁
  timeoutSeconds: 1        # 快速失败
  failureThreshold: 3      # 容忍短暂故障
  
readinessProbe:
  periodSeconds: 5         # 更频繁检查
  failureThreshold: 1      # 快速从负载均衡移除
```

### 3. 使用 Startup Probe 保护慢启动

```yaml
startupProbe:
  httpGet:
    path: /healthz
    port: 8080
  failureThreshold: 30  # 允许 30 次失败
  periodSeconds: 10     # 每 10 秒一次 = 300 秒启动时间
```

### 4. 健康检查端点应轻量

```javascript
// 好的实践
app.get('/healthz', (req, res) => {
  res.status(200).send('ok');
});

// 避免在 Liveness 中做复杂检查
// app.get('/healthz', async (req, res) => {
//   await checkDatabase();  // 不要在这里做
//   await checkCache();
//   await checkExternalAPIs();
// });
```

### 5. 添加健康检查指标

```yaml
# 在 Service Monitor 中添加健康检查指标
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
spec:
  endpoints:
  - port: http
    path: /healthz
    interval: 30s
```

---

## 常见问题排查

### Pod 不断重启

```bash
# 查看重启原因
kubectl describe pod <pod-name> | grep -A 5 "Liveness"

# 查看事件日志
kubectl get events --field-selector involvedObject.name=<pod-name>
```

### Pod 无法就绪

```bash
# 查看 Readiness 状态
kubectl describe pod <pod-name> | grep -A 5 "Readiness"

# 测试端点
kubectl exec <pod-name> -- curl -s localhost:8080/ready
```

### 健康检查超时

```bash
# 增加超时时间
timeoutSeconds: 5

# 检查应用响应时间
kubectl exec <pod-name> -- time curl localhost:8080/healthz
```

---

## 参考资源

- [Kubernetes Liveness Probe 官方文档](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [Docker HEALTHCHECK 官方文档](https://docs.docker.com/engine/reference/builder/#healthcheck)
- [容器健康检查最佳实践](https://kubernetes.io/blog/2018/10/01/health-checking-grpc-servers-on-kubernetes/)