# Production values for the blue/green setup. Used with: terraform plan -var-file=environments/prod.tfvars
#
# This file records the state of production. It is not loaded automatically (Terraform only
# loads terraform.tfvars on its own), so every run names it explicitly.
#
# Green is live (cut over 2026-11-05). Blue is switched off (0 servers) and can be started again by setting blue_capacity.
# A release goes to the environment that is NOT live (see infra/README.md, "Blue/green deploys").

live_color      = "green"
blue_image_tag  = "5394708ccbfb4663eabf7b706bb0418f4bef91fd"
green_image_tag = "07c5a5d4b357d7350729d1cec17449530b524b0f"
blue_capacity   = 0
green_capacity  = 2

# Flags the deploy must always keep on. See the CI notes in infra/README.md.
etl_access_enabled = true
events_enabled     = true

# SRE alert email. Gets a subscription on the alphabridge-sre-alerts topic. AWS sends a confirmation
# email that must be accepted before alerts arrive. Kept here so every deploy keeps the subscription.
alerts_email = "jkfolics@gmail.com"
