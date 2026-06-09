# ── VCN ───────────────────────────────────────────────────────────────────────
resource "oci_core_vcn" "main" {
  compartment_id = oci_identity_compartment.main.id
  display_name   = "vcn-${var.project_name}"
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = "vcn893"

  freeform_tags = { project = var.project_name }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────
# Required for the container instance to pull images from OCIR
resource "oci_core_internet_gateway" "main" {
  compartment_id = oci_identity_compartment.main.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "ig-${var.project_name}"
  enabled        = true

  freeform_tags = { project = var.project_name }
}

# ── Route Table ───────────────────────────────────────────────────────────────
# Sends all outbound traffic (0.0.0.0/0) to the internet gateway
resource "oci_core_route_table" "main" {
  compartment_id = oci_identity_compartment.main.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "rt-${var.project_name}"

  route_rules {
    network_entity_id = oci_core_internet_gateway.main.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }

  freeform_tags = { project = var.project_name }
}

# ── Security List ─────────────────────────────────────────────────────────────
resource "oci_core_security_list" "main" {
  compartment_id = oci_identity_compartment.main.id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "sl-${var.project_name}"

  dynamic "ingress_security_rules" {
    for_each = var.allow_ssh_ingress ? var.ingress_allowed_cidrs : []
    content {
      protocol  = "6" # TCP
      source    = ingress_security_rules.value
      stateless = false
      tcp_options {
        min = 22
        max = 22
      }
    }
  }

  # App port: VCN-only when LB fronts the container; otherwise public per ingress_allowed_cidrs.
  dynamic "ingress_security_rules" {
    for_each = var.enable_load_balancer ? [var.vcn_cidr] : var.ingress_allowed_cidrs
    content {
      protocol  = "6"
      source    = ingress_security_rules.value
      stateless = false
      tcp_options {
        min = var.app_port
        max = var.app_port
      }
    }
  }

  dynamic "ingress_security_rules" {
    for_each = var.enable_load_balancer ? var.ingress_allowed_cidrs : []
    content {
      protocol  = "6"
      source    = ingress_security_rules.value
      stateless = false
      tcp_options {
        min = 443
        max = 443
      }
    }
  }

  dynamic "ingress_security_rules" {
    for_each = var.enable_load_balancer && var.lb_enable_http_listener ? var.ingress_allowed_cidrs : []
    content {
      protocol  = "6"
      source    = ingress_security_rules.value
      stateless = false
      tcp_options {
        min = 80
        max = 80
      }
    }
  }

  # Egress: All traffic (needed to pull OCIR image and reach ORDS)
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
  }

  freeform_tags = { project = var.project_name }
}

# ── Public Subnet ─────────────────────────────────────────────────────────────
resource "oci_core_subnet" "main" {
  compartment_id             = oci_identity_compartment.main.id
  vcn_id                     = oci_core_vcn.main.id
  display_name               = "subnet-${var.project_name}"
  cidr_block                 = var.subnet_cidr
  route_table_id             = oci_core_route_table.main.id
  security_list_ids          = [oci_core_security_list.main.id]
  prohibit_public_ip_on_vnic = false # public subnet — assigns a public IP
  dns_label                  = "pub893"

  freeform_tags = { project = var.project_name }
}
