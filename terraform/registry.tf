# OCI Container Registry repository
# is_public = true so the container instance can pull without an image pull secret
resource "oci_artifacts_container_repository" "main" {
  compartment_id = oci_identity_compartment.main.id
  display_name   = var.project_name
  is_public      = true

  freeform_tags = { project = var.project_name }
}
