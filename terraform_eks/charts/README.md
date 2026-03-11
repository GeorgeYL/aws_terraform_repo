# Local Helm Charts

Place the following chart packages in this folder for offline deployment:

- ingress-nginx-4.12.1.tgz
- kube-prometheus-stack-82.10.1.tgz

Then run:

terraform plan -out plan-local.tfplan
terraform apply "plan-local.tfplan"
