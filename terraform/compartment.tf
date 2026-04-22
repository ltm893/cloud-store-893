resource "oci_identity_compartment" "main" {
  compartment_id = var.tenancy_ocid
  name           = var.project_name
  description    = "All resources for the ${var.project_name} project"
  enable_delete  = true

  freeform_tags = { project = var.project_name }
}
