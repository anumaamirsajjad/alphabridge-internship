# Production values for the blue/green setup. Used with: terraform plan -var-file=environments/prod.tfvars
#
# This file records the state of production. It is not loaded automatically (Terraform only
# loads terraform.tfvars on its own), so every run names it explicitly.
#
# Green is live (cut over 2026-11-05). Blue is switched off (0 servers) and can be started again by setting blue_capacity.
# A release goes to the environment that is NOT live (see infra/README.md, "Blue/green deploys").

live_color      = "green"
blue_image_tag  = "d53882a1698dc1742de5b888bc3cd6ae3d5f7501"
green_image_tag = "07c5a5d4b357d7350729d1cec17449530b524b0f"
blue_capacity   = 0
green_capacity  = 2

# Flags the deploy must always keep on. See the CI notes in infra/README.md.
etl_access_enabled = true
events_enabled     = true
