# EKS Monitoring Stack — Troubleshooting Guide

This document summarizes the issues encountered during deployment and their fixes.

---

## 1. `base64sha1` Function Does Not Exist

**Error:**
```
Error: Call to unknown function "base64sha1"
```

**Cause:** `base64sha1` is not a built-in Terraform function.

**Fix:** Use a pre-computed htpasswd string passed as a variable instead of computing it at plan time.

---

## 2. `string_data` Not Supported on `kubernetes_secret_v1`

**Error:**
```
Error: Unsupported argument "string_data"
```

**Cause:** The `kubernetes_secret_v1` resource uses `data`, not `string_data`.

**Fix:** Changed `string_data` to `data` in the secret resource block.

---

## 3. `data.aws_eks_cluster` Fails Before Cluster Exists

**Error:**
```
Error: reading EKS Cluster: couldn't find resource
```

**Cause:** `data.aws_eks_cluster.this` tries to read the cluster during plan, but the cluster doesn't exist yet on the first apply.

**Fix:** Added `depends_on = [module.eks]` to the data source so it waits for cluster creation.

---

## 4. `node_group_name` Attribute Not Found on EKS Module

**Error:**
```
Error: Unsupported attribute "node_group_name"
```

**Cause:** The EKS module output structure doesn't expose `node_group_name` directly.

**Fix:** Hardcoded the node group name `"linux-ng"` instead of referencing the module output.

---

## 5. `t3.medium` Not Free Tier Eligible — `CREATE_FAILED`

**Error:**
```
NodeCreationFailure: Instances failed to join the kubernetes cluster
```

**Cause:** `t3.medium` is not Free Tier eligible and may have capacity/quota issues.

**Fix:** Changed instance type to `t3.micro` in both `variables.tf` and `terraform.tfvars`.

---

## 6. Helm Chart Download Failures (Network Restricted)

**Error:**
```
Error: could not download chart: failed to fetch https://github.com/kubernetes/ingress-nginx/releases/download/...
```

**Cause:** Network restrictions prevent downloading Helm charts from GitHub/remote repos.

**Fix:** Implemented a local chart fallback system:
- Added `use_local_helm_charts` toggle variable
- Added variables for local chart paths (`ingress_nginx_local_chart_path`, `kube_prometheus_stack_local_chart_path`)
- Created `charts/` directory for storing `.tgz` chart archives
- Set `repository = null` when using local charts
- Manually downloaded charts and placed them in `charts/`

---

## 7. Helm Chart Version Mismatch

**Error:**
```
Error: chart "kube-prometheus-stack" matching 69.8.2 not found in ... index
```

**Cause:** Originally configured for version `69.8.2` but the manually downloaded chart was version `82.1.1`.

**Fix:** Synchronized the version across `variables.tf` defaults, `terraform.tfvars`, and chart filename references.

---

## 8. Helm Release `context deadline exceeded`

**Error:**
```
Error: context deadline exceeded
```

**Cause:** `kube-prometheus-stack` takes longer than the default 5-minute Helm timeout on small nodes.

**Fix:**
- Increased `timeout` to `1200` (20 minutes)
- Set `atomic = true` and `cleanup_on_fail = true`
- Reduced Prometheus/Grafana resource requests to fit on `t3.micro`
- Disabled alertmanager

---

## 9. EKS Auth Token Expiry During Long Operations

**Error:**
```
Error: Kubernetes cluster unreachable: the server has asked for the client to provide credentials
```

**Cause:** `data.aws_eks_cluster_auth` generates a static token at plan time that expires after ~15 minutes. Long-running Helm installs exceed this window.

**Fix:** Switched Kubernetes and Helm providers from static `token` auth to `exec`-based auth using AWS CLI:
```hcl
exec {
  api_version = "client.authentication.k8s.io/v1beta1"
  command     = "aws"
  args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
}
```
This fetches a fresh token on each API call.

**Prerequisite:** AWS CLI must be installed (`winget install Amazon.AWSCLI`).

---

## 10. `executable aws not found`

**Error:**
```
Error: exec: executable aws not found
```

**Cause:** AWS CLI was not installed on the Windows machine, required by the `exec`-based Kubernetes auth.

**Fix:** Installed AWS CLI via `winget install Amazon.AWSCLI`. After installation, PATH must be refreshed in existing terminal sessions:
```powershell
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
```

---

## 11. `cannot re-use a name that is still in use`

**Error:**
```
Error: cannot re-use a name that is still in use
```

**Cause:** A previous failed Helm install left orphaned release secrets in the cluster. The release name was taken but not tracked in Terraform state.

