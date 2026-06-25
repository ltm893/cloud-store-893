#!/usr/bin/env bash

# Build public + localhost redirect URIs (same rules as idp-update-redirect-uris.sh).
idp_collect_redirect_uris() {
  local role="$1"
  local host scheme base local_port port_suffix h
  host="${APP_PUBLIC_HOST:?Set APP_PUBLIC_HOST before creating OIDC apps}"
  scheme="${APP_PUBLIC_SCHEME:-http}"
  local_port="${APP_PORT:-3000}"

  port_suffix=""
  if [[ -n "${APP_PUBLIC_PORT:-}" ]]; then
    if [[ "$scheme" == "https" && "$APP_PUBLIC_PORT" == "443" ]] \
      || [[ "$scheme" == "http" && "$APP_PUBLIC_PORT" == "80" ]]; then
      port_suffix=""
    else
      port_suffix=":${APP_PUBLIC_PORT}"
    fi
    local_port="$APP_PUBLIC_PORT"
  fi
  base="${scheme}://${host}${port_suffix}"

  local -a uris=()
  if [[ "$role" == "admin" ]]; then
    uris+=("${base}/admin/" "${base}/oauth/admin/callback")
  else
    uris+=("${base}/" "${base}/oauth/callback")
  fi

  local -a local_hosts=(127.0.0.1 localhost)
  if [[ -n "${EXTRA_REDIRECT_HOSTS:-}" ]]; then
    read -r -a _extra <<< "${EXTRA_REDIRECT_HOSTS}"
    local_hosts+=("${_extra[@]}")
  fi
  for h in "${local_hosts[@]}"; do
    [[ -z "$h" ]] && continue
    if [[ "$role" == "admin" ]]; then
      uris+=("http://${h}:${local_port}/admin/" "http://${h}:${local_port}/oauth/admin/callback")
    else
      uris+=("http://${h}:${local_port}/" "http://${h}:${local_port}/oauth/callback")
    fi
  done

  printf '%s\n' "${uris[@]}" | jq -R . | jq -s .
}

idp_app_role_for_name() {
  local display_name="$1"
  if [[ "$display_name" == "$IDP_ADMIN_APP_NAME" ]]; then
    printf '%s' 'admin'
  else
    printf '%s' 'pos'
  fi
}

idp_build_app_json() {
  local display_name="$1" description="$2" role redirects_json
  role="$(idp_app_role_for_name "$display_name")"
  redirects_json="$(idp_collect_redirect_uris "$role")"
  local template="${IDP_APP_TEMPLATE:-CustomWebAppTemplateId}"
  jq -nc \
    --arg name "$display_name" \
    --arg desc "$description" \
    --arg template "$template" \
    --argjson redirects "$redirects_json" \
    '{
      schemas: ["urn:ietf:params:scim:schemas:oracle:idcs:App"],
      basedOnTemplate: {value: $template},
      displayName: $name,
      description: $desc,
      active: true,
      isOAuthClient: true,
      clientType: "confidential",
      allUrlSchemesAllowed: true,
      allowOffline: true,
      allowedGrants: ["authorization_code", "refresh_token"],
      redirectUris: $redirects
    }'
}

idp_app_oauth_client_id() {
  local display_name="$1" app_id="${2:-}"
  local client_id
  client_id="$(idp_idcs apps list \
    --endpoint "$IDP_DOMAIN_ENDPOINT" \
    --filter "$(printf 'displayName eq "%s"' "$display_name")" \
    --attributes id,name \
    --query 'data.resources[0].name' \
    --raw-output 2>/dev/null || true)"
  if [[ -n "$client_id" && "$client_id" != "null" ]]; then
    printf '%s' "$client_id"
    return 0
  fi
  [[ -n "$app_id" && "$app_id" != "null" ]] || return 1
  idp_idcs app get \
    --endpoint "$IDP_DOMAIN_ENDPOINT" \
    --app-id "$app_id" \
    --query 'data.name' \
    --raw-output 2>/dev/null || true
}

