variable "app_configurations" {
  description = "App Configuration list object"
  type = list(object({
    location                                         = optional(string, "uksouth")
    name                                             = string
    rg_name                                          = string
    sku                                              = optional(string, "standard")
    identity_type                                    = optional(string, "SystemAssigned")
    identity_ids                                     = optional(list(string))
    tags                                             = optional(map(string))
    local_auth_enabled                               = optional(bool, false)
    public_network_access_enabled                    = optional(bool, true)
    purge_protection_enabled                         = optional(bool, false)
    soft_delete_retention_days                       = optional(number)
    data_plane_proxy_authentication_mode             = optional(string, "Pass-through")
    data_plane_proxy_private_link_delegation_enabled = optional(bool, false)

    encryption = optional(object({
      identity_client_id       = optional(string)
      key_vault_key_identifier = optional(string)
    }))
    replica = optional(list(object({
      name     = string
      location = optional(string)
    })))
    create_app_config_data_owner_role_assignment       = optional(bool, true)
    object_ids_to_assign_app_config_data_owner_role_to = optional(list(string))

    create_app_config_features               = optional(bool, false)
    create_app_config_key_value_pairs        = optional(bool, false)
    create_app_config_secret_key_value_pairs = optional(bool, false)
    features = optional(list(object({
      name                    = string
      key                     = optional(string)
      value                   = optional(string)
      description             = optional(string)
      label                   = optional(string)
      enabled                 = optional(bool)
      locked                  = optional(bool)
      tags                    = optional(map(string))
      percentage_filter_value = optional(number)
      targeting_filter = optional(object({
        default_rollout_percentage = number
        groups = optional(list(object({
          name               = string
          rollout_percentage = number
        })))
        users = optional(list(string))
      }))
      timewindow_filter = optional(object({
        start = optional(string)
        end   = optional(string)
      }))
    })))
    key_value_pairs = optional(list(object({
      type         = optional(string, "kv")
      key          = string
      value        = optional(string)
      label        = optional(string)
      content_type = optional(string)
      enabled      = optional(bool)
      locked       = optional(bool)
      tags         = optional(map(string))
    })))
    secret_key_value_pairs = optional(list(object({
      type         = optional(string, "vault")
      key          = string
      value        = optional(string)
      label        = optional(string)
      content_type = optional(string)
      enabled      = optional(bool)
      locked       = optional(bool)
      tags         = optional(map(string))
    })))
    create_private_endpoints = optional(bool, false)
    private_endpoints = optional(list(object({
      private_endpoint_name         = optional(string, null)
      location                      = optional(string, null)
      rg_name                       = optional(string, null)
      subnet_id                     = string
      custom_network_interface_name = optional(string, null)
      tags                          = optional(map(string), {})
      create_asg                    = optional(bool, false)
      asg_name                      = optional(string)
      create_asg_association        = optional(bool, false)
      private_service_connection = optional(object({
        name                              = optional(string)
        is_manual_connection              = optional(bool)
        private_connection_resource_alias = optional(string)
        request_message                   = optional(string)
      }))
      private_dns_zone_group = optional(object({
        name                 = string
        private_dns_zone_ids = list(string)
      }))
      ip_configuration = optional(object({
        name               = optional(string)
        private_ip_address = optional(string)
        subresource_name   = optional(string)
        member_name        = optional(string)
      }))
    })))
  }))
}