**Fix:**
1. Delete the stuck Helm release secret:
   ```bash
   kubectl delete secret sh.helm.release.v1.kube-prometheus-stack.v1 -n monitoring
   ```
2. Clean up leftover resources:
   ```bash
   kubectl delete all -n monitoring -l app.kubernetes.io/instance=kube-prometheus-stack --force --grace-period=0
   kubectl delete configmaps,secrets -n monitoring -l app.kubernetes.io/instance=kube-prometheus-stack
   kubectl delete mutatingwebhookconfigurations,validatingwebhookconfigurations -l app.kubernetes.io/instance=kube-prometheus-stack
   ```
3. Remove from Terraform state if needed:
   ```bash
   terraform state rm helm_release.kube_prometheus_stack
   ```

---

## 12. `another operation (install/upgrade/rollback) is in progress`

**Error:**
```
Error: another operation (install/upgrade/rollback) is in progress
```

**Cause:** Same root cause as #11 — a previous Helm operation left the release in a pending state.

**Fix:** Same cleanup as #11. Delete the Helm release secret and orphaned resources, then re-apply.

---

## 13. Pods Stuck in `Pending` — Too Many Pods per Node

**Error:**
```
Warning  FailedScheduling  0/2 nodes are available: 2 Too many pods.
```

**Cause:** `t3.micro` has 2 ENIs × 2 IPv4 addresses = **4 pods max per node**. With system pods (aws-node, kube-proxy, coredns) already consuming all slots, no capacity remains for monitoring workloads.

**Fix:**
1. Enable VPC CNI prefix delegation on the aws-node DaemonSet:
   ```bash
   kubectl set env daemonset aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true WARM_PREFIX_TARGET=1
   ```
2. The kubelet's `--max-pods` must also be raised. See issue #14 for the correct Terraform approach.
3. Nodes must be **replaced** (not just restarted) since `max-pods` is set at kubelet startup time.

---

## 14. `bootstrap_extra_args` Silently Ignored on EKS Managed Node Groups

**Symptom:**
After adding `bootstrap_extra_args` to the EKS managed node group config, `terraform plan` shows **0 to change** — the launch template and node group are not updated. Nodes continue running with the old `max-pods` limit.

```hcl
# THIS DOES NOT WORK for managed node groups using ami_type (no custom AMI)
bootstrap_extra_args = "--use-max-pods false --kubelet-extra-args '--max-pods=110'"
```

**Cause:** The `terraform-aws-modules/eks/aws` module's `bootstrap_extra_args` parameter is only used when you provide a **custom AMI** via `ami_id`. When using `ami_type` (e.g., `AL2_x86_64`), the EKS service manages the AMI and bootstrap process itself — `bootstrap_extra_args` is silently ignored.

**Fix Options:**

**Option A — Use a custom launch template with user data (AL2):**
Provide a custom AMI and use `bootstrap_extra_args`:
```hcl
eks_managed_node_groups = {
  linux = {
    ami_id         = data.aws_ami.eks_al2.id
    ami_type       = "AL2_x86_64"
    instance_types = ["t3.micro"]
    bootstrap_extra_args = "--use-max-pods false --kubelet-extra-args '--max-pods=110'"
  }
}
```
Note: Using a custom AMI means you must manage AMI updates yourself.

**Option B — Use AL2023 with nodeadm configuration:**
Switch to `AL2023` AMI type which uses `nodeadm` and supports `cloudinit_pre_nodeadm`:
```hcl
eks_managed_node_groups = {
  linux = {
    ami_type       = "AL2023_x86_64_STANDARD"
    instance_types = ["t3.micro"]
    cloudinit_pre_nodeadm = [
      {
        content_type = "application/node.eks.aws"
        content      = <<-EOT
          ---
          apiVersion: node.eks.aws/v1alpha1
          kind: NodeConfig
          spec:
            kubelet:
              config:
                maxPods: 110
        EOT
      }
    ]
  }
}
```

**Option C — Use `pre_bootstrap_user_data` with `ami_id` (AL2):**
```hcl
eks_managed_node_groups = {
  linux = {
    ami_id   = data.aws_ami.eks_al2.id
    ami_type = "AL2_x86_64"
    pre_bootstrap_user_data = <<-EOT
      #!/bin/bash
      # Set max-pods before bootstrap.sh runs
      echo "KUBELET_EXTRA_ARGS=--max-pods=110" >> /etc/environment
    EOT
    bootstrap_extra_args = "--use-max-pods false --kubelet-extra-args '--max-pods=110'"
  }
}
```

