# Autonomous Database (ATP) — Always Free tier
#
# After `terraform apply`, get the ORDS URL from:
#   terraform output ords_base_url
# Then update your .env file and rebuild/push your Docker image.

resource "oci_database_autonomous_database" "main" {
  compartment_id           = oci_identity_compartment.main.id
  db_name                  = var.adb_db_name
  display_name             = "adb-${var.project_name}"
  db_workload              = "OLTP"  # ATP — Autonomous Transaction Processing
  is_free_tier             = true
  cpu_core_count           = 1
  data_storage_size_in_tbs = 1
  admin_password           = var.adb_admin_password
  is_auto_scaling_enabled  = false

  freeform_tags = { project = var.project_name }

  # Always Free ADB rejects in-place updates to OCPU/storage; ignore API drift.
  lifecycle {
    ignore_changes = [
      cpu_core_count,
      data_storage_size_in_tbs,
      is_auto_scaling_enabled,
    ]
  }
}
