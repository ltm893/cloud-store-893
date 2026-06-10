# ── Cert renewal OCI Function (Let's Encrypt → OCI Certificates) ───────────────
# Opt-in: enable_cert_renew_function = true
# See docs/oci-load-balancer-https.md § Function-driven renewal.

resource "oci_objectstorage_bucket" "certbot_state" {
  count = var.enable_cert_renew_function ? 1 : 0

  compartment_id = oci_identity_compartment.main.id
  namespace      = var.object_storage_namespace
  name           = var.certbot_state_bucket_name
  access_type    = "NoPublicAccess"

  freeform_tags = { project = var.project_name }
}

resource "oci_functions_application" "cert_renew" {
  count = var.enable_cert_renew_function ? 1 : 0

  compartment_id = oci_identity_compartment.main.id
  display_name   = "cert-renew-${var.project_name}"
  subnet_ids     = [oci_core_subnet.main.id]

  freeform_tags = { project = var.project_name }
}

resource "oci_functions_function" "cert_renew" {
  count = var.enable_cert_renew_function ? 1 : 0

  application_id = oci_functions_application.cert_renew[0].id
  display_name   = "cert-renew"
  image          = local.cert_renew_image
  memory_in_mbs  = var.cert_renew_memory_mbs
  timeout_in_seconds = var.cert_renew_timeout_seconds

  config = {
    CERT_HOSTNAME          = var.lb_public_hostname
    CERT_OCID              = var.lb_certificate_ocid
    CERTBOT_STATE_BUCKET   = var.certbot_state_bucket_name
    CERTBOT_STATE_OBJECT   = "certbot-state.tar.gz"
    CERTBOT_EMAIL          = var.cert_renew_email
    DNS_PROPAGATION_SECS   = tostring(var.cert_renew_dns_propagation_seconds)
  }

  freeform_tags = { project = var.project_name }
}

locals {
  cert_renew_image = "${var.ocir_region_key}.ocir.io/${var.object_storage_namespace}/${var.project_name}:${var.cert_renew_image_tag}"
}

# Dynamic group + policies (tenancy-level DG; policies in project compartment).
resource "oci_identity_dynamic_group" "cert_renew_fn" {
  count = var.enable_cert_renew_function ? 1 : 0

  compartment_id = var.tenancy_ocid
  name           = "${var.project_name}-cert-renew-fn"
  description    = "OCI Functions that renew Let's Encrypt certificates for ${var.project_name}"

  matching_rule = "ALL {resource.type = 'fnfunc', resource.compartment.id = '${oci_identity_compartment.main.id}'}"
}

resource "oci_identity_policy" "cert_renew_fn" {
  count = var.enable_cert_renew_function ? 1 : 0

  compartment_id = oci_identity_compartment.main.id
  name           = "${var.project_name}-cert-renew-fn"
  description    = "Allow cert-renew function resource principal to manage DNS, certs, and certbot state bucket"

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.cert_renew_fn[0].name} to read dns-zones in compartment id ${oci_identity_compartment.main.id}",
    "Allow dynamic-group ${oci_identity_dynamic_group.cert_renew_fn[0].name} to manage dns-records in compartment id ${oci_identity_compartment.main.id}",
    "Allow dynamic-group ${oci_identity_dynamic_group.cert_renew_fn[0].name} to manage leaf-certificate-family in compartment id ${oci_identity_compartment.main.id}",
    "Allow dynamic-group ${oci_identity_dynamic_group.cert_renew_fn[0].name} to manage objects in compartment id ${oci_identity_compartment.main.id} where target.bucket.name='${var.certbot_state_bucket_name}'",
  ]
}
