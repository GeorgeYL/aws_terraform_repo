# Terraform Backend Bootstrap (S3 + DynamoDB)

This folder bootstraps Terraform backend resources used by other stacks:

- S3 bucket for remote state
- DynamoDB table for state lock (`LockID` string hash key)

## Usage

```bash
cd terraform_backend
terraform init
terraform apply
```

After apply succeeds, configure stack backends to use:

- `bucket = "george-terraform-state-bucket"`
- `dynamodb_table = "terraform-state-lock"`
- `region = "eu-north-1"`

Then reconfigure any stack using this backend:

```bash
cd ../terraform_aws
terraform init -reconfigure
terraform plan
```

## Notes

- Do not destroy this backend while other Terraform stacks still use it.
- If you already have a lock table with wrong schema (for example `lockID`), use a new table name instead of reusing it.

## Troubleshooting

### Error: `Error acquiring the state lock`

If you see errors like:

```text
ValidationException: Missing the key lockID in the item
ValidationException: The provided key element does not match the schema
```

your DynamoDB table schema is incompatible with Terraform state locking.

Required lock table schema:

- Partition key name: `LockID` (exact case-sensitive)
- Partition key type: `S` (String)

After correcting/recreating the table, run:

```bash
cd ../terraform_aws
terraform init -reconfigure
terraform plan
```

Execution logs (excerpt):

```text
# Before fix
Error acquiring the state lock
ValidationException: Missing the key lockID in the item
ValidationException: The provided key element does not match the schema

# After fix
Successfully configured the backend "s3"!
Acquiring state lock. This may take a few moments...
Plan: 30 to add, 0 to change, 0 to destroy.
Releasing state lock. This may take a few moments...
```

## Runbook Timeline

| Stage | Command | Symptom | Action | Result |
|------|------|------|------|------|
| Initial backend usage | `terraform init` + `terraform plan` (in `terraform_aws`) | `Error acquiring the state lock` with `Missing the key lockID in the item` | Investigated lock table schema in DynamoDB | Confirmed key-name mismatch |
| Backend correction | `terraform apply` (in `terraform_backend`) | Existing table had incompatible hash key casing | Recreated/managed lock table with `hash_key = "LockID"` and `type = "S"` | Lock schema aligned with Terraform backend requirements |
| Consumer stack reconfigure | `terraform init -reconfigure` + `terraform plan` (in `terraform_aws`) | Previous lock failures expected | Reinitialized backend to pick corrected lock table | Plan succeeded and lock was acquired/released normally |