idp_app_oauth_client_secret() {
  local app_id="$1"
  idp_idcs app get \
    --endpoint "$IDP_DOMAIN_ENDPOINT" \
    --app-id "$app_id" \
    --query 'data."client-secret"' \
    --raw-output 2>/dev/null || true
}

idp_regenerate_app_client_secret() {
  local app_id="$1"
  local base="${IDP_DOMAIN_ENDPOINT%/}"
  base="${base%/admin/v1}"
  base="${base%:443}"
  local tmp body secret status
  body="$(jq -nc --arg appId "$app_id" \
    '{schemas:["urn:ietf:params:scim:schemas:oracle:idcs:AppClientSecretRegenerator"],appId:$appId}')"
  tmp="$(mktemp)"
  oci raw-request \
    --http-method POST \
    --target-uri "${base}/admin/v1/AppClientSecretRegenerator" \
    --request-body "$body" \
    >"$tmp"
  status="$(jq -r '.status // empty' "$tmp")"
  secret="$(jq -r '.data.clientSecret // .data."client-secret" // empty' "$tmp")"
  if [[ -z "$secret" || "$secret" == "null" ]]; then
    echo "error: AppClientSecretRegenerator failed (${status:-no status})" >&2
    jq . "$tmp" >&2
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
  printf '%s' "$secret"
}

idp_redirect_uris_match_expected() {
  local display_name="$1" role="$2"
  local current expected
  current="$(idp_idcs apps list \
    --endpoint "$IDP_DOMAIN_ENDPOINT" \
    --filter "$(printf 'displayName eq "%s"' "$display_name")" \
    --attributes redirectUris \
    --query 'data.resources[0]."redirect-uris"' \
    --raw-output 2>/dev/null || true)"
  [[ -n "$current" && "$current" != "null" ]] || return 1
  expected="$(idp_collect_redirect_uris "$role")"
  [[ "$(jq -c 'sort' <<<"$current")" == "$(jq -c 'sort' <<<"$expected")" ]]
}

idp_find_app_id() {
  local display_name="$1"
  idp_idcs apps list \
    --endpoint "$IDP_DOMAIN_ENDPOINT" \
    --filter "$(printf 'displayName eq "%s"' "$display_name")" \
    --attributes id \
    --query 'data.resources[0].id' \
    --raw-output 2>/dev/null || true
}

idp_create_or_get_app() {
  local display_name="$1" description="$2"
  local app_id client_id client_secret
  app_id="$(idp_find_app_id "$display_name")"
  if [[ -n "$app_id" && "$app_id" != "null" ]]; then
    echo "    App exists: $display_name ($app_id)" >&2
    client_id="$(idp_app_oauth_client_id "$display_name" "$app_id")"
    [[ -n "$client_id" && "$client_id" != "null" ]] || {
      echo "error: could not read OAuth client id (app name) for $display_name" >&2
      return 1
    }
    client_secret="$(idp_app_oauth_client_secret "$app_id")"
    if [[ -z "$client_secret" || "$client_secret" == "null" ]]; then
      echo "    Regenerating client secret..." >&2
      client_secret="$(idp_regenerate_app_client_secret "$app_id")" || return 1
    else
      echo "    Using existing client secret from app" >&2
    fi
    printf '%s\n%s\n%s' "$app_id" "$client_id" "$client_secret"
    return 0
  fi

  local body tmp
  body="$(idp_build_app_json "$display_name" "$description")"
  tmp="$(mktemp)"
  idp_idcs app create \
    --endpoint "$IDP_DOMAIN_ENDPOINT" \
    --from-json "$body" \
    >"$tmp"

  app_id="$(jq -r '.data.id // empty' "$tmp")"
  client_id="$(jq -r '.data.name // .data."oauth-client"."client-id" // .data."oauth-client".clientId // .data."client-id" // .data.clientId // empty' "$tmp")"
  client_secret="$(jq -r '.data."client-secret" // .data."oauth-client"."client-secret" // .data."oauth-client".clientSecret // empty' "$tmp")"

  if [[ -z "$app_id" ]]; then
    echo "error: failed to create app $display_name" >&2
    cat "$tmp" >&2
    rm -f "$tmp"
    return 1
  fi

  echo "    Created app: $display_name ($app_id)" >&2
  if [[ -z "$client_secret" ]]; then
    echo "warn: client secret not in create response — reset in OCI Console if needed" >&2
  fi
  rm -f "$tmp"
  printf '%s\n%s\n%s' "$app_id" "$client_id" "$client_secret"
}

