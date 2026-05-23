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
  ad_name    = data.oci_identity_availability_domains.all.availability_domains[0].name
  image_path = "${var.ocir_region_key}.ocir.io/${var.object_storage_namespace}/${var.project_name}:${var.ocir_image_tag}"
  ords_base_url = "${oci_database_autonomous_database.main.connection_urls[0].ords_url}admin"
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

    environment_variables = {
      PORT                     = tostring(var.app_port)
      ORDS_BASE_URL            = local.ords_base_url
      CASHIER_PIN              = var.cashier_pin
      ADMIN_PIN                = var.admin_pin != "" ? var.admin_pin : var.cashier_pin
      CASHIER_SESSION_SECURE   = var.cashier_session_secure ? "true" : "false"
    }
  }

  freeform_tags = { project = var.project_name }
}
