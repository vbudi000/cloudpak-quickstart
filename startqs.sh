#!/bin/bash

if [ -d "cloudpak-quickstart" ]; then
    echo "cloudpak-quickstart has been created "
    echo "it will not be re-cloned"
else 
    git clone https://github.com/vbudi000/cloudpak-quickstart
fi

###########################################################
# Change the following environment variables
###########################################################
export GIT_USER="gituser"
export GITHUB_TOKEN="ghp_key"
export GIT_ORG="git-org"
export IBM_ENTITLEMENT_KEY="entitlement-key"
export SEALED_SECRET_KEY_FILE=./shared-secret.yaml
export RWX_STORAGECLASS="ocs-storagecluster-cephfs"
###########################################################
# Start deployment of Quick Start - pick and choose the components to enable
###########################################################
export ADD_INFRA=yes
export ADD_MQ=yes
export ADD_MQAPPS=yes
export ADD_ACE=yes
export ADD_ACEAPPS=yes
###########################################################
# End environment variable changes
###########################################################
export GIT_TOKEN=${GITHUB_TOKEN}
export SOURCE_DIR=$(pwd)
export OUTPUT_DIR=gitops

if [ -f "install-config.yaml" ]; then
    echo "The install-config.yaml exists. Will create new OpenShift install."
else 
    oc cluster-info 
    if [ $? -ne 0 ]; then
        echo "You has neither install-config.yaml nor an existing openshift session. Exiting ...."
        exit 11
    fi 
fi

echo ${GITHUB_TOKEN} | gh auth login --with-token
./cloudpak-quickstart/scripts/quickstart.sh

exit