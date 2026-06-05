resource "oci_identity_compartment" "main" {
  compartment_id = var.tenancy_ocid
  name           = var.project_name
  description    = "All resources for the ${var.project_name} project"
  enable_delete  = true

  freeform_tags = { project = var.project_name }

  # Single long-lived compartment (default name: cloud-store via var.project_name).
  # terraform destroy removes workloads only; this resource is not destroyed here.
  # To remove the compartment itself, use the OCI console — repo scripts never
  # remove oci_identity_compartment from state or call delete on it.
  #
  # If apply fails after OCI drift: fix state for *workloads* only with
  # scripts/oci/terraform-recover-workload-state.sh (never drops the compartment).
  lifecycle {
    prevent_destroy = true
  }
}
