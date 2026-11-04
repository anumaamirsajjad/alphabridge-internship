# Infrastructure (Terraform)

This folder describes every AWS resource the project uses. Changes are made here, through
Terraform, never in the AWS console.

## One-time setup (the only manual step)

Terraform stores its record of the resources in an S3 bucket, and locks it with a lock file in the same bucket.
Create the bucket once, in `ap-south-1`:

1. **S3:** create a bucket named `alphabridge-tfstate-169774886945`. Turn on **Versioning** and **Default encryption**. Block all public access.

The DynamoDB table created earlier is no longer used, and it can be deleted during cleanup.

## Commands

Run these from the `infra` folder, with credentials for the Terraform identity (see the open question in the project notes).
Always pass the values file, so the live state is read from `environments/prod.tfvars`:

```powershell
cd "C:\Users\MTS\OneDrive\Desktop\transaction feature\infra"
terraform init            # downloads the AWS provider and connects to the state
terraform fmt -check      # checks the formatting
terraform validate        # checks the configuration
terraform plan -var-file=environments/prod.tfvars -var "etl_access_enabled=true" -var "events_enabled=true"   # shows what would change, changes nothing
terraform apply -var-file=environments/prod.tfvars -var "etl_access_enabled=true" -var "events_enabled=true"  # makes the changes
terraform destroy         # removes everything, used at cleanup
```

The two flags `etl_access_enabled` and `events_enabled` must be passed on every plan and apply. Leaving them out
removes the ETL database rule or turns off event sending.

## Blue/green deploys

There are two complete app environments, `blue` and `green`. Only the one named in `live_color` takes customer
traffic. A release is started on the other one (the "idle" one), tested on the real load balancer, and then
switched to. A rollback is switching back.

What the pieces are:

- `environments/prod.tfvars`: the committed record of the live state. It says which color is live, which image
  each color runs, and how many servers each has.
- Each color has its own launch template, auto scaling group, and target group (`compute.tf`, `alb.tf`).
- The load balancer listener forwards customers to the target group of `live_color` (`alb.tf`).
- An optional test route (`candidate_test` rule) sends requests with the header `X-Deploy-Test: <secret>` to the idle color.

### Release flow

1. **Deploy to the idle color.** Merging to `main` runs the deploy job. It builds the image, runs the database
   migrations on the live servers, and starts the new image on the idle color with 2 servers. Customers are not affected.
2. **Check the idle color.** Confirm its servers are healthy in its target group, then run the smoke tests through the
   test route (below).
3. **Cut over.** Change `live_color` in `environments/prod.tfvars` to the idle color, and set that color's
   `*_image_tag` to the tested commit ID. Apply. The listener switches within seconds.
4. **Watch.** For 15 to 60 minutes, check the load balancer 5xx count and latency, the event count, and the DLQ alarm.
5. **Roll back if needed.** Change `live_color` back. The old color is still running, so this takes seconds.
6. **Retire the old color.** After the bake period (for example 24 hours), set its `*_capacity` to `0` and apply.

### Smoke test through the test route

Pick a value that is not committed. Pass it through an environment variable:

```powershell
$env:TF_VAR_deploy_test_header_value = "<random value>"
# then: curl -H "X-Deploy-Test: <random value>" https://<api>/prod/openapi.json   (expect 200)
```

Requests with the header reach the idle color, requests without it reach the live color. Turn the route off by
clearing the variable and applying.

### Important notes

- **The database is shared.** Old and new versions run against the same database while both are up. Migrations
  must stay additive (expand, then contract). The connection count doubles during overlap.
- **Events.** Both colors can send `transfer.created`. Each event has its own `event_id`, and the Athena view keeps one row per event.
- **Terraform values and CI.** The CI deploy uses the `*_image_tag` and `*_capacity` values for the idle color
  on the command line, so `environments/prod.tfvars` does not hold the new candidate's values until the cutover commit.
  Before a local plan, check the idle color's values in the file against what is running, or the plan will show
  a change to the idle color. The live color is never changed by a deploy.

## Rules

- Never change a resource in the AWS console. Change this code, then `plan` and `apply`.
- The pipeline runs `fmt` and `validate` on pull requests into `develop`, and deploys the idle color after merging to `main`.
- Cutover (changing `live_color`) is a manual change, applied by a person.
- Secrets are not stored here. The database password stays in Secrets Manager. The test header value is passed on the
  command line or in the environment, never committed.
