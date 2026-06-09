# ── Flexible Load Balancer (HTTPS → container HTTP) ───────────────────────────
# Enable with enable_load_balancer = true and TLS PEMs in lb_tls.auto.tfvars
# (see docs/oci-load-balancer-https.md). Node stays on HTTP :app_port; TLS
# terminates at the listener.

data "oci_core_private_ips" "container_primary" {
  count   = var.enable_load_balancer ? 1 : 0
  vnic_id = data.oci_core_vnic.main.id

  filter {
    name   = "is_primary"
    values = [true]
  }
}

locals {
  lb_https_pem = (
    var.enable_load_balancer
    && var.lb_tls_certificate_pem != ""
    && var.lb_tls_private_key_pem != ""
  )
  lb_https_certs_service = (
    var.enable_load_balancer
    && var.lb_certificate_ocid != ""
  )
  lb_https_enabled = local.lb_https_pem || local.lb_https_certs_service
}
resource "oci_load_balancer_load_balancer" "main" {
  count = var.enable_load_balancer ? 1 : 0

  compartment_id = oci_identity_compartment.main.id
  display_name   = "lb-${var.project_name}"
  shape          = "flexible"

  shape_details {
    minimum_bandwidth_in_mbps = var.lb_bandwidth_mbps
    maximum_bandwidth_in_mbps = var.lb_bandwidth_mbps
  }

  subnet_ids = [oci_core_subnet.main.id]
  is_private = false

  freeform_tags = { project = var.project_name }
}

resource "oci_load_balancer_certificate" "app_tls" {
  count = local.lb_https_pem ? 1 : 0
  
  load_balancer_id = oci_load_balancer_load_balancer.main[0].id
  certificate_name = "app-tls-${var.project_name}"

  public_certificate = var.lb_tls_certificate_pem
  private_key        = var.lb_tls_private_key_pem
  ca_certificate     = var.lb_tls_ca_certificate_pem != "" ? var.lb_tls_ca_certificate_pem : null

  lifecycle {
    create_before_destroy = true
  }
}

resource "oci_load_balancer_backend_set" "app" {
  count = var.enable_load_balancer ? 1 : 0

  load_balancer_id = oci_load_balancer_load_balancer.main[0].id
  name             = "app-backend"
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol          = "HTTP"
    port              = var.app_port
    url_path          = "/api/build-info"
    return_code       = 200
    interval_ms       = 10000
    timeout_in_millis = 3000
    retries           = 3
  }
}

resource "oci_load_balancer_backend" "app" {
  count = var.enable_load_balancer ? 1 : 0

  load_balancer_id = oci_load_balancer_load_balancer.main[0].id
  backendset_name  = oci_load_balancer_backend_set.app[0].name
  ip_address       = data.oci_core_private_ips.container_primary[0].private_ips[0].ip_address
  port             = var.app_port
  weight           = 1
  backup           = false
  drain            = false
  offline          = false
}

resource "oci_load_balancer_listener" "https" {
  count = local.lb_https_enabled ? 1 : 0

  load_balancer_id         = oci_load_balancer_load_balancer.main[0].id
  name                     = "https"
  default_backend_set_name = oci_load_balancer_backend_set.app[0].name
  port                     = 443
  protocol                 = "HTTP"

   ssl_configuration {
    certificate_ids         = [var.lb_certificate_ocid]
    verify_peer_certificate = false
    protocols               = ["TLSv1.2", "TLSv1.3"]
  }
}

resource "oci_load_balancer_listener" "http" {
  count = var.enable_load_balancer && var.lb_enable_http_listener && !local.lb_https_enabled ? 1 : 0

  load_balancer_id         = oci_load_balancer_load_balancer.main[0].id
  name                     = "http"
  default_backend_set_name = oci_load_balancer_backend_set.app[0].name
  port                     = 80
  protocol                 = "HTTP"
}
