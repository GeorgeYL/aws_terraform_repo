# devops_IaC
DevOps Infrastructure

## Stacks

- `terraform_aws/`: EC2 Auto Scaling stack
- `terraform_backend/`: S3 + DynamoDB backend bootstrap
- `terraform_eks/`: EKS + managed Linux nodes + Prometheus public endpoint

## Runbook

- Terraform AWS runbook timeline: `terraform_aws/README.md`
- Terraform backend lock runbook timeline: `terraform_backend/README.md`

然后访问：

http://<LB_DNS>/prometheus
http://<LB_DNS>/grafana
会先弹出 Basic Auth（默认 admin/admin）。

登录后，选择 Prometheus 或者 Grafana 对应的 Dashboard 即可。