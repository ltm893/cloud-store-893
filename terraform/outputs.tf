output "compartment_ocid" {
  description = "OCID of the project compartment (name = var.project_name, default cloud-store)"
  value       = oci_identity_compartment.main.id
}

output "container_instance_ocid" {
  description = "OCID of the container instance — save as CLOUD_STORE_OCID in ~/.zshrc"
  value       = oci_container_instances_container_instance.main.id
}

output "app_url" {
  description = "Direct HTTP URL on the container public IP (bypasses load balancer / tunnel)"
  value       = "http://${data.oci_core_vnic.main.public_ip_address}:${var.app_port}"
}

output "app_url_https" {
  description = "Public HTTPS URL when OCI LB or Cloudflare Tunnel hostname is configured (hostname only — does not imply TLS listener is up; check terraform plan for listener resources)"
  value = (
    var.enable_load_balancer && var.lb_public_hostname != ""
  ) ? "https://${var.lb_public_hostname}/" : (
    var.cloudflare_tunnel_hostname != "" ? "https://${var.cloudflare_tunnel_hostname}/" : null
  )
}

output "load_balancer_public_ip" {
  description = "Public IP on the flexible load balancer (point DNS here when LB is enabled)"
  value = var.enable_load_balancer ? one([
    for ip in oci_load_balancer_load_balancer.main[0].ip_address_details : ip.ip_address if ip.is_public
  ]) : null
}

output "cloudflare_tunnel_hostname" {
  description = "Public hostname served by Cloudflare Tunnel (empty when not configured)"
  value       = var.cloudflare_tunnel_hostname != "" ? var.cloudflare_tunnel_hostname : ""
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

output "cert_renew_function_ocid" {
  description = "OCID of the cert-renew OCI Function (empty when enable_cert_renew_function is false)"
  value       = var.enable_cert_renew_function ? oci_functions_function.cert_renew[0].id : null
}

output "cert_renew_function_image" {
  description = "OCIR image for cert-renew function — build and push before first apply"
  value       = local.cert_renew_image
}

output "certbot_state_bucket" {
  description = "Object Storage bucket for certbot state between function invocations"
  value       = var.enable_cert_renew_function ? var.certbot_state_bucket_name : null
}

output "cert_renew_schedule_ocid" {
  description = "OCID of the weekly cert-renew Resource Scheduler schedule (null when disabled)"
  value       = var.enable_cert_renew_function && var.enable_cert_renew_schedule ? oci_resource_scheduler_schedule.cert_renew[0].id : null
}

output "cert_renew_schedule_next_run" {
  description = "Next scheduled cert-renew invocation (UTC), when schedule is enabled"
  value       = var.enable_cert_renew_function && var.enable_cert_renew_schedule ? oci_resource_scheduler_schedule.cert_renew[0].time_next_run : null
}