**Key takeaway:** Always verify with `terraform plan` that changes to node group configuration actually produce infrastructure updates. If the plan shows "0 to change" after modifying bootstrap args, the parameter is being ignored.

---

## 15. Kubernetes Provider Tries `http://localhost` During Plan

**Error:**
```
Error: Get "http://localhost/api/v1/namespaces/monitoring": dial tcp [::1]:80: connectex: No connection could be made because the target machine actively refused it.
```

**Symptom:**
`terraform plan` shows valid AWS/EKS changes (for example, node group replacement), but fails while refreshing Kubernetes resources such as `kubernetes_namespace.monitoring`.

**Cause:**
Terraform is trying to evaluate Kubernetes resources in the same run as EKS control-plane/node-group changes. In this state, the Kubernetes provider may fall back to an invalid local endpoint during refresh.

**Fix (staged apply):**
1. Apply EKS infrastructure changes first:
  ```bash
  terraform apply -target=module.eks -refresh=false -auto-approve
  ```
2. Wait for node group replacement to finish and nodes to become `Ready`.
3. Run a normal apply for Kubernetes and Helm resources:
  ```bash
  terraform apply -auto-approve
  ```

**Recommended long-term structure:**
Split infrastructure and Kubernetes workloads into separate root modules/stacks:
- Stack A: VPC + EKS
- Stack B: Kubernetes + Helm resources

This avoids provider bootstrapping races during cluster lifecycle updates.

---

## 16. `terraform init` Fails to Download Modules (GitHub Connection Reset)

**Error:**
```
Error: Failed to download module
fatal: unable to access 'https://github.com/terraform-aws-modules/...': Recv failure: Connection was reset
```

**Cause:**
Network path to GitHub is unstable/blocked during module install.

**Fix Options:**
1. Retry with a stable network/VPN and run:
   ```bash
   terraform init
   ```
2. Vendor modules locally and point `source` to local paths (offline-safe):
   ```hcl
   module "vpc" {
     source = "./modules/terraform-aws-vpc"
   }

   module "eks" {
     source = "./modules/terraform-aws-eks"
   }
   ```
3. Keep a tar/zip backup of a known-good `.terraform/modules` directory for restricted environments.

**Note:**
If `.terraform/modules/modules.json` is reset or incomplete, Terraform may report modules as "not installed" even when some module directories still exist.

---

## 17. Nodes Go `NotReady` Due to OOM on t3.micro

**Symptom:**
```
kubectl get nodes
NAME                                              STATUS     ROLES    AGE
ip-10-50-11-109.ap-southeast-1.compute.internal   NotReady   <none>   93m
```

Nodes show `NotReady` with taints like `node.kubernetes.io/unreachable:NoSchedule`.

**Cause:**
`t3.micro` has only **1GB RAM**. When running kube-prometheus-stack (Grafana, Prometheus, kube-state-metrics, node-exporter, operator), memory pressure causes the kubelet to become unresponsive, triggering the node to go `NotReady`.

The OOM condition is especially triggered during:
- Helm upgrades (multiple pods recreated simultaneously)
- Prometheus scraping spikes
- Grafana dashboard loading

**Diagnosis:**
```bash
kubectl describe node <node-name> | grep -A5 "Conditions:"
# Look for MemoryPressure: True
```

**Fix:**
Upgrade to `t3.small` (2GB RAM) or larger:

1. Update `terraform.tfvars`:
   ```hcl
   node_instance_types = ["t3.small"]
   ```

2. Clean up stuck Helm releases (if any):
   ```bash
   kubectl delete secrets -n monitoring -l owner=helm,name=kube-prometheus-stack
   kubectl delete all -n monitoring -l app.kubernetes.io/instance=kube-prometheus-stack --force --grace-period=0
   terraform state rm helm_release.kube_prometheus_stack
   ```

3. Apply staged (node group first):
   ```bash
   terraform apply -target=module.eks -auto-approve
   # Wait for new nodes to become Ready
   terraform apply -auto-approve
   ```

**Memory Requirements (approximate):**
| Component | Memory Request |
|-----------|---------------|
| Prometheus | 128Mi-512Mi |
| Grafana | 128Mi |
| kube-state-metrics | 32Mi |
| prometheus-operator | 128Mi |
| node-exporter | 32Mi per node |

**Recommendation:** Use `t3.small` (2GB) minimum for a monitoring stack.

---

## 18. Grafana `grafana.ini` Settings Not Applied via Helm `set`

**Symptom:**
Grafana returns 404 at `/grafana` even though `root_url` and `serve_from_sub_path` are configured in Helm values.

