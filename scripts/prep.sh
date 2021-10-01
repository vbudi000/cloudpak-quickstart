#!/bin/bash

## Bash color scheme
RED='\033[0;31m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
LBLUE='\033[1;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color


if [[ -z ${GIT_ORG} ]]; then
    echo "We recommend to create a new github organization for all your gitops repos"
    echo "Setup a new organization on github https://docs.github.com/en/organizations/collaborating-with-groups-in-organizations/creating-a-new-organization-from-scratch"
    echo "Please set the environment variable GIT_ORG when running the script like:"
    echo "GIT_ORG=acme-org OUTPUT_DIR=gitops-production ./scripts/bootstrap.sh"
    
    exit 1
fi

if [[ -z ${OUTPUT_DIR} ]]; then
    echo "Please set the environment variable OUTPUT_DIR when running the script like:"
    echo "GIT_ORG=acme-org OUTPUT_DIR=gitops-production ./scripts/bootstrap.sh"
    
    exit 1
fi

if [[ -z ${IBM_ENTITLEMENT_KEY} ]]; then
    echo "Please pass the environment variable IBM_ENTITLEMENT_KEY"
    exit 1
fi
