###############################################################################
# Locals
###############################################################################

locals {
  # ---------------------------------------------------------------------------
  # Build a single map of every Private Endpoint definition across every
  #   element in var.app_configurations.
  #
  #   • The INNER loop iterates over each PE in an app’s `private_endpoints`
  #     list (or an empty list if it’s null).
  #   • The OUTER loop iterates over every app in the variable.
  #   • The `if app.create_private_endpoints` clause skips apps that have PE
  #     creation disabled.
  #   • `flatten()` squashes the two-level nested lists into one flat list.
  #   • The final `for … : "${v.app_index}_${v.pe_index}" => v` comprehension
  #     converts that list into a map whose key uniquely identifies the PE
  #     (“<app_index>_<pe_index>”).
  # ---------------------------------------------------------------------------
  private_endpoints = {
    for v in flatten([
      for app_index, app in var.app_configurations : [
        for pe_index, pe in(
          app.private_endpoints != null ? app.private_endpoints : []
          ) : {
          app_index = app_index # which app we’re on
          pe_index  = pe_index  # position within that app’s list
          app       = app       # full app object (handy later)
          pe        = pe        # the PE definition itself
        } if app.create_private_endpoints
      ]
    ]) : "${v.app_index}_${v.pe_index}" => v
  }

  # ---------------------------------------------------------------------------
  # For every app decide *which* principal IDs we’ll assign the “Data Owner”
  # role to:
  #   • If the caller supplied a non-empty list
  #       → use it as-is.
  #   • Otherwise
  #       → default to a single-item list containing Terraform’s own
  #         service-principal objectId (`data.azurerm_client_config.current`).
  #
  # `coalesce(attr, [])` converts `null` → `[]`, so the succeeding `length()`
  # never crashes with a null value.
  # ---------------------------------------------------------------------------
  app_config_principal_lists = {
    for app_index, app in var.app_configurations :
    app_index => (
      length(coalesce(app.object_ids_to_assign_app_config_data_owner_role_to, [])) > 0
      ? app.object_ids_to_assign_app_config_data_owner_role_to # caller-supplied list
      : [data.azurerm_client_config.current.object_id]         # fallback to self
    )
  }

  # ---------------------------------------------------------------------------
  # Flatten the *map of lists* produced above into ONE map that’s perfect for
  # `for_each`:
  #
  #   • The inner comprehension produces a small map for each principal
  #     (`"${app_index}_${principal_index}"` is the key).
  #   • The outer comprehension wraps those small maps in a list.
  #   • `merge([ … ]...)` uses the splat-operator (`...`) to pass the list’s
  #     elements as separate arguments to `merge()`, stitching them together
  #     into a single flat map.
  # ---------------------------------------------------------------------------
  role_assignment_instances = merge([
    for app_index, principal_list in local.app_config_principal_lists : {
      for principal_index, pid in principal_list :
      "${app_index}_${principal_index}" => {
        app_index    = app_index # which app this belongs to
        principal_id = pid       # objectId that will receive the role
      }
    }
  ]...)
}