**Configuration that DOES NOT work:**
```hcl
set {
  name  = "grafana.grafana.ini.server.root_url"
  value = "http://example.com/grafana"
}
set {
  name  = "grafana.grafana.ini.server.serve_from_sub_path"
  value = "true"
}
```

**Cause:**
Helm's `--set` flag uses dots (`.`) as key separators. Keys like `grafana.ini` that contain literal dots must be **escaped** with backslashes. In Terraform HCL, backslashes must be doubled (`\\`).

**Fix — Escape dots in key names:**
```hcl
set {
  name  = "grafana.grafana\\.ini.server.root_url"
  value = "http://example.com/grafana"
}
set {
  name  = "grafana.grafana\\.ini.server.serve_from_sub_path"
  value = "true"
}
```

This tells Helm to treat `grafana.ini` as a single key, not as `grafana` → `ini`.

**Verification:**
After apply, check the ConfigMap:
```bash
kubectl get configmap kube-prometheus-stack-grafana -n monitoring -o yaml | grep -E "root_url|serve_from"
```
Should show:
```
root_url = http://example.com/grafana
serve_from_sub_path = true
```

---

## 19. Ingress Returns 502 Bad Gateway After Pod Recreation

**Symptom:**
```
HTTP/1.1 502 Bad Gateway
```

Accessing Grafana/Prometheus through the ingress returns 502 even though pods are Running.

**Nginx logs show:**
```
Service "monitoring/kube-prometheus-stack-grafana" does not have any active Endpoint.
```

**Cause:**
The NGINX Ingress Controller has a stale endpoint cache. This happens when:
1. Backend pods are deleted and recreated (e.g., during Helm upgrades)
2. Node replacement causes pods to be rescheduled
3. The ingress controller was running before the backend service existed

**Diagnosis:**
```bash
# Check endpoints exist
kubectl get endpoints kube-prometheus-stack-grafana -n monitoring
# Should show IP:PORT, not "<none>"

# Test from inside cluster
kubectl exec -n monitoring deploy/ingress-nginx-controller -- curl -s http://kube-prometheus-stack-grafana.monitoring.svc.cluster.local/grafana
# Should return 302 or 200
```

**Fix:**
Restart the ingress controller to refresh its endpoint cache:
```bash
kubectl rollout restart deployment/ingress-nginx-controller -n monitoring
```

Wait 15-30 seconds for the new pod to become ready, then test again.

**Prevention:**
Ensure ingress controller is deployed **after** backend services are ready. In Terraform, use `depends_on`:
```hcl
resource "kubernetes_ingress_v1" "monitoring" {
  depends_on = [helm_release.kube_prometheus_stack]
  # ...
}
```

---

## 20. AWS CLI Path Not Found in Exec Auth (Full Path Required)

**Symptom:**
```
Error: exec: executable aws not found
```

Even after installing AWS CLI, Terraform cannot find `aws` when using exec-based auth.

**Cause:**
On Windows, background processes or some terminal sessions may not have the updated PATH. The `aws` command is installed to `C:\Program Files\Amazon\AWSCLIV2\` which may not be in PATH.

**Fix:**
Use the full path to `aws.exe` in the provider exec configuration:
```hcl
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "C:/Program Files/Amazon/AWSCLIV2/aws.exe"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}
```

Note: Use forward slashes (`/`) in the path for cross-platform compatibility.

---

## General Tips

- **Background terminals reset PATH:** After installing CLI tools (e.g., AWS CLI), refresh PATH before running commands:
  ```powershell
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
  ```

- **Background terminals reset CWD:** Background terminals in VS Code start at the workspace root, not the Terraform project directory. Always `cd` first.

- **Stuck Helm releases:** If `terraform apply` fails mid-Helm-install, always check for orphaned release secrets before retrying:
  ```bash
  kubectl get secrets -n <namespace> -l owner=helm,name=<release-name>
  ```

- **Manual kubeconfig without AWS CLI:** If AWS CLI is unavailable, generate a temporary kubeconfig from Terraform state:
  ```powershell
  $state = terraform show -json | ConvertFrom-Json
  $cluster = $state.values.root_module.resources | Where-Object { $_.address -eq "data.aws_eks_cluster.this" } | Select-Object -ExpandProperty values
  $auth = $state.values.root_module.resources | Where-Object { $_.address -eq "data.aws_eks_cluster_auth.this" } | Select-Object -ExpandProperty values
  # Use $cluster.endpoint, $cluster.certificate_authority[0].data, and $auth.token
  ```
  Note: This token expires in ~15 minutes.
