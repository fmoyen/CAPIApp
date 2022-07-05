#!/bin/bash

# oc get oauth.config.openshift.io/cluster -o json  > oauth_initial.json
# oc get oauth.config.openshift.io/cluster -o json | jq -r '.spec.identityProviders[]' > oauth_identityProviders_target.json

# Add an htpasswd definition
# jq '.spec.identityProviders[.spec.identityProviders | length] |= .+ {"htpasswd": {"fileData": {"name": "htpasswd-toto"}},"mappingMethod": "claifab","name": "myhtpasswd","type": "HTPasswd"}' oauth_target.json > test.json

# Test if identityProviders already provided
# jq -e -r '.spec.identityProvsdfiders' oauth_initial.json  > /dev/null
# echo $?
# 1
# jq -e -r '.spec.identityProviders' oauth_initial.json  > /dev/null
# echo $?
# 0

############################################################################################################################

oauthInitialConfig=./oauth_initial.json
oauthFinalConfig=./oauth_final.json

# Get the oauth initial (current) config in JSON format and write it in $oauthInitialConfig file
oc get oauth.config.openshift.io/cluster -o json > $oauthInitialConfig

# Test if the "opfh_htpasswd" identity provider is not already defined
if ! `jq -e -r '.spec.identityProviders' $oauthInitialConfig | grep -q "opfh_htpasswd"`; then

  # Add the definition of the opfh_htpasswd identity provider (after the potential other Identity Providers already defined) and write it in $oauthFinalConfig file
  # {it works even if .spec.identityProviders or even .spec does not exist)
  jq '.spec.identityProviders[.spec.identityProviders | length] |= .+ {"htpasswd": {"fileData": {"name": "opfh-htpass-secret"}},"mappingMethod": "claim","name": "opfh_htpasswd","type": "HTPasswd"}' $oauthInitialConfig > $oauthFinalConfig

  echo
  echo "##################################################################################################"
  echo "Pushing the new Identity Provider to the Authentication Cluster Operator (oauth)"
  echo
  echo "oc apply -f $oauthFinalConfig"
  oc apply -f $oauthFinalConfig

else
  echo
  echo "##################################################################################################"
  echo "Identity Provider \"opfh_htpasswd\" already defined"
  echo "Exiting..."
  echo
fi

