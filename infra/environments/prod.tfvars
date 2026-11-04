# Production values for the blue/green setup. Used with: terraform plan -var-file=environments/prod.tfvars
#
# This file records the state of production. It is not loaded automatically (Terraform only
# loads terraform.tfvars on its own), so every run names it explicitly.
#
# Blue is live today on the image that is running now. Green is a copy of it with no servers.
# A release goes to the environment that is NOT live (see infra/README.md, "Blue/green deploys").

live_color      = "blue"
blue_image_tag  = "d53882a1698dc1742de5b888bc3cd6ae3d5f7501"
green_image_tag = "d53882a1698dc1742de5b888bc3cd6ae3d5f7501"
blue_capacity   = 2
green_capacity  = 0

# Flags the deploy must always keep on. See the CI notes in infra/README.md.
etl_access_enabled = true
events_enabled     = true