idp_grant_group_to_app() {
  local group_id="$1" app_id="$2"
  local schemas='["urn:ietf:params:scim:schemas:oracle:idcs:Grant"]'
  local grantee app_ref
  grantee="$(jq -nc --arg g "$group_id" '{value:$g,type:"Group"}')"
  app_ref="$(jq -nc --arg a "$app_id" '{value:$a}')"
  idp_idcs grant create \
    --endpoint "$IDP_DOMAIN_ENDPOINT" \
    --schemas "$schemas" \
    --grant-mechanism ADMINISTRATOR_TO_GROUP \
    --grantee "$grantee" \
    --app "$app_ref" \
    >/dev/null 2>&1 || true
}

idp_bootstrap_apps() {
  echo "==> OIDC confidential apps"
  local pos_lines admin_lines
  pos_lines="$(idp_create_or_get_app "$IDP_POS_APP_NAME" "Cloud Store POS OIDC client (dev)")"
  admin_lines="$(idp_create_or_get_app "$IDP_ADMIN_APP_NAME" "Cloud Store admin OIDC client (dev)")"

  IDP_POS_APP_ID="$(printf '%s' "$pos_lines" | sed -n '1p')"
  IDP_POS_CLIENT_ID="$(printf '%s' "$pos_lines" | sed -n '2p')"
  IDP_POS_CLIENT_SECRET="$(printf '%s' "$pos_lines" | sed -n '3p')"
  IDP_ADMIN_APP_ID="$(printf '%s' "$admin_lines" | sed -n '1p')"
  IDP_ADMIN_CLIENT_ID="$(printf '%s' "$admin_lines" | sed -n '2p')"
  IDP_ADMIN_CLIENT_SECRET="$(printf '%s' "$admin_lines" | sed -n '3p')"

  export IDP_POS_APP_ID IDP_POS_CLIENT_ID IDP_POS_CLIENT_SECRET
  export IDP_ADMIN_APP_ID IDP_ADMIN_CLIENT_ID IDP_ADMIN_CLIENT_SECRET
}

idp_grant_groups_to_apps() {
  echo "==> Assign groups to integrated apps"
  local g_cashier g_super g_admin
  g_cashier="$(idp_idcs groups list --endpoint "$IDP_DOMAIN_ENDPOINT" --filter "$(printf 'displayName eq "%s"' "$IDP_CASHIER_GROUP")" --attributes id --query 'data.resources[0].id' --raw-output)"
  g_super="$(idp_idcs groups list --endpoint "$IDP_DOMAIN_ENDPOINT" --filter "$(printf 'displayName eq "%s"' "$IDP_SUPERVISOR_GROUP")" --attributes id --query 'data.resources[0].id' --raw-output)"
  g_admin="$(idp_idcs groups list --endpoint "$IDP_DOMAIN_ENDPOINT" --filter "$(printf 'displayName eq "%s"' "$IDP_ADMIN_GROUP")" --attributes id --query 'data.resources[0].id' --raw-output)"

  for gid in "$g_cashier" "$g_super"; do
    [[ -n "$gid" && "$gid" != "null" ]] && idp_grant_group_to_app "$gid" "$IDP_POS_APP_ID"
  done
  for gid in "$g_super" "$g_admin"; do
    [[ -n "$gid" && "$gid" != "null" ]] && idp_grant_group_to_app "$gid" "$IDP_ADMIN_APP_ID"
  done
  echo "    Grants applied (best-effort; verify in Console if sign-in fails)"
}
