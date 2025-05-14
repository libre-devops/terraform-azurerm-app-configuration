output "app_configuration_ids" {
  description = "The IDs of the App Configuration stores"
  value       = { for k, v in azurerm_app_configuration.this : k => v.id }
}

output "app_configuration_endpoints" {
  description = "The endpoints of the App Configuration stores"
  value       = { for k, v in azurerm_app_configuration.this : k => v.endpoint }
}

output "app_configuration_primary_read_keys" {
  description = "The primary read keys for the App Configuration stores"
  value       = { for k, v in azurerm_app_configuration.this : k => v.primary_read_key }
  sensitive   = true
}

output "app_configuration_primary_write_keys" {
  description = "The primary write keys for the App Configuration stores"
  value       = { for k, v in azurerm_app_configuration.this : k => v.primary_write_key }
  sensitive   = true
}

output "app_configuration_secondary_read_keys" {
  description = "The secondary read keys for the App Configuration stores"
  value       = { for k, v in azurerm_app_configuration.this : k => v.secondary_read_key }
  sensitive   = true
}

output "app_configuration_secondary_write_keys" {
  description = "The secondary write keys for the App Configuration stores"
  value       = { for k, v in azurerm_app_configuration.this : k => v.secondary_write_key }
  sensitive   = true
}

output "app_configuration_identities" {
  description = "The managed identities associated with the App Configuration stores"
  value       = { for k, v in azurerm_app_configuration.this : k => v.identity }
}

output "app_configuration_features" {
  description = "The features created in the App Configuration stores"
  value       = { for k, v in azurerm_app_configuration_feature.this : k => {
    id                     = v.id
    name                   = v.name
    key                    = v.key
    configuration_store_id = v.configuration_store_id
    enabled                = v.enabled
    locked                 = v.locked
    etag                   = v.etag
  }}
}

output "app_configuration_key_values" {
  description = "The key-value pairs created in the App Configuration stores"
  value       = { for k, v in azurerm_app_configuration_key.key_value_pairs : k => {
    id                     = v.id
    key                    = v.key
    configuration_store_id = v.configuration_store_id
    label                  = v.label
    content_type           = v.content_type
    type                   = v.type
    locked                 = v.locked
    etag                   = v.etag
  }}
}

output "app_configuration_secret_key_values" {
  description = "The secret key-value pairs created in the App Configuration stores"
  value       = { for k, v in azurerm_app_configuration_key.secret_key_value_pairs : k => {
    id                     = v.id
    key                    = v.key
    configuration_store_id = v.configuration_store_id
    label                  = v.label
    content_type           = v.content_type
    type                   = v.type
    locked                 = v.locked
    etag                   = v.etag
  }}
}

output "app_configuration_role_assignments" {
  description = "The role assignments created for App Configuration stores"
  value       = { for k, v in azurerm_role_assignment.app_config_data_owner : k => {
    id                   = v.id
    principal_id         = v.principal_id
    scope                = v.scope
    role_definition_name = v.role_definition_name
  }}
}

output "private_endpoint_ids" {
  description = "The IDs of the Private Endpoints created for each App Configuration store"
  value       = { for k, v in azurerm_private_endpoint.this : k => v.id }
}

output "private_endpoint_network_interface_ids" {
  description = "The network interface IDs attached to each Private Endpoint"
  value       = { for k, v in azurerm_private_endpoint.this : k => v.network_interface }
}

output "application_security_group_ids" {
  description = "The IDs of the Application Security Groups created for Private Endpoints"
  value       = { for k, v in azurerm_application_security_group.pep_asg : k => v.id }
}

output "private_endpoint_asg_association_ids" {
  description = "The IDs of the Private Endpoint ↔ ASG association resources"
  value       = { for k, v in azurerm_private_endpoint_application_security_group_association.pep_asg_association : k => v.id }
}
