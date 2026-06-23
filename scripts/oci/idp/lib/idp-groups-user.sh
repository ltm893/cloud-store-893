#!/usr/bin/env bash

idp_idcs() {
  oci --region "$IDP_REGION" identity-domains "$@"
}

idp_create_group() {
  local display_name="$1"
  local gid
  gid="$(idp_idcs groups list \
    --endpoint "$IDP_DOMAIN_ENDPOINT" \
    --filter "$(printf 'displayName eq "%s"' "$display_name")" \
    --attributes id,displayName \
    --query 'data.resources[0].id' \
    --raw-output 2>/dev/null || true)"
  if [[ -n "$gid" && "$gid" != "null" ]]; then
    echo "    Group exists: $display_name ($gid)"
    printf '%s' "$gid"
    return 0
  fi

  local schemas='["urn:ietf:params:scim:schemas:core:2.0:Group","urn:ietf:params:scim:schemas:oracle:idcs:extension:group:Group"]'
  gid="$(idp_idcs group create \
    --endpoint "$IDP_DOMAIN_ENDPOINT" \
    --schemas "$schemas" \
    --display-name "$display_name" \
    --query 'data.id' \
    --raw-output)"
  echo "    Created group: $display_name ($gid)"
  printf '%s' "$gid"
}

idp_add_user_to_group() {
  local group_id="$1" user_id="$2"
  local schemas='[{"value":"urn:ietf:params:scim:api:messages:2.0:PatchOp","type":"string"}]'
  local ops
  ops="$(jq -nc --arg uid "$user_id" \
    '[{op:"add",path:"members",value:[{value:$uid,type:"User"}]}]')"
  idp_idcs group patch \
    --endpoint "$IDP_DOMAIN_ENDPOINT" \
    --group-id "$group_id" \
    --schemas "$schemas" \
    --operations "$ops" \
    >/dev/null 2>&1 || true
}

idp_create_user_with_password() {
  local email="$1" password="$2" given="$3" family="$4"
  local user_name
  user_name="$(idp_user_name_from_email "$email")"

  local existing
  existing="$(idp_idcs users list \
    --endpoint "$IDP_DOMAIN_ENDPOINT" \
    --filter "$(printf 'userName eq "%s"' "$user_name")" \
    --attributes id,userName \
    --query 'data.resources[0].id' \
    --raw-output 2>/dev/null || true)"

  if [[ -n "$existing" && "$existing" != "null" ]]; then
    IDP_USER_ID="$existing"
    echo "    User exists: $user_name ($IDP_USER_ID)"
  else
    local schemas='["urn:ietf:params:scim:schemas:core:2.0:User","urn:ietf:params:scim:schemas:oracle:idcs:extension:user:User"]'
    local name_json emails_json
    name_json="$(jq -nc --arg g "$given" --arg f "$family" '{givenName:$g,familyName:$f}')"
    emails_json="$(jq -nc --arg e "$email" '[{value:$e,type:"work",primary:true}]')"
    IDP_USER_ID="$(idp_idcs user create \
      --endpoint "$IDP_DOMAIN_ENDPOINT" \
      --schemas "$schemas" \
      --user-name "$user_name" \
      --name "$name_json" \
      --emails "$emails_json" \
      --user-type External \
      --active true \
      --query 'data.id' \
      --raw-output)"
    echo "    Created user: $user_name ($IDP_USER_ID)"
  fi

  local pw_schemas='["urn:ietf:params:scim:schemas:oracle:idcs:UserPasswordChanger"]'
  echo "    Setting password (admin reset)..."
  idp_idcs user-password-changer put \
    --endpoint "$IDP_DOMAIN_ENDPOINT" \
    --user-password-changer-id "$IDP_USER_ID" \
    --schemas "$pw_schemas" \
    --password "$password" \
    --bypass-notification true \
    --force \
    >/dev/null
  echo "    Password set"

  export IDP_USER_ID IDP_USER_NAME="$user_name"
}

idp_bootstrap_groups_and_user() {
  local password="$1"
  echo "==> Groups and dev user ($IDP_USER_EMAIL)"
  local g_cashier g_super g_admin
  g_cashier="$(idp_create_group "$IDP_CASHIER_GROUP")"
  g_super="$(idp_create_group "$IDP_SUPERVISOR_GROUP")"
  g_admin="$(idp_create_group "$IDP_ADMIN_GROUP")"

  idp_create_user_with_password "$IDP_USER_EMAIL" "$password" "$IDP_USER_GIVEN_NAME" "$IDP_USER_FAMILY_NAME"

  echo "    Adding user to groups..."
  idp_add_user_to_group "$g_cashier" "$IDP_USER_ID"
  idp_add_user_to_group "$g_super" "$IDP_USER_ID"
  idp_add_user_to_group "$g_admin" "$IDP_USER_ID"
  echo "    User added to: $IDP_CASHIER_GROUP, $IDP_SUPERVISOR_GROUP, $IDP_ADMIN_GROUP"
}
