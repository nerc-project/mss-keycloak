#!/bin/bash
set -x
REALM=${REALM:-mss}
CLI=${CLI:-/opt/jboss/keycloak/bin/kcadm.sh}
IDP_MAPPER_CONFIG='{"identityProviderAlias":"cilogon","config":{"syncMode":"IMPORT","claim":"idp_name","user.attribute":"cilogon_idp_name"},"name":"cilogon_idp_name","identityProviderMapper":"oidc-user-attribute-idp-mapper"}'
REDIRECTOR_CONFIG='{"config":{"defaultProvider":"cilogon"},"alias":"cilogon_auth_config"}'

function kcadm() {
  $CLI "$@" --config /tmp/kcadm.conf
}

function wait_for_keycloak_start() {
  # Wait until keycloak api is up
  until kcadm config credentials --server http://localhost:8080/auth --realm master --client admin-cli --user "${KEYCLOAK_USER}" --password "${KEYCLOAK_PASSWORD}"
  do
    echo 'nerc-setup.sh: waiting for keycloak to start...'
    sleep 5
  done
  sleep 5
}


function wait_for_realm_and_client() {
  until kcadm get "realms/${REALM}/clients" -q "clientId=${1}" --fields id --format csv --noquotes
  do
    echo "nerc-setup.sh: waiting for realm ${REALM} and client ${1} to become available..."
    sleep 5
  done
  sleep 5
}

function setup_regapp() {
  CLIENT_ID=$1

  # Add all realm management roles (mappings) to client service account
  CLIENT_KCID=$(kcadm get realms/${REALM}/clients -q clientId=$CLIENT_ID --fields id --format csv --noquotes)
  SVC_ACCT_USER_KCID=$(kcadm get realms/${REALM}/clients/$CLIENT_KCID/service-account-user --fields id --format csv --noquotes)
  REALM_MGMT_CLIENT_KCID=$(kcadm get realms/${REALM}/clients -q clientId=realm-management --fields id --format csv --noquotes)
  ALLROLES=$(kcadm get realms/${REALM}/clients/${REALM_MGMT_CLIENT_KCID}/roles --fields id,name)
  kcadm create realms/${REALM}/users/${SVC_ACCT_USER_KCID}/role-mappings/clients/${REALM_MGMT_CLIENT_KCID} --body "$ALLROLES"

  # Add the idp mapper for cilogon
  kcadm create realms/${REALM}/identity-provider/instances/cilogon/mappers --body "$IDP_MAPPER_CONFIG"

  # Update cilogon clientId and clientSecret
  # sed replace needs to be clean of \ / and &
  # jq would be much better but not available in stock image
  CISEC=$(printf '%s\n' "$CILOGON_CLIENT_SECRET" | sed -e 's/[\/&]/\\&/g')
  CIID=$(printf '%s\n' "$CILOGON_CLIENT_ID" | sed -e 's/[\/&]/\\&/g')
  CILOGON_IDP_REP=$(kcadm get realms/${REALM}/identity-provider/instances/cilogon | sed -e "s/\"clientSecret.*,/\"clientSecret\": \"$CISEC\",/g" -e "s/\"clientId.*,/\"clientId\": \"$CIID\",/g")
  kcadm update realms/${REALM}/identity-provider/instances/cilogon --body "$CILOGON_IDP_REP"

  # Configure the idp redirector execution in the browser flow to go directly
  # to cilogon
  REDIRECTOR_KCID=$(kcadm get realms/${REALM}/authentication/flows/browser/executions  --format csv --fields id,displayName --noquotes | sed -n 's/\(.*\),Identity Provider Redirector.*/\1/p')
  kcadm create realms/${REALM}/authentication/executions/$REDIRECTOR_KCID/config --body "$REDIRECTOR_CONFIG"
}

function setup_coldfront() {
  kcadm create groups -r "${REALM}" -b '{ "name": "pi" }'
}

# Called on startup with no args, must background self so
# as not to block startup while wating for startup...
if [ $# -eq 0 ]; then
  CMD=$(realpath $0)
  $CMD regapp coldfront & disown
else
  # Called with an arg, this is the backgrounded invocation

  wait_for_keycloak_start

  for client in $*;
  do
    wait_for_realm_and_client "${client}"
    setup_${client} "${client}"
  done
fi
