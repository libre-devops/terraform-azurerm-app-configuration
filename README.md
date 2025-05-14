```hcl
###############################################################################
# App Configuration stores
###############################################################################

resource "azurerm_app_configuration" "this" {
  for_each = { for index, value in var.app_configurations : index => merge(value, { index = index }) }

  name                                             = each.value.name
  resource_group_name                              = each.value.rg_name
  location                                         = each.value.location
  sku                                              = lower(each.value.sku)
  local_auth_enabled                               = each.value.local_auth_enabled
  public_network_access                            = each.value.public_network_access_enabled == true ? "Enabled" : "Disabled"
  purge_protection_enabled                         = each.value.purge_protection_enabled
  soft_delete_retention_days                       = each.value.soft_delete_retention_days
  tags                                             = each.value.tags
  data_plane_proxy_authentication_mode             = lower(each.value.data_plane_proxy_authentication_mode) == "pass-through" ? "Pass-through" : title(each.value.data_plane_proxy_authentication_mode)
  data_plane_proxy_private_link_delegation_enabled = each.value.data_plane_proxy_private_link_delegation_enabled

  dynamic "identity" {
    for_each = each.value.identity_type == "SystemAssigned" ? [each.value.identity_type] : []
    content {
      type = each.value.identity_type
    }
  }

  dynamic "identity" {
    for_each = each.value.identity_type == "SystemAssigned, UserAssigned" ? [each.value.identity_type] : []
    content {
      type         = each.value.identity_type
      identity_ids = try(each.value.identity_ids, [])
    }
  }

  dynamic "identity" {
    for_each = each.value.identity_type == "UserAssigned" ? [each.value.identity_type] : []
    content {
      type         = each.value.identity_type
      identity_ids = try(each.value.identity_ids, [])
    }
  }

  dynamic "encryption" {
    for_each = each.value.encryption != null ? [each.value.encryption] : []
    content {
      identity_client_id       = encryption.value.identity_client_id
      key_vault_key_identifier = encryption.value.key_vault_key_identifier
    }
  }

  dynamic "replica" {
    for_each = each.value.replica != null ? each.value.replica : []
    content {
      name     = replica.value.name
      location = replica.value.location
    }
  }
}

resource "azurerm_role_assignment" "app_config_data_owner" {
  for_each = local.role_assignment_instances

  principal_id         = each.value.principal_id
  scope                = azurerm_app_configuration.this[each.value.app_index].id
  role_definition_name = "App Configuration Data Owner"
}


###############################################################################
# Feature flags
###############################################################################

resource "azurerm_app_configuration_feature" "this" {
  # Always depend on the role‑assignment resource – even if no instances are
  # created, the address is still valid and keeps the graph simple.
  depends_on = [azurerm_role_assignment.app_config_data_owner]

  for_each = {
    for v in flatten([
      for app_index, app in var.app_configurations : [
        for feature_index, feature in(app.features != null ? app.features : []) : {
          app_index     = app_index
          feature_index = feature_index
          feature       = feature
        } if app.create_app_config_features
      ]
    ]) : "${v.app_index}_${v.feature_index}" => v
  }

  configuration_store_id  = azurerm_app_configuration.this[each.value.app_index].id
  name                    = each.value.feature.name
  key                     = coalesce(each.value.feature.key, each.value.feature.name)
  description             = each.value.feature.description
  label                   = each.value.feature.label
  enabled                 = each.value.feature.enabled
  locked                  = each.value.feature.locked
  tags                    = each.value.feature.tags
  percentage_filter_value = each.value.feature.percentage_filter_value

  dynamic "targeting_filter" {
    for_each = each.value.feature.targeting_filter != null ? [each.value.feature.targeting_filter] : []
    content {
      default_rollout_percentage = targeting_filter.value.default_rollout_percentage

      dynamic "groups" {
        for_each = targeting_filter.value.groups != null ? targeting_filter.value.groups : []
        content {
          name               = groups.value.name
          rollout_percentage = groups.value.rollout_percentage
        }
      }

      users = targeting_filter.value.users
    }
  }

  dynamic "timewindow_filter" {
    for_each = each.value.feature.timewindow_filter != null ? [each.value.feature.timewindow_filter] : []
    content {
      start = timewindow_filter.value.start
      end   = timewindow_filter.value.end
    }
  }
}

###############################################################################
# Key‑Value pairs (plain)
###############################################################################

resource "azurerm_app_configuration_key" "key_value_pairs" {
  depends_on = [azurerm_role_assignment.app_config_data_owner]

  for_each = {
    for v in flatten([
      for app_index, app in var.app_configurations : [
        for kv_index, kv in(app.key_value_pairs != null ? app.key_value_pairs : []) : {
          app_index = app_index
          kv_index  = kv_index
          kv        = kv
        } if app.create_app_config_key_value_pairs
      ]
    ]) : "${v.app_index}_${v.kv_index}" => v
  }

  configuration_store_id = azurerm_app_configuration.this[each.value.app_index].id
  key                    = each.value.kv.key
  value                  = each.value.kv.value
  label                  = each.value.kv.label
  content_type           = each.value.kv.content_type
  type                   = each.value.kv.type
  locked                 = each.value.kv.locked
  tags                   = each.value.kv.tags
}

###############################################################################
# Key‑Value pairs (secret)
###############################################################################

resource "azurerm_app_configuration_key" "secret_key_value_pairs" {
  depends_on = [azurerm_role_assignment.app_config_data_owner]

  for_each = {
    for v in flatten([
      for app_index, app in var.app_configurations : [
        for secret_index, secret in(app.secret_key_value_pairs != null ? app.secret_key_value_pairs : []) : {
          app_index    = app_index
          secret_index = secret_index
          secret       = secret
        } if app.create_app_config_secret_key_value_pairs
      ]
    ]) : "${v.app_index}_${v.secret_index}" => v
  }

  configuration_store_id = azurerm_app_configuration.this[each.value.app_index].id
  key                    = each.value.secret.key
  vault_key_reference    = each.value.secret.value
  label                  = each.value.secret.label
  content_type           = each.value.secret.content_type
  type                   = each.value.secret.type
  locked                 = each.value.secret.locked
  tags                   = each.value.secret.tags
}

###############################################################################
# Private Endpoints – driven by local.private_endpoints
###############################################################################

resource "azurerm_private_endpoint" "this" {
  for_each = local.private_endpoints

  depends_on = [azurerm_app_configuration_key.key_value_pairs, azurerm_app_configuration_key.secret_key_value_pairs, azurerm_app_configuration_feature.this]

  name                          = coalesce(each.value.pe.private_endpoint_name, "pe-${azurerm_app_configuration.this[each.value.app_index].name}")
  location                      = coalesce(each.value.pe.location, each.value.app.location)
  resource_group_name           = coalesce(each.value.pe.rg_name, each.value.app.rg_name)
  subnet_id                     = each.value.pe.subnet_id
  custom_network_interface_name = coalesce(each.value.pe.custom_network_interface_name, "pe-nic-${azurerm_app_configuration.this[each.value.app_index].name}")
  tags                          = each.value.app.tags

  dynamic "private_service_connection" {
    for_each = each.value.pe.private_service_connection != null ? [each.value.pe.private_service_connection] : []
    content {
      name                              = private_service_connection.value.name != null ? private_service_connection.value.name : "pvsvccon-pe-${each.value.app.name}"
      is_manual_connection              = private_service_connection.value.is_manual_connection
      private_connection_resource_id    = azurerm_app_configuration.this[each.value.app_index].id
      private_connection_resource_alias = private_service_connection.value.private_connection_resource_alias
      subresource_names                 = ["configurationStores"]
      request_message                   = private_service_connection.value.is_manual_connection == false ? null : private_service_connection.value.request_message != null ? private_service_connection.value.request_message : "Manual approval for pe-${each.value.app.name}"
    }
  }

  dynamic "private_dns_zone_group" {
    for_each = each.value.pe.private_dns_zone_group != null ? [each.value.pe.private_dns_zone_group] : []
    content {
      name                 = private_dns_zone_group.value.name
      private_dns_zone_ids = private_dns_zone_group.value.private_dns_zone_ids
    }
  }

  dynamic "ip_configuration" {
    for_each = each.value.pe.ip_configuration != null ? [each.value.pe.ip_configuration] : []
    content {
      name               = ip_configuration.value.name
      private_ip_address = ip_configuration.value.private_ip_address
      subresource_name   = ip_configuration.value.subresource_name
      member_name        = ip_configuration.value.member_name
    }
  }
}

###############################################################################
# Application Security Groups (optional per‑PE)
###############################################################################

resource "azurerm_application_security_group" "pep_asg" {
  for_each = {
    for k, v in local.private_endpoints : k => v if v.pe.create_asg
  }

  name                = coalesce(each.value.pe.asg_name, "asg-${each.value.pe.private_endpoint_name}")
  location            = azurerm_private_endpoint.this[each.key].location
  resource_group_name = azurerm_private_endpoint.this[each.key].resource_group_name
  tags                = azurerm_private_endpoint.this[each.key].tags
}

###############################################################################
# Association – ASG ↔ Private Endpoint (optional)
###############################################################################

resource "azurerm_private_endpoint_application_security_group_association" "pep_asg_association" {
  for_each = {
    for k, v in local.private_endpoints : k => v if v.pe.create_asg && v.pe.create_asg_association
  }

  private_endpoint_id           = azurerm_private_endpoint.this[each.key].id
  application_security_group_id = azurerm_application_security_group.pep_asg[each.key].id
}
```
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_app_configuration.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/app_configuration) | resource |
| [azurerm_app_configuration_feature.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/app_configuration_feature) | resource |
| [azurerm_app_configuration_key.key_value_pairs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/app_configuration_key) | resource |
| [azurerm_app_configuration_key.secret_key_value_pairs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/app_configuration_key) | resource |
| [azurerm_application_security_group.pep_asg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_security_group) | resource |
| [azurerm_private_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_private_endpoint_application_security_group_association.pep_asg_association](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint_application_security_group_association) | resource |
| [azurerm_role_assignment.app_config_data_owner](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_app_configurations"></a> [app\_configurations](#input\_app\_configurations) | App Configuration list object | <pre>list(object({<br/>    location                                         = optional(string, "uksouth")<br/>    name                                             = string<br/>    rg_name                                          = string<br/>    sku                                              = optional(string, "standard")<br/>    identity_type                                    = optional(string, "SystemAssigned")<br/>    identity_ids                                     = optional(list(string))<br/>    tags                                             = optional(map(string))<br/>    local_auth_enabled                               = optional(bool, false)<br/>    public_network_access_enabled                    = optional(bool, true)<br/>    purge_protection_enabled                         = optional(bool, false)<br/>    soft_delete_retention_days                       = optional(number)<br/>    data_plane_proxy_authentication_mode             = optional(string, "Pass-through")<br/>    data_plane_proxy_private_link_delegation_enabled = optional(bool, false)<br/><br/>    encryption = optional(object({<br/>      identity_client_id       = optional(string)<br/>      key_vault_key_identifier = optional(string)<br/>    }))<br/>    replica = optional(list(object({<br/>      name     = string<br/>      location = optional(string)<br/>    })))<br/>    create_app_config_data_owner_role_assignment       = optional(bool, true)<br/>    object_ids_to_assign_app_config_data_owner_role_to = optional(list(string))<br/><br/>    create_app_config_features               = optional(bool, false)<br/>    create_app_config_key_value_pairs        = optional(bool, false)<br/>    create_app_config_secret_key_value_pairs = optional(bool, false)<br/>    features = optional(list(object({<br/>      name                    = string<br/>      key                     = optional(string)<br/>      value                   = optional(string)<br/>      description             = optional(string)<br/>      label                   = optional(string)<br/>      enabled                 = optional(bool)<br/>      locked                  = optional(bool)<br/>      tags                    = optional(map(string))<br/>      percentage_filter_value = optional(number)<br/>      targeting_filter = optional(object({<br/>        default_rollout_percentage = number<br/>        groups = optional(list(object({<br/>          name               = string<br/>          rollout_percentage = number<br/>        })))<br/>        users = optional(list(string))<br/>      }))<br/>      timewindow_filter = optional(object({<br/>        start = optional(string)<br/>        end   = optional(string)<br/>      }))<br/>    })))<br/>    key_value_pairs = optional(list(object({<br/>      type         = optional(string, "kv")<br/>      key          = string<br/>      value        = optional(string)<br/>      label        = optional(string)<br/>      content_type = optional(string)<br/>      enabled      = optional(bool)<br/>      locked       = optional(bool)<br/>      tags         = optional(map(string))<br/>    })))<br/>    secret_key_value_pairs = optional(list(object({<br/>      type         = optional(string, "vault")<br/>      key          = string<br/>      value        = optional(string)<br/>      label        = optional(string)<br/>      content_type = optional(string)<br/>      enabled      = optional(bool)<br/>      locked       = optional(bool)<br/>      tags         = optional(map(string))<br/>    })))<br/>    create_private_endpoints = optional(bool, false)<br/>    private_endpoints = optional(list(object({<br/>      private_endpoint_name         = optional(string, null)<br/>      location                      = optional(string, null)<br/>      rg_name                       = optional(string, null)<br/>      subnet_id                     = string<br/>      custom_network_interface_name = optional(string, null)<br/>      tags                          = optional(map(string), {})<br/>      create_asg                    = optional(bool, false)<br/>      asg_name                      = optional(string)<br/>      create_asg_association        = optional(bool, false)<br/>      private_service_connection = optional(object({<br/>        name                              = optional(string)<br/>        is_manual_connection              = optional(bool)<br/>        private_connection_resource_alias = optional(string)<br/>        request_message                   = optional(string)<br/>      }))<br/>      private_dns_zone_group = optional(object({<br/>        name                 = string<br/>        private_dns_zone_ids = list(string)<br/>      }))<br/>      ip_configuration = optional(object({<br/>        name               = optional(string)<br/>        private_ip_address = optional(string)<br/>        subresource_name   = optional(string)<br/>        member_name        = optional(string)<br/>      }))<br/>    })))<br/>  }))</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_app_configuration_endpoints"></a> [app\_configuration\_endpoints](#output\_app\_configuration\_endpoints) | The endpoints of the App Configuration stores |
| <a name="output_app_configuration_features"></a> [app\_configuration\_features](#output\_app\_configuration\_features) | The features created in the App Configuration stores |
| <a name="output_app_configuration_identities"></a> [app\_configuration\_identities](#output\_app\_configuration\_identities) | The managed identities associated with the App Configuration stores |
| <a name="output_app_configuration_ids"></a> [app\_configuration\_ids](#output\_app\_configuration\_ids) | The IDs of the App Configuration stores |
| <a name="output_app_configuration_key_values"></a> [app\_configuration\_key\_values](#output\_app\_configuration\_key\_values) | The key-value pairs created in the App Configuration stores |
| <a name="output_app_configuration_primary_read_keys"></a> [app\_configuration\_primary\_read\_keys](#output\_app\_configuration\_primary\_read\_keys) | The primary read keys for the App Configuration stores |
| <a name="output_app_configuration_primary_write_keys"></a> [app\_configuration\_primary\_write\_keys](#output\_app\_configuration\_primary\_write\_keys) | The primary write keys for the App Configuration stores |
| <a name="output_app_configuration_role_assignments"></a> [app\_configuration\_role\_assignments](#output\_app\_configuration\_role\_assignments) | The role assignments created for App Configuration stores |
| <a name="output_app_configuration_secondary_read_keys"></a> [app\_configuration\_secondary\_read\_keys](#output\_app\_configuration\_secondary\_read\_keys) | The secondary read keys for the App Configuration stores |
| <a name="output_app_configuration_secondary_write_keys"></a> [app\_configuration\_secondary\_write\_keys](#output\_app\_configuration\_secondary\_write\_keys) | The secondary write keys for the App Configuration stores |
| <a name="output_app_configuration_secret_key_values"></a> [app\_configuration\_secret\_key\_values](#output\_app\_configuration\_secret\_key\_values) | The secret key-value pairs created in the App Configuration stores |
| <a name="output_application_security_group_ids"></a> [application\_security\_group\_ids](#output\_application\_security\_group\_ids) | The IDs of the Application Security Groups created for Private Endpoints |
| <a name="output_private_endpoint_asg_association_ids"></a> [private\_endpoint\_asg\_association\_ids](#output\_private\_endpoint\_asg\_association\_ids) | The IDs of the Private Endpoint Γåö ASG association resources |
| <a name="output_private_endpoint_ids"></a> [private\_endpoint\_ids](#output\_private\_endpoint\_ids) | The IDs of the Private Endpoints created for each App Configuration store |
| <a name="output_private_endpoint_network_interface_ids"></a> [private\_endpoint\_network\_interface\_ids](#output\_private\_endpoint\_network\_interface\_ids) | The network interface IDs attached to each Private Endpoint |
