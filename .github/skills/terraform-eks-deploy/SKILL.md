---
name: terraform-eks-deploy
description: 'Deploy and update the terraform_eks stack safely. Use when running terraform init/plan/apply, validating node groups and outputs, or handling common EKS deployment blockers.'
argument-hint: 'Goal: fresh deploy | update | validate-only'
user-invocable: true
---

# Terraform EKS Deploy

## What This Skill Produces
A repeatable checklist to deploy or update `terraform_eks/` with safety checks and clear stop conditions.

## When To Use
- Provision a new EKS environment from `terraform_eks/`.
- Apply incremental Terraform changes to the EKS stack.
- Validate stack health after plan/apply.

## Checklist Workflow
1. Confirm scope and state safety.
- Work only in `terraform_eks/`.
- Assume local state (`terraform.tfstate`) unless explicitly told to use a remote backend.
- If local state exists, take a timestamped backup before apply.
- If backend settings are present, pause and confirm whether to treat that run as remote-state mode.

2. Validate inputs before planning.
- Review `terraform_eks/terraform.tfvars` for environment-specific values.
- Ensure node group desired/min capacity is not below module constraints.
- Run Terraform formatting and validation checks.

3. Run deterministic plan.
- Run `terraform init` if providers/modules are not initialized.
- Run `terraform plan -out=plan.tfplan`.
- Stop if plan contains unexpected destructive changes.

4. Branch on plan result.
- If no changes: proceed to post-checks in step 6.
- If expected changes only: continue to apply.
- If unknown or risky changes: stop and request approval.

5. Apply safely.
- Run `terraform apply plan.tfplan`.
- Capture key outputs and any warnings.
- If apply fails, do not force re-apply until root cause is identified.

6. Post-apply validation.
- Confirm EKS control plane status is active.
- Confirm managed Linux node group desired/min values are healthy (default baseline is 2).
- Verify Terraform outputs are present and values are plausible for the target environment.
- Confirm Kubernetes nodes report `Ready`.
- Confirm Prometheus service exposure matches expected LoadBalancer/NLB behavior and endpoint reachability.
- If Argo CD is in scope for the environment, confirm Argo CD app health is `Healthy`/`Synced`.

## Completion Criteria
- Terraform plan is clean or applied with approved changes.
- No unresolved Terraform errors remain.
- Cluster and node group health checks pass.
- Service exposure checks pass for Prometheus.

## Escalation Rules
- Hard stop on any delete/replace action in plan unless explicit user approval is provided.
- Pause on provider/module drift that changes unrelated resources.
- Pause if state locking/backend configuration is unclear.

## Suggested Prompt Examples
- `/terraform-eks-deploy Goal: fresh deploy`
- `/terraform-eks-deploy Goal: update`
- `/terraform-eks-deploy Goal: validate-only`