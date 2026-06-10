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

variable "ingress_allowed_cidrs" {
  description = <<-EOT
    CIDR blocks allowed inbound to the app port (and SSH when allow_ssh_ingress is true).
    Default 0.0.0.0/0 keeps the current public app URL. For shop-only access, set your
    public IP with /32 (e.g. ["203.0.113.50/32"]). Tablets on cellular need VPN or 0.0.0.0/0.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allow_ssh_ingress" {
  description = "When false, no SSH (port 22) rule is created on the security list."
  type        = bool
  default     = true
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

variable "cashier_session_secure" {
  description = "Set true when the app is served over HTTPS (adds Secure flag on cashier session cookie). Auto-enabled when cloudflare_tunnel_token is set."
  type        = bool
  default     = false
}

variable "cloudflare_tunnel_token" {
  description = "Cloudflare Tunnel token (CLOUDFLARE_TUNNEL_TOKEN). When set, the container runs cloudflared alongside Node."
  type        = string
  default     = ""
  sensitive   = true
}

variable "cloudflare_tunnel_hostname" {
  description = "Public HTTPS hostname on the tunnel (e.g. oci.cloudstore893.com). Used by confirm-public-url.sh / app_url_https output — not injected into the container."
  type        = string
  default     = ""
}

# ── Load Balancer (HTTPS) ─────────────────────────────────────────────────────
# Preferred production path when HTTPS must terminate on OCI. See docs/oci-load-balancer-https.md.
# TLS PEMs: terraform/lb_tls.auto.tfvars (gitignored) from scripts/generate-lb-tls.sh or Let's Encrypt.

variable "enable_load_balancer" {
  description = "When true, create a flexible OCI Load Balancer in front of the container instance."
  type        = bool
  default     = false
}

variable "lb_public_hostname" {
  description = "Public DNS hostname for HTTPS (e.g. oci.cloudstore893.com). Used in app_url_https output."
  type        = string
  default     = "oci.cloudstore893.com"
}

variable "lb_bandwidth_mbps" {
  description = "Flexible load balancer bandwidth (Mbps). Minimum 10 on OCI."
  type        = number
  default     = 10
}

variable "lb_enable_http_listener" {
  description = "When true and HTTPS certs are not yet set, expose HTTP :80 on the load balancer for bring-up."
  type        = bool
  default     = true
}

variable "lb_certificate_ocid" {
  description = "OCI Certificates service OCID for the HTTPS listener (Let's Encrypt import). Preferred over lb_tls_* PEMs."
  type        = string
  default     = ""
}

variable "lb_tls_certificate_pem" {
  description = "TLS certificate PEM for the HTTPS listener (public / leaf cert)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "lb_tls_private_key_pem" {
  description = "TLS private key PEM for the HTTPS listener."
  type        = string
  default     = ""
  sensitive   = true
}

variable "lb_tls_ca_certificate_pem" {
  description = "Optional CA / intermediate chain PEM (fullchain minus leaf). Omit for self-signed POC."
  type        = string
  default     = ""
  sensitive   = true
}

# ── Cert renewal Function (Let's Encrypt → OCI Certificates) ─────────────────
# See docs/oci-load-balancer-https.md § Function-driven renewal.

variable "enable_cert_renew_function" {
  description = "When true, create Object Storage bucket, Functions app/function, and IAM for automated LE renewal."
  type        = bool
  default     = false
}

variable "certbot_state_bucket_name" {
  description = "Object Storage bucket for certbot config/work/logs between function runs."
  type        = string
  default     = "cloud-store-certbot-state"
}

variable "cert_renew_image_tag" {
  description = "OCIR image tag for the cert-renew function (same repo as app: project_name:tag)."
  type        = string
  default     = "cert-renew"
}

variable "cert_renew_email" {
  description = "Let's Encrypt account email for the cert-renew function."
  type        = string
  default     = ""
}

variable "cert_renew_memory_mbs" {
  description = "Memory for cert-renew function (MB). Certbot + DNS propagation needs headroom."
  type        = number
  default     = 512
}

variable "cert_renew_timeout_seconds" {
  description = "Sync invoke timeout (seconds). Use invoke --call-type detached for longer runs if needed."
  type        = number
  default     = 300
}

variable "cert_renew_dns_propagation_seconds" {
  description = "Wait after OCI DNS TXT record before ACME validation."
  type        = number
  default     = 120
}

variable "enable_cert_renew_schedule" {
  description = "When true (and enable_cert_renew_function), create a weekly Resource Scheduler job to invoke cert-renew."
  type        = bool
  default     = true
}

variable "cert_renew_schedule_cron" {
  description = "Cron (UTC) for cert-renew Resource Scheduler. Default: Sundays 03:00 UTC."
  type        = string
  default     = "0 3 * * 0"
}

variable "cert_renew_schedule_display_name" {
  description = "Display name for the cert-renew Resource Scheduler schedule."
  type        = string
  default     = "cert-renew-weekly"
}

# ── App / IdP / Model B (container env) ───────────────────────────────────────
# Optional. Leave empty to omit from container env. Prefer container_env.auto.tfvars
# generated by scripts/oci/sync-container-env-to-terraform.sh from repo .env.

variable "app_public_url" {
  description = "Optional APP_PUBLIC_URL on container. Prefer app_public_url_from_request on OCI (ephemeral IP)."
  type        = string
  default     = ""
}

variable "app_public_url_from_request" {
  description = "When true, OAuth redirect_uri uses the request Host (APP_PUBLIC_URL_FROM_REQUEST). Use on OCI."
  type        = bool
  default     = true
}

variable "idp_pos_issuer" {
  type      = string
  default   = ""
  sensitive = false
}

variable "idp_pos_client_id" {
  type      = string
  default   = ""
  sensitive = false
}

variable "idp_pos_client_secret" {
  type      = string
  default   = ""
  sensitive = true
}

variable "idp_admin_issuer" {
  type      = string
  default   = ""
  sensitive = false
}

variable "idp_admin_client_id" {
  type      = string
  default   = ""
  sensitive = false
}

variable "idp_admin_client_secret" {
  type      = string
  default   = ""
  sensitive = true
}

variable "idp_signin_debug" {
  description = "When true, OAuth callback errors include the underlying message (IDP_SIGNIN_DEBUG)."
  type        = bool
  default     = false
}

variable "idp_scopes" {
  description = "OAuth scopes for IdP authorize requests (IDP_SCOPES). Include groups for supervisor/cashier checks."
  type        = string
  default     = "openid profile email groups"
}

variable "idp_allow_pin" {
  description = "When true, PIN remains available alongside IdP (container env IDP_ALLOW_PIN)."
  type        = bool
  default     = true
}

variable "cashier_supervisor_approval" {
  description = "Enable Model B supervisor approval (CASHIER_SUPERVISOR_APPROVAL)."
  type        = bool
  default     = false
}

variable "cashier_approval_ttl_sec" {
  description = "Pending login TTL in seconds (CASHIER_APPROVAL_TTL_SEC)."
  type        = number
  default     = 300
}

variable "idp_supervisor_group" {
  type    = string
  default = "store-supervisors"
}

variable "idp_pos_cashier_group" {
  type    = string
  default = "store-cashiers"
}

variable "cashier_supervisor_pin_is_supervisor" {
  description = "Local dev: admin PIN counts as supervisor when true."
  type        = bool
  default     = false
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
