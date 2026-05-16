# ── OCI Auth ──────────────────────────────────────────────────────────────────
# These values come from your OCI API key setup.
# Found in: OCI Console → Profile → My Profile → API Keys

variable "tenancy_ocid" {
  description = "OCID of your OCI tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID of the OCI user running Terraform"
  type        = string
}

variable "fingerprint" {
  description = "API key fingerprint for the OCI user"
  type        = string
}

variable "private_key_path" {
  description = "Path to the OCI API private key .pem file"
  type        = string
  default     = "~/.oci/oci_api_key.pem"
}

variable "region" {
  description = "OCI home region identifier"
  type        = string
  default     = "us-ashburn-1"
}

# ── Project ───────────────────────────────────────────────────────────────────

variable "project_name" {
  description = "Single OCI compartment name plus OCIR repo / VCN / container display-name prefix (default: cloud-store)"
  type        = string
  default     = "cloud-store"
}

variable "object_storage_namespace" {
  description = "OCI Object Storage namespace (Governance → Tenancy Details → Object Storage Namespace)"
  type        = string
}

variable "ocir_region_key" {
  description = "Short region key used in the OCIR hostname (iad = us-ashburn-1)"
  type        = string
  default     = "iad"
  # Common values: iad (Ashburn), phx (Phoenix), fra (Frankfurt), lhr (London), nrt (Tokyo)
}

variable "ocir_image_tag" {
  description = "Docker image tag to deploy to the container instance"
  type        = string
  default     = "latest"
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "vcn_cidr" {
  description = "CIDR block for the VCN"
  type        = string
  default     = "10.0.0.0/24"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet (must be within vcn_cidr)"
  type        = string
  default     = "10.0.0.0/24"
}

variable "app_port" {
  description = "TCP port the Node.js app listens on"
  type        = number
  default     = 3000
}

variable "cashier_pin" {
  description = "Cashier PIN for POST /api/cashier/unlock (tablet POS)"
  type        = string
  default     = "8930"
  sensitive   = true
}

variable "admin_pin" {
  description = "Admin UI PIN (defaults to cashier_pin when empty in container.tf)"
  type        = string
  default     = ""
  sensitive   = true
}

# ── Autonomous Database ───────────────────────────────────────────────────────

variable "adb_db_name" {
  description = "Database name — no spaces, max 14 chars, uppercase"
  type        = string
  default     = "CLOUDSTORE893"
}

variable "adb_admin_password" {
  description = "ADB admin password (min 12 chars: upper + lower + number + special char)"
  type        = string
  sensitive   = true
}
