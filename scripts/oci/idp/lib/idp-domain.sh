#!/usr/bin/env bash

idp_list_domain_numbers() {
  local prefix="$1" compartment="$2"
  oci iam domain list \
    --compartment-id "$compartment" \
    --all \
    --query "data[?starts_with(\"display-name\", '${prefix}')].\"display-name\"" \
    --raw-output 2>/dev/null \
    | jq -r '.[]?' 2>/dev/null \
    | sed -n "s/^${prefix}\([0-9][0-9]*\)$/\1/p"
}

idp_next_domain_name() {
  local prefix="$1" compartment="$2" max=0 n
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    if ((10#$n > max)); then max=$((10#$n)); fi
  done < <(idp_list_domain_numbers "$prefix" "$compartment")
  printf '%s%s' "$prefix" "$((max + 1))"
}

idp_domain_id_by_name() {
  local display_name="$1" compartment="$2"
  oci iam domain list \
    --compartment-id "$compartment" \
    --display-name "$display_name" \
    --query 'data[0].id' \
    --raw-output 2>/dev/null
}

idp_latest_domain_name() {
  local prefix="$1" compartment="$2" max=0
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    if ((10#$n > max)); then max=$((10#$n)); fi
  done < <(idp_list_domain_numbers "$prefix" "$compartment")
  if ((max > 0)); then
    printf '%s%s' "$prefix" "$max"
  fi
}

idp_wait_work_request_domain_id() {
  local wr_id="$1" i status domain_id tmp
  for i in $(seq 1 80); do
    tmp="$(mktemp)"
    oci iam iam-work-request get --iam-work-request-id "$wr_id" >"$tmp"
    status="$(jq -r '.data.status // empty' "$tmp")"
    domain_id="$(jq -r '.data.resources[]? | select(."entity-type"=="domain") | .identifier' "$tmp" | head -1)"
    rm -f "$tmp"
    case "$status" in
      SUCCEEDED)
        [[ -n "$domain_id" && "$domain_id" != "null" ]] || {
          echo "error: work request succeeded but no domain resource" >&2
          return 1
        }
        printf '%s' "$domain_id"
        return 0
        ;;
      FAILED|CANCELED)
        echo "error: domain create work request $status" >&2
        oci iam iam-work-request list-iam-work-request-errors \
          --iam-work-request-id "$wr_id" >&2 || true
        return 1
        ;;
    esac
    if ((i == 1)); then
      echo "    Waiting for work request $status..."
    fi
    sleep 15
  done
  echo "error: timed out waiting for work request $wr_id" >&2
  return 1
}

idp_attach_domain() {
  local display_name="$1" domain_id="$2"
  IDP_DOMAIN_ID="$domain_id"
  IDP_DOMAIN_NAME="$display_name"
  echo "    Domain OCID: $IDP_DOMAIN_ID"
  echo "    Waiting for ACTIVE..."
  idp_wait_domain_active "$IDP_DOMAIN_ID"
  idp_resolve_domain_urls "$IDP_DOMAIN_ID"
  export IDP_DOMAIN_ID IDP_DOMAIN_NAME
}

idp_wait_domain_active() {
  local domain_id="$1" i state
  for i in $(seq 1 60); do
    state="$(oci iam domain get --domain-id "$domain_id" --query 'data."lifecycle-state"' --raw-output 2>/dev/null || true)"
    case "$state" in
      ACTIVE)
        return 0
        ;;
      FAILED|DELETED|DELETING)
        echo "error: domain entered state $state" >&2
        return 1
        ;;
    esac
    sleep 10
  done
  echo "error: domain not ACTIVE after 10 minutes (last state: ${state:-unknown})" >&2
  return 1
}

idp_resolve_domain_urls() {
  local domain_id="$1"
  local raw_home raw_url
  raw_home="$(oci iam domain get --domain-id "$domain_id" --query 'data."home-region-url"' --raw-output)"
  raw_url="$(oci iam domain get --domain-id "$domain_id" --query 'data.url' --raw-output)"

  IDP_DOMAIN_ENDPOINT="${raw_home%/admin/v1}"
  IDP_DOMAIN_ENDPOINT="${IDP_DOMAIN_ENDPOINT%/}"
  IDP_DOMAIN_ENDPOINT="${IDP_DOMAIN_ENDPOINT%:443}"

  # Issuer for OIDC (shorter host; fallback to endpoint host).
  if [[ -n "$raw_url" && "$raw_url" != "null" ]]; then
    IDP_ISSUER="${raw_url%/}"
    IDP_ISSUER="${IDP_ISSUER%:443}"
  else
    IDP_ISSUER="$IDP_DOMAIN_ENDPOINT"
  fi

  export IDP_DOMAIN_ENDPOINT IDP_ISSUER
}

idp_create_domain() {
  local display_name="$1"
  local existing_id
  existing_id="$(idp_domain_id_by_name "$display_name" "$IDP_COMPARTMENT_OCID")"
  if [[ -n "$existing_id" && "$existing_id" != "null" ]]; then
    echo "==> Using existing identity domain: $display_name"
    idp_attach_domain "$display_name" "$existing_id"
    return 0
  fi

  echo "==> Creating identity domain: $display_name (license: $IDP_LICENSE_TYPE)"
  local tmp wr_id
  tmp="$(mktemp)"
  oci iam domain create \
    --compartment-id "$IDP_COMPARTMENT_OCID" \
    --display-name "$display_name" \
    --description "Cloud Store dev IdP (automated bootstrap)" \
    --home-region "$IDP_REGION" \
    --license-type "$IDP_LICENSE_TYPE" \
    --is-primary-email-required true \
    >"$tmp"

  IDP_DOMAIN_ID="$(jq -r '.data.id // empty' "$tmp")"
  if [[ -z "$IDP_DOMAIN_ID" ]]; then
    wr_id="$(jq -r '.["opc-work-request-id"] // empty' "$tmp")"
    [[ -n "$wr_id" ]] || {
      echo "error: domain create returned no domain id or work request" >&2
      cat "$tmp" >&2
      rm -f "$tmp"
      return 1
    }
    echo "    Async work request: $wr_id"
    IDP_DOMAIN_ID="$(idp_wait_work_request_domain_id "$wr_id")" || {
      rm -f "$tmp"
      return 1
    }
  fi
  rm -f "$tmp"

  idp_attach_domain "$display_name" "$IDP_DOMAIN_ID"
}
