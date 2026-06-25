#!/usr/bin/env bash
# Resolve prod vs dev Terraform var-file, state file, and public hostname.
#
# Usage (from repo scripts):
#   PROJECT_ROOT="$(cd ... && pwd)"
#   # shellcheck source=lib/terraform-env.sh
#   source "$PROJECT_ROOT/scripts/oci/lib/terraform-env.sh"
#   cloud_store_resolve_tf_env "$PROJECT_ROOT"
#   cloud_store_tf plan
#   cloud_store_tf_output container_instance_ocid
#
# Select environment:
#   CLOUD_STORE_ENV=dev   (default: prod)
#   ./scripts/oci/redeploy-app-code-dev.sh "label"

cloud_store_resolve_tf_env() {
  local project_root="${1:?project_root required}"
  CLOUD_STORE_ENV="${CLOUD_STORE_ENV:-prod}"
  CLOUD_STORE_TF_DIR="${CLOUD_STORE_TF_DIR:-$project_root/terraform}"

  case "$CLOUD_STORE_ENV" in
    prod)
      CLOUD_STORE_TFVARS="$CLOUD_STORE_TF_DIR/terraform.tfvars"
      CLOUD_STORE_TF_STATE="$CLOUD_STORE_TF_DIR/terraform.tfstate"
      CLOUD_STORE_CONTAINER_ENV_FILE="$CLOUD_STORE_TF_DIR/container_env.prod.tfvars"
      CLOUD_STORE_PUBLIC_HOSTNAME="${CLOUD_STORE_PUBLIC_HOSTNAME:-oci.cloudstore893.com}"
      ;;
    dev)
      CLOUD_STORE_TFVARS="$CLOUD_STORE_TF_DIR/terraform.dev.tfvars"
      CLOUD_STORE_TF_STATE="$CLOUD_STORE_TF_DIR/terraform.dev.tfstate"
      CLOUD_STORE_CONTAINER_ENV_FILE="$CLOUD_STORE_TF_DIR/container_env.dev.tfvars"
      CLOUD_STORE_PUBLIC_HOSTNAME="${CLOUD_STORE_PUBLIC_HOSTNAME:-dev.oci.cloudstore893.com}"
      ;;
    *)
      echo "error: CLOUD_STORE_ENV must be prod or dev (got: $CLOUD_STORE_ENV)" >&2
      return 1
      ;;
  esac

  export CLOUD_STORE_ENV CLOUD_STORE_TF_DIR CLOUD_STORE_TFVARS CLOUD_STORE_TF_STATE \
    CLOUD_STORE_CONTAINER_ENV_FILE CLOUD_STORE_PUBLIC_HOSTNAME
}

cloud_store_tf_var_files() {
  local -a files=()
  [[ -f "$CLOUD_STORE_TFVARS" ]] || {
    echo "error: Terraform var-file not found: $CLOUD_STORE_TFVARS" >&2
    if [[ "$CLOUD_STORE_ENV" == "dev" ]]; then
      echo "hint: cp terraform/terraform.dev.tfvars.example terraform/terraform.dev.tfvars" >&2
    else
      echo "hint: cp terraform/terraform.tfvars.example terraform/terraform.tfvars" >&2
    fi
    return 1
  }
  files+=(-var-file="$CLOUD_STORE_TFVARS")

  if [[ -f "$CLOUD_STORE_CONTAINER_ENV_FILE" ]]; then
    files+=(-var-file="$CLOUD_STORE_CONTAINER_ENV_FILE")
  elif [[ "$CLOUD_STORE_ENV" == "prod" && -f "$CLOUD_STORE_TF_DIR/container_env.auto.tfvars" ]]; then
    files+=(-var-file="$CLOUD_STORE_TF_DIR/container_env.auto.tfvars")
  fi

  printf '%s\0' "${files[@]}"
}

cloud_store_tf() {
  local -a var_files=()
  local chunk subcommand
  while IFS= read -r -d '' chunk; do
    var_files+=("$chunk")
  done < <(cloud_store_tf_var_files)

  subcommand="${1:?terraform subcommand required (plan|apply|destroy|import|...)}"
  shift

  # Terraform 1.14+: -state and -var-file are subcommand options, not global flags.
  terraform -chdir="$CLOUD_STORE_TF_DIR" \
    "$subcommand" \
    -state="$CLOUD_STORE_TF_STATE" \
    "${var_files[@]}" \
    "$@"
}

cloud_store_tf_output() {
  local name="${1:?output name required}"
  if [[ ! -f "$CLOUD_STORE_TF_STATE" ]]; then
    return 1
  fi
  terraform -chdir="$CLOUD_STORE_TF_DIR" \
    output -state="$CLOUD_STORE_TF_STATE" -raw "$name" 2>/dev/null || true
}

cloud_store_tf_init() {
  terraform -chdir="$CLOUD_STORE_TF_DIR" init -upgrade "$@"
}

cloud_store_env_label() {
  case "${CLOUD_STORE_ENV:-prod}" in
    dev) printf 'dev' ;;
    *) printf 'prod' ;;
  esac
}

cloud_store_container_ocid_var() {
  case "${CLOUD_STORE_ENV:-prod}" in
    dev) printf 'CLOUD_STORE_DEV_OCID' ;;
    *) printf 'CLOUD_STORE_OCID' ;;
  esac
}

cloud_store_container_ocid_from_env() {
  local var_name
  var_name="$(cloud_store_container_ocid_var)"
  printf '%s' "${!var_name:-}"
}
