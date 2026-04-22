# Terraform — cloud-store-893

Provisions and tears down all OCI resources for the cloud-store-893 project with a single command.

## Resources managed

| File | Resources created |
|---|---|
| `compartment.tf` | `oci_identity_compartment` |
| `network.tf` | VCN, Internet Gateway, Route Table, Security List, Subnet |
| `registry.tf` | Container Registry repository |
| `database.tf` | Autonomous Database (ATP, Always Free) |
| `container.tf` | Container Instance (CI.Standard.A1.Flex, Always Free) |

---

## Prerequisites

1. **Terraform** — `brew install terraform`
2. **OCI API key** — OCI Console → Profile → My Profile → API Keys → Add API Key
   - Download the private key to `~/.oci/oci_api_key.pem`
   - The console shows your `tenancy_ocid`, `user_ocid`, and `fingerprint` after creation
3. **Docker image already pushed to OCIR** — the container instance needs the image to exist at startup.
   Build and push before running `terraform apply`:
   ```bash
   docker buildx build --platform linux/arm64 -t <ocir_image_path> .
   docker push <ocir_image_path>
   ```
   The exact image path is printed by `terraform output ocir_image_path` after the first apply.

---

## Setup

```bash
cd terraform

# Install the OCI provider
terraform init

# Create your tfvars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your OCI credentials and namespace
```

---

## Deploy everything

```bash
terraform plan   # preview what will be created
terraform apply  # create all resources (~5–10 min for ADB provisioning)
```

After apply, useful outputs are printed automatically:

```
app_url                  = "http://<public-ip>:3000"
ocir_image_path          = "iad.ocir.io/<namespace>/cloud-store-893:latest"
ords_base_url            = "https://xxxx-CLOUDSTORE893.adb.us-ashburn-1.oraclecloudapps.com/ords/admin"
container_instance_ocid  = "ocid1.containerinstance..."
```

**After first apply:**
- Copy `ords_base_url` → update your `.env` file and `Dockerfile` ENV
- Copy `container_instance_ocid` → add `export CLOUD_STORE_OCID="..."` to `~/.zshrc`

---

## Tear down everything

```bash
terraform destroy   # removes all resources including the compartment
```

Destroy order is handled automatically by Terraform's dependency graph.

---

## Important notes

- **ADB provisioning takes 3–5 minutes** — `terraform apply` will wait.
- **Always Free limits** — your tenancy can only have 2 ADB Always Free instances and limited A1 OCPUs. If apply fails with a quota error, check the OCI Console.
- **terraform.tfvars is gitignored** — it contains your ADB admin password. Never commit it.
- **OCIR image must exist before `terraform apply`** — the container instance will fail to start if the image isn't in the registry yet.
  On a fresh setup: run `terraform apply` once (it will create the registry repo), push your image, then the container instance will be able to pull it. You may need to re-run apply after pushing.
