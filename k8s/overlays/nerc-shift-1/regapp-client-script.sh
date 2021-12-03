#!/bin/bash
CLI=/opt/jboss/keycloak/bin/kcadm.sh
REGAPP_CLIENT_ID=regapp
IDP_MAPPER_CONFIG='{"identityProviderAlias":"cilogon","config":{"syncMode":"IMPORT","claim":"idp_name","user.attribute":"cilogon_idp_name"},"name":"cilogon_idp_name","identityProviderMapper":"oidc-user-attribute-idp-mapper"}'
REDIRECTOR_CONFIG='{"config":{"defaultProvider":"cilogon"},"alias":"cilogon_auth_config"}'

# Called on startup with no args, must background self so
# as not to block startup while wating for startup...
if [ $# -eq 0 ]; then
    CMD=$(realpath $0)
    $CMD foo & disown
else
    # Called with an arg, this is the backgrounded invocation

    # Wait until keycloak api is up
    until $CLI config credentials --server http://localhost:8080/auth --realm master --client admin-cli --user $KEYCLOAK_USER --password $KEYCLOAK_PASSWORD
    do
        echo regapp-client-script waiting for server to start...
        sleep 5
    done

    # Now wait until realm and client are viable
    sleep 5
    until $CLI get realms/mss/clients -q clientId=$REGAPP_CLIENT_ID --fields id --format csv --noquotes
    do
        echo regapp-client-script waiting for realm and client to become available...
        sleep 5
    done 

    # Add all realm management roles (mappings) to regapp service account
    sleep 5
    REGAPP_CLIENT_KCID=$($CLI get realms/mss/clients -q clientId=$REGAPP_CLIENT_ID --fields id --format csv --noquotes)
    SVC_ACCT_USER_KCID=$($CLI get realms/mss/clients/$REGAPP_CLIENT_KCID/service-account-user --fields id --format csv --noquotes)
    REALM_MGMT_CLIENT_KCID=$($CLI get realms/mss/clients -q clientId=realm-management --fields id --format csv --noquotes)
    ALLROLES=$($CLI get realms/mss/clients/$REALM_MGMT_CLIENT_KCID/roles --fields id,name)
    $CLI create realms/mss/users/$SVC_ACCT_USER_KCID/role-mappings/clients/$REALM_MGMT_CLIENT_KCID --body "$ALLROLES"

    # Add the idp mapper for cilogon
    $CLI create realms/mss/identity-provider/instances/cilogon/mappers --body $IDP_MAPPER_CONFIG

    # Update cilogon clientId and clientSecret
    # sed replace needs to be clean of \ / and &
    CISEC=$(printf '%s\n' "$CILOGON_CLIENT_SECRET" | sed -e 's/[\/&]/\\&/g')
    CIID=$(printf '%s\n' "$CILOGON_CLIENT_ID" | sed -e 's/[\/&]/\\&/g')
    CILOGON_IDP_REP=$($CLI get realms/mss/identity-provider/instances/cilogon | sed -e "s/\"clientSecret.*,/\"clientSecret\": \"$CISEC\",/g" -e "s/\"clientId.*,/\"clientId\": \"$CIID\",/g")
    $CLI update realms/mss/identity-provider/instances/cilogon --body "$CILOGON_IDP_REP"


    # Configure the idp redirector execution in the browser flow to go directly
    # to cilogon
    REDIRECTOR_KCID=$($CLI get realms/mss/authentication/flows/browser/executions  --format csv --fields id,displayName --noquotes | sed -n 's/\(.*\),Identity Provider Redirector.*/\1/p')
    $CLI create realms/mss/authentication/executions/$REDIRECTOR_KCID/config --body $REDIRECTOR_CONFIG

    # Example update - note this command cannot change client id!!
    # $CLI update realms/mss/clients/$REGAPP_CLIENT_ID  -s description=supersuccesssuperdude
fi