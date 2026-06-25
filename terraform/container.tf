# ── Availability Domain lookup ────────────────────────────────────────────────
data "oci_identity_availability_domains" "all" {
  compartment_id = var.tenancy_ocid
}

# ── VNIC lookup ───────────────────────────────────────────────────────────────
# The container instance returns a vnic_id after creation.
# We use this data source to get the public IP assigned to it.
data "oci_core_vnic" "main" {
  vnic_id = oci_container_instances_container_instance.main.vnics[0].vnic_id
}

# ── Locals ────────────────────────────────────────────────────────────────────
locals {
  ad_name       = data.oci_identity_availability_domains.all.availability_domains[0].name
  image_path    = "${var.ocir_region_key}.ocir.io/${var.object_storage_namespace}/${var.project_name}:${var.ocir_image_tag}"
  ords_base_url = "${oci_database_autonomous_database.main.connection_urls[0].ords_url}admin"

  optional_app_env = {
    for k, v in {
      CLOUDFLARE_TUNNEL_TOKEN              = var.cloudflare_tunnel_token
      APP_PUBLIC_URL                       = var.app_public_url
      IDP_POS_ISSUER                       = var.idp_pos_issuer
      IDP_POS_CLIENT_ID                    = var.idp_pos_client_id
      IDP_POS_CLIENT_SECRET                = var.idp_pos_client_secret
      IDP_ADMIN_ISSUER                     = var.idp_admin_issuer
      IDP_ADMIN_CLIENT_ID                  = var.idp_admin_client_id
      IDP_ADMIN_CLIENT_SECRET              = var.idp_admin_client_secret
      IDP_SUPERVISOR_GROUP                 = var.idp_supervisor_group
      IDP_POS_CASHIER_GROUP                = var.idp_pos_cashier_group
      CASHIER_APPROVAL_TTL_SEC             = var.cashier_supervisor_approval ? tostring(var.cashier_approval_ttl_sec) : ""
      OPENING_CASH_FLOAT                   = var.opening_cash_float
    } : k => v if v != null && v != ""
  }

  systems_container_env = {
    SYSTEMS_REPO_URL           = "https://github.com/ltm893/cloud-store-893"
    SYSTEMS_TLS_HOSTNAME       = var.lb_public_hostname != "" ? var.lb_public_hostname : ""
    SYSTEMS_COMPARTMENT_NAME   = var.project_name
    SYSTEMS_COMPARTMENT_OCID   = oci_identity_compartment.main.id
    # Container OCID omitted — referencing main.id here creates a Terraform cycle
    # (env vars are inputs to the same resource). Name is enough for /admin systems UI.
    SYSTEMS_CONTAINER_NAME       = "container-instance-${var.project_name}"
    SYSTEMS_ADB_OCID             = oci_database_autonomous_database.main.id
    SYSTEMS_ADB_NAME             = oci_database_autonomous_database.main.display_name
    SYSTEMS_VCN_OCID             = oci_core_vcn.main.id
    SYSTEMS_VCN_NAME             = oci_core_vcn.main.display_name
    SYSTEMS_OCI_REGION           = var.region
    SYSTEMS_LB_OCID = var.enable_load_balancer ? oci_load_balancer_load_balancer.main[0].id : ""
    SYSTEMS_LB_NAME = var.enable_load_balancer ? "lb-${var.project_name}" : ""
    SYSTEMS_LB_PUBLIC_IP = var.enable_load_balancer ? one([
      for ip in oci_load_balancer_load_balancer.main[0].ip_address_details : ip.ip_address if ip.is_public
    ]) : ""
    SYSTEMS_LB_CERT_OCID = var.lb_certificate_ocid != "" ? var.lb_certificate_ocid : ""
    SYSTEMS_LB_CERT_NAME = var.lb_certificate_ocid != "" ? replace(var.lb_public_hostname, ".", "-") : ""
  }

  container_environment_variables = merge(
    {
      PORT                   = tostring(var.app_port)
      ORDS_BASE_URL          = local.ords_base_url
      CASHIER_PIN            = var.cashier_pin
      ADMIN_PIN              = var.admin_pin != "" ? var.admin_pin : var.cashier_pin
      CASHIER_SESSION_SECURE = (
        var.cashier_session_secure
        || var.cloudflare_tunnel_token != ""
        || (var.enable_load_balancer && var.lb_certificate_ocid != "")
        || (var.enable_load_balancer && var.lb_tls_certificate_pem != "" && var.lb_tls_private_key_pem != "")
      ) ? "true" : "false"
      IDP_ALLOW_PIN          = var.idp_allow_pin ? "true" : "false"
      CASHIER_SUPERVISOR_APPROVAL = var.cashier_supervisor_approval ? "true" : "false"
      CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR = var.cashier_supervisor_pin_is_supervisor ? "true" : "false"
      APP_PUBLIC_URL_FROM_REQUEST = var.app_public_url_from_request ? "true" : "false"
      IDP_SIGNIN_DEBUG            = var.idp_signin_debug ? "true" : "false"
      IDP_SCOPES                  = var.idp_scopes
    },
    local.optional_app_env,
    { for k, v in local.systems_container_env : k => v if v != "" },
  )
}

# ── Container Instance ────────────────────────────────────────────────────────
resource "oci_container_instances_container_instance" "main" {
  compartment_id      = oci_identity_compartment.main.id
  availability_domain = local.ad_name
  display_name        = "container-instance-${var.project_name}"
  shape               = "CI.Standard.A1.Flex"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  vnics {
    subnet_id             = oci_core_subnet.main.id
    is_public_ip_assigned = true
    display_name          = "vnic-${var.project_name}"
  }

  containers {
    display_name = "${var.project_name}-container-1"
    image_url    = local.image_path

    environment_variables = local.container_environment_variables
  }

  freeform_tags = { project = var.project_name }
}
