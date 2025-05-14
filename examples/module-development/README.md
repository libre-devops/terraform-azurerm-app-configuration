```hcl
locals {
  rg_name         = "rg-${var.short}-${var.loc}-${var.env}-01"
  vnet_name       = "vnet-${var.short}-${var.loc}-${var.env}-01"
  dev_subnet_name = "DevSubnet"
  nsg_name        = "nsg-${var.short}-${var.loc}-${var.env}-01"
  key_vault_name  = "kv-${var.short}-${var.loc}-${var.env}-01"
  app_config_name = "app-config-${var.short}-${var.loc}-${var.env}-01"
}

module "rg" {
  source = "libre-devops/rg/azurerm"

  rg_name  = local.rg_name
  location = local.location
  tags     = local.tags
}

module "shared_vars" {
  source = "libre-devops/shared-vars/azurerm"
}

locals {
  lookup_cidr = {
    for landing_zone, envs in module.shared_vars.cidrs : landing_zone => {
      for env, cidr in envs : env => cidr
    }
  }
}

module "subnet_calculator" {
  source = "libre-devops/subnet-calculator/null"

  base_cidr = local.lookup_cidr[var.short][var.env][0]
  subnets = {
    (local.dev_subnet_name) = {
      mask_size = 26
      netnum    = 0
    }
  }
}

module "network" {
  source = "libre-devops/network/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  vnet_name          = local.vnet_name
  vnet_location      = module.rg.rg_location
  vnet_address_space = [module.subnet_calculator.base_cidr]

  subnets = {
    for i, name in module.subnet_calculator.subnet_names :
    name => {
      address_prefixes  = toset([module.subnet_calculator.subnet_ranges[i]])
      service_endpoints = name == local.dev_subnet_name ? ["Microsoft.KeyVault"] : []

      # Only assign delegation to subnet3
      delegation = []
    }
  }
}

module "client_ip" {
  source = "libre-devops/ip-address/external"
}

module "nsg" {
  source = "libre-devops/nsg/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  nsg_name              = local.nsg_name
  associate_with_subnet = true
  subnet_ids            = { for k, v in module.network.subnets_ids : k => v if k != "AzureBastionSubnet" }
  custom_nsg_rules = {
    "AllowVnetInbound" = {
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    }
    "AllowClientInbound" = {
      priority                   = 101
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = chomp(module.client_ip.public_ip_address)
      destination_address_prefix = "VirtualNetwork"
    }
  }
}


module "key_vault" {
  source = "../../../terraform-azurerm-keyvault"

  key_vaults = [
    {

      rg_name  = module.rg.rg_name
      location = module.rg.rg_location
      tags     = module.rg.rg_tags

      name                            = local.key_vault_name
      enabled_for_deployment          = true
      enabled_for_disk_encryption     = true
      enabled_for_template_deployment = true
      enable_rbac_authorization       = true
      purge_protection_enabled        = false
      public_network_access_enabled   = true
      network_acls = {
        default_action             = "Deny"
        bypass                     = "AzureServices"
        ip_rules                   = [chomp(module.client_ip.public_ip_address)]
        virtual_network_subnet_ids = [module.network.subnets_ids[local.dev_subnet_name]]
      }
    }
  ]
}

module "key_vault_secrets" {
  source = "../../../terraform-azurerm-key-vault-secrets"

  key_vault_id = module.key_vault.key_vault_ids[local.key_vault_name]

  key_vault_secrets = [
    {
      secret_name              = "example-password"
      generate_random_password = true
      content_type             = "text/plain"
      tags                     = module.rg.rg_tags
    },
  ]
}

module "role_assignments_key_vault" {
  source = "github.com/libre-devops/terraform-azurerm-role-assignment"

  role_assignments = [
    {
      principal_ids = [data.azurerm_client_config.current.object_id]
      role_names    = ["Key Vault Administrator"]
      scope         = module.key_vault.key_vault_ids[local.key_vault_name]
    },
  ]
}


module "private_dns_zones" {
  source = "github.com/libre-devops/terraform-azurerm-private-dns-zone"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  private_dns_zone_name = "privatelink.azconfig.io"

  create_private_dns_zone = true
  link_to_vnet            = true
  vnet_id                 = module.network.vnet_id
}

module "app_configuration" {
  source = "../../"

  depends_on = [module.private_dns_zones]

  app_configurations = [
    {
      rg_name  = module.rg.rg_name
      location = module.rg.rg_location
      tags     = module.rg.rg_tags

      name = local.app_config_name

      create_app_config_data_owner_role_assignment       = true
      object_ids_to_assign_app_config_data_owner_role_to = [data.azurerm_client_config.current.object_id]

      create_app_config_features = true
      features = [
        # A simple ON/OFF feature (enabled for all users)
        {
          name = "welcome-banner"
          # key       = "welcome-banner"            # <- omitted → defaults to name
          description = "Show the brand-new welcome banner"
          label       = "dev"
          enabled     = true # <- turn it on
          locked      = false
          tags = {
            owner = "platform-team"
            jira  = "WEB-123"
          }
        },

        # A percentage-rollout feature with targeting + time window
        {
          name                    = "new-checkout"
          key                     = "checkout/v2"
          description             = "Roll out the redesigned checkout flow"
          label                   = "dev"
          enabled                 = true
          locked                  = false
          percentage_filter_value = 25 # <- show to 25 % of users
          targeting_filter = {
            default_rollout_percentage = 0 # everyone else = 0 %
            groups = [
              {
                name               = "internal-testers"
                rollout_percentage = 100 # but 100 % for the tester group
              }
            ]
            users = [
              "user42", "user77" # always include these user IDs
            ]
          }
          timewindow_filter = {
            # Feature auto-starts now and expires in a month
            start = timeadd(timestamp(), "0h")
            end   = timeadd(timestamp(), "720h") # 30 days
          }
          tags = {
            owner = "checkout-team"
            jira  = "PAY-456"
          }
        }
      ]

      create_app_config_key_value_pairs = true
      key_value_pairs = [
        {
          key          = "myapp/settings/message"
          value        = "Hello, World!"
          label        = "dev"
          content_type = "text/plain"
        },
        {
          key   = "myapp/settings/background-color"
          value = "#FFFFFF"
          label = "dev"
        }
      ]
      create_app_config_secret_key_value_pairs = true
      secret_key_value_pairs = [
        {
          key   = "myapp/settings/api-key"
          value = module.key_vault_secrets.created_secrets["example-password"].versionless_id
        }
      ]

      create_private_endpoints = true
      private_endpoints = [
        {
          subnet_id = module.network.subnets_ids[local.dev_subnet_name]
          private_service_connection = {
            is_manual_connection = false
          }

          private_dns_zone_group = {
            name                 = module.private_dns_zones.dns_zone_name[0]
            private_dns_zone_ids = module.private_dns_zones.dns_zone_id
          }
        }
      ]
    }
  ]
}
```
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.28.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.28.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.7.2 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_app_configuration"></a> [app\_configuration](#module\_app\_configuration) | ../../ | n/a |
| <a name="module_client_ip"></a> [client\_ip](#module\_client\_ip) | libre-devops/ip-address/external | n/a |
| <a name="module_key_vault"></a> [key\_vault](#module\_key\_vault) | ../../../terraform-azurerm-keyvault | n/a |
| <a name="module_key_vault_secrets"></a> [key\_vault\_secrets](#module\_key\_vault\_secrets) | ../../../terraform-azurerm-key-vault-secrets | n/a |
| <a name="module_network"></a> [network](#module\_network) | libre-devops/network/azurerm | n/a |
| <a name="module_nsg"></a> [nsg](#module\_nsg) | libre-devops/nsg/azurerm | n/a |
| <a name="module_private_dns_zones"></a> [private\_dns\_zones](#module\_private\_dns\_zones) | github.com/libre-devops/terraform-azurerm-private-dns-zone | n/a |
| <a name="module_rg"></a> [rg](#module\_rg) | libre-devops/rg/azurerm | n/a |
| <a name="module_role_assignments_key_vault"></a> [role\_assignments\_key\_vault](#module\_role\_assignments\_key\_vault) | github.com/libre-devops/terraform-azurerm-role-assignment | n/a |
| <a name="module_shared_vars"></a> [shared\_vars](#module\_shared\_vars) | libre-devops/shared-vars/azurerm | n/a |
| <a name="module_subnet_calculator"></a> [subnet\_calculator](#module\_subnet\_calculator) | libre-devops/subnet-calculator/null | n/a |

## Resources

| Name | Type |
|------|------|
| [random_string.entropy](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_client_config.current_creds](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_key_vault.mgmt_kv](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/key_vault) | data source |
| [azurerm_resource_group.mgmt_rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/resource_group) | data source |
| [azurerm_ssh_public_key.mgmt_ssh_key](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/ssh_public_key) | data source |
| [azurerm_user_assigned_identity.mgmt_user_assigned_id](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/user_assigned_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_Regions"></a> [Regions](#input\_Regions) | Converts shorthand name to longhand name via lookup on map list | `map(string)` | <pre>{<br/>  "eus": "East US",<br/>  "euw": "West Europe",<br/>  "uks": "UK South",<br/>  "ukw": "UK West"<br/>}</pre> | no |
| <a name="input_env"></a> [env](#input\_env) | This is passed as an environment variable, it is for the shorthand environment tag for resource.  For example, production = prod | `string` | `"dev"` | no |
| <a name="input_loc"></a> [loc](#input\_loc) | The shorthand name of the Azure location, for example, for UK South, use uks.  For UK West, use ukw. Normally passed as TF\_VAR in pipeline | `string` | `"uks"` | no |
| <a name="input_name"></a> [name](#input\_name) | The name of this resource | `string` | `"tst"` | no |
| <a name="input_short"></a> [short](#input\_short) | This is passed as an environment variable, it is for a shorthand name for the environment, for example hello-world = hw | `string` | `"libd"` | no |
| <a name="input_static_tags"></a> [static\_tags](#input\_static\_tags) | The tags variable | `map(string)` | <pre>{<br/>  "Contact": "info@cyber.scot",<br/>  "CostCentre": "671888",<br/>  "ManagedBy": "Terraform"<br/>}</pre> | no |

## Outputs

No outputs.
