output "compartment_ocid" {
  description = "OCID of the project compartment (name = var.project_name, default cloud-store)"
  value       = oci_identity_compartment.main.id
}

output "container_instance_ocid" {
  description = "OCID of the container instance — save as CLOUD_STORE_OCID in ~/.zshrc"
  value       = oci_container_instances_container_instance.main.id
}

output "app_url" {
  description = "Public URL to reach the shopping cart app"
  value       = "http://${data.oci_core_vnic.main.public_ip_address}:${var.app_port}"
}

output "ocir_image_path" {
  description = "Full OCIR image path — use for docker tag and docker push"
  value       = local.image_path
}

output "ords_base_url" {
  description = "ORDS base URL — set as ORDS_BASE_URL in .env"
  value       = local.ords_base_url
}

output "adb_ocid" {
  description = "OCID of the Autonomous Database"
  value       = oci_database_autonomous_database.main.id
}

output "vcn_ocid" {
  description = "OCID of the VCN"
  value       = oci_core_vcn.main.id
}
