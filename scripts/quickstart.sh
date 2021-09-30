#!/usr/bin/env bash

## Bash color scheme
RED='\033[0;31m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
LBLUE='\033[1;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

## Set environment variables
if [[ -z ${SOURCE_DIR} ]]; then
    echo "You must specify a target directory that is not belonging to a GIT repository to run this"
    
    exit 1
else 
    git -C ${SOURCE_DIR} rev-parse 2>/dev/null
    if [ "$?" -eq 0 ]; then 
        echo "You must specify a target directory that is not belonging to a GIT repository to run this"
    else 
        echo "YES"
    fi
    pushd ${SOURCE_DIR}
fi

CP_DEFAULT_TARGET_NAMESPACE=${CP_DEFAULT_TARGET_NAMESPACE:-tools}
GITOPS_PROFILE=${GITOPS_PROFILE:-0-bootstrap/single-cluster}
GIT_BRANCH=${GIT_BRANCH:-master}
GIT_BASEURL=${GIT_BASEURL:-https://github.com}
GIT_GITOPS=${GIT_GITOPS:-multi-tenancy-gitops.git}
GIT_GITOPS_BRANCH=${GIT_GITOPS_BRANCH:-${GIT_BRANCH}}
GIT_GITOPS_INFRA=${GIT_GITOPS_INFRA:-multi-tenancy-gitops-infra.git}
GIT_GITOPS_INFRA_BRANCH=${GIT_GITOPS_INFRA_BRANCH:-${GIT_BRANCH}}
GIT_GITOPS_SERVICES=${GIT_GITOPS_SERVICES:-multi-tenancy-gitops-services.git}
GIT_GITOPS_SERVICES_BRANCH=${GIT_GITOPS_SERVICES_BRANCH:-${GIT_BRANCH}}
GIT_GITOPS_APPLICATIONS=${GIT_GITOPS_APPLICATIONS:-multi-tenancy-gitops-apps.git}
GIT_GITOPS_APPLICATIONS_BRANCH=${GIT_GITOPS_APPLICATIONS_BRANCH:-master}


pushd () {
    command pushd "$@" > /dev/null
}

popd () {
    command popd "$@" > /dev/null
}

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

[[ -n "${DEBUG:-}" ]] && set -x


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

if [[ -z ${RWX_STORAGECLASS} ]]; then
    echo "Please pass the environment variable RWX_STORAGECLASS for Platform Navigator"
    exit 1
fi

if [[ "${ADD_MQAPPS}" == "yes" ]]; then 
    if [[ -z ${GIT_USER} ]]; then
        echo "Please pass the environment variable GIT_USER"
        exit 1
    fi
    if [[ -z ${GIT_TOKEN} ]]; then
        echo "Please pass the environment variable GIT_TOKEN"
        exit 1
    fi
    ADD_MQ="yes"
fi
if [[ "${ADD_ACEAPPS}" == "yes" ]]; then 
    ADD_ACE="yes"
fi

gh_stat=$(gh auth status 2>&1 | grep "not logged" | wc -l)

if [[ "gh_stat" -gt 0 ]]; then
    echo "Not logged into GitHub gh cli"
    exit 1
fi

mkdir -p "${OUTPUT_DIR}"

create_cluster() {
    echo -e "${WHITE}Creating OpenShift cluster${NC}"

    openshift-install create cluster

    echo -e "${WHITE}Logging into OpenShift Cluster${NC}"
    pw=$(cat ${SOURCE_DIR}/auth/kubeadmin-password)
    api=$(cat ${SOURCE_DIR}/auth/kubeconfig | grep "server:" | cut -d" " -f6)

    oc login -u kubeadmin -p ${pw} ${api} --insecure-skip-tls-verify

    consoleURL=$(oc get route -n openshift-console console -o template --template='https://{{.spec.host}}')
    #open ${consoleURL}

    sleep 5
    echo -e "${WHITE}Login to OpenShift console as ${GREEN}kubeadmin${WHITE} using ${GREEN}${pw}${NC}"
    sleep 5
}

fork_repos() {
    echo -e "${WHITE}Forking GitOps repository${NC}"

    gh repo fork cloud-native-toolkit/multi-tenancy-gitops --clone=false --org ${GIT_ORG} --remote
    gh repo fork cloud-native-toolkit/multi-tenancy-gitops-infra --clone=false --org ${GIT_ORG} --remote
    gh repo fork cloud-native-toolkit/multi-tenancy-gitops-services --clone=false --org ${GIT_ORG} --remote
}

run_bootstrap() {
    echo -e "${WHITE}Invoking bootstrap script${NC}"
    curl -sfL https://raw.githubusercontent.com/cloud-native-toolkit/multi-tenancy-gitops/master/scripts/bootstrap.sh | DEBUG="" GIT_ORG=${GIT_ORG} OUTPUT_DIR=${OUTPUT_DIR} IBM_ENTITLEMENT_KEY=${IBM_ENTITLEMENT_KEY} bash

    gitopsURL=$(oc get route -n openshift-gitops openshift-gitops-cntk-server -o template --template='https://{{.spec.host}}')
    gitopsPWD=$(oc get secrets/openshift-gitops-cntk-cluster -o 'go-template={{index .data "admin.password"}}' -n openshift-gitops | base64 -d)

    echo -e "${WHITE}GitOps password:${NC} ${gitopsPWD}"
    #open ${gitopsURL}
}
#############################################################
# End of the common QuickStart module
#############################################################

#############################################################
# Start of the custom components
#############################################################

# Common component - 1 - infrastructure and storage

create_infra_components() {
    echo -e "${WHITE}Adding infrastructure components${NC}"
    
    pushd ${OUTPUT_DIR}/gitops-0-bootstrap
    
    source ./scripts/infra-mod.sh
    popd
    
    echo -e -n "${WHITE}Waiting till ${LBLUE}machines${WHITE} for infra and storage are available ${NC}"
    cnt=$(oc get machines -n openshift-machine-api | grep "storage\|infra" | grep "Running" | wc -l)
    while [ $cnt -lt 6 ]; do
        sleep 60
        echo -n "."
        cnt=$(oc get machines -n openshift-machine-api | grep "storage\|infra" | grep "Running" | wc -l)
    done
    echo ""
    
    oc get machines -n openshift-machine-api
    echo -e "${WHITE}Infrastructure and Storage nodes are Ready${NC}"
    
}

# Specific components - enabled using ENVIRONMENT variable
apply_mq_recipe() {
    echo -e "${WHITE}Applying MQ recipe${NC}"
    
    pushd ${OUTPUT_DIR}/gitops-0-bootstrap
    
    source ${SCRIPTDIR}/recipe-mq.sh
    
    popd
    
    echo -e -n "${WHITE}Waiting till ${LBLUE}integration-navigator-pn${WHITE} route is available ${NC}"
    cnt=$(oc get route -n tools 2>/dev/null | grep "integration-navigator-pn" | wc -l)
    while [ $cnt -eq 0 ]; do
        sleep 60
        echo -n "."
        cnt=$(oc get route -n tools 2>/dev/null  | grep "integration-navigator-pn" | wc -l)
    done
    echo ""
    
    oc get route -n tools integration-navigator-pn
    echo -e "${WHITE}MQ recipe ready${NC}"
    
}

apply_mqapps_recipe() {
    echo -e "${WHITE}Preparing mq-apps recipe${NC}"
    
    pushd ${OUTPUT_DIR}
    
    gh repo fork cloud-native-toolkit-demos/multi-tenancy-gitops-apps --clone --org ${GIT_ORG} --remote
    mv multi-tenancy-gitops-apps gitops-3-apps
    gh repo fork cloud-native-toolkit-demos/mq-infra --clone --org ${GIT_ORG} --remote
    gh repo fork cloud-native-toolkit-demos/mq-spring-app --clone --org ${GIT_ORG} --remote
    
    popd
    
    pushd ${OUTPUT_DIR}/gitops-0-bootstrap
    
    source ${SCRIPTDIR}/recipe-mqapps.sh
    
    popd
    
    echo -e -n "${WHITE}Waiting till ${LBLUE}artifactory-access${WHITE} secret is available ${NC}"
    cnt=$(oc get secret -n tools | grep "artifactory-access" | wc -l)
    while [ $cnt -eq 0 ]; do
        sleep 60
        echo -n "."
        cnt=$(oc get secret -n tools | grep "artifactory-access" | wc -l)
    done
    echo ""
    
    oc get secret -n tools artifactory-access
    
    echo -e "${WHITE}MQ application Bootstrap script${NC}"
    
    pushd ${OUTPUT_DIR}/gitops-3-apps/scripts
    
    alias exit=return
    source mq-bootstrap.sh
    unalias exit
    popd
    
    echo -e "${WHITE}Preparing Tekton pipelines${NC}"
    set +e
    cnt=$(oc get pipelines -n ci 2>/dev/null | grep "mq-infra-dev" | wc -l)
    while [ $cnt -eq 0 ]; do
        sleep 5
        echo -n "."
        cnt=$(oc get pipelines -n ci 2>/dev/null  | grep "mq-infra-dev" | wc -l)
    done
    echo ""
    sleep 30

    echo -e "${WHITE}Preparing Tekton pipelines${NC}"
    
    piperun=$(tkn pipeline start mq-infra-dev -n ci -p git-url="https://github.com/${GIT_ORG}/mq-infra.git" 2>/dev/null | grep pipelinerun)
    infra-plrun=$(echo $piperun | cut -d" " -f4)
    $piperun 2>/dev/null  >> mq-infra.log
    pipestat=$(oc get pipelinerun $infra-plrun -n ci --no-headers | cut -d" " -f7)

    if [[ $pipestat != "Succeeded" ]]; then
        oc get pipelinerun $infra-plrun -n ci
        return
    fi
    
    piperun=$(tkn pipeline start mq-spring-app-dev -n ci -p git-url="https://github.com/${GIT_ORG}/mq-spring-app.git" 2>/dev/null | grep pipelinerun)
    app-plrun=$(echo $piperun | cut -d" " -f4)
    $piperun 2>/dev/null >> mq-spring-app.log
    pipestat=$(oc get pipelinerun $app-plrun -n ci --no-headers | cut -d" " -f7)

    if [[ $pipestat != "Succeeded" ]]; then
        oc get pipelinerun $app-plrun -n ci
        return
    fi

    oc get pipelinerun -n ci
   
}

apply_ace_recipe() {
    echo -e "${WHITE}Applying ACE recipe${NC}"
    
    pushd ${OUTPUT_DIR}/gitops-0-bootstrap
    
    source ${SCRIPTDIR}/recipe-ace.sh
    
    popd
    
    echo -e -n "${WHITE}Waiting till ${LBLUE}integration-navigator-pn${WHITE} route is available ${NC}"
    cnt=$(oc get route -n tools 2>/dev/null | grep "integration-navigator-pn" | wc -l)
    while [ $cnt -eq 0 ]; do
        sleep 60
        echo -n "."
        cnt=$(oc get route -n tools 2>/dev/null  | grep "integration-navigator-pn" | wc -l)
    done
    echo ""
    
    oc get route -n tools integration-navigator-pn
    echo -e "${WHITE}ACE recipe ready${NC}"
    
}

apply_aceapps_recipe() {
    echo -e "${WHITE}Preparing ACE-apps recipe${NC}"
    
    pushd ${OUTPUT_DIR}
    
    gh repo fork cloud-native-toolkit-demos/multi-tenancy-gitops-apps --clone --org ${GIT_ORG} --remote
    mv multi-tenancy-gitops-apps gitops-3-apps
    gh repo fork cloud-native-toolkit-demos/ace-customer-details --clone --org ${GIT_ORG} --remote
    mv ace-customer-details src-ace-app-customer-details

    popd
    
    pushd ${OUTPUT_DIR}/gitops-0-bootstrap
    
    source ${SCRIPTDIR}/recipe-aceapps.sh
    
    popd

    echo -e "${WHITE}ACE application Bootstrap script${NC}"
    
    pushd ${OUTPUT_DIR}/gitops-3-apps/scripts
    
    alias exit=return
    source ace-bootstrap.sh
    unalias exit
    popd
    
    
    sleep 10
    
    echo -e "${WHITE}Preparing Tekton pipelines${NC}"
    set +e
    cnt=$(oc get pipelines -n ci 2>/dev/null | grep "ace-build-bar-promote-dev" | wc -l)
    while [ $cnt -eq 0 ]; do
        sleep 5
        echo -n "."
        cnt=$(oc get pipelines -n ci 2>/dev/null | grep "ace-build-bar-promote-dev" | wc -l)
    done
    echo ""
    sleep 30
    
    piperun=$(tkn pipeline start ace-build-bar-promote-dev -n ci -p is-source-repo-url="https://github.com/${GIT_ORG}/ace-customer-details" -p is-source-revision="master" --workspace name=shared-workspace,claimName=ace-bar-pvc 2>/dev/null | grep pipelinerun) 
    plrun=$(echo $piperun | cut -d" " -f4)
    $piperun 2>/dev/null  >> ace-build-bar-promote-dev.log
    
    pipestat=$(oc get pipelinerun $plrun -n ci --no-headers | cut -d" " -f7)

    if [[ $pipestat != "Succeeded" ]]; then
        oc get pipelinerun $plrun -n ci
        return
    fi
    oc rollout restart deploy/create-customer-details-rest-is -n dev

    piperun=$(tkn pipeline start ace-promote-dev-stage -n ci -p is-source-repo-url="https://github.com/${GIT_ORG}/ace-customer-details" -p source-env="dev" -p destination-env="staging" --workspace name=shared-workspace,claimName=ace-test-pvc 2>/dev/null | grep pipelinerun) 
    plrun=$(echo $piperun | cut -d" " -f4)
    $piperun 2>/dev/null >> ace-promote-dev-stage.log

    pipestat=$(oc get pipelinerun $plrun -n ci --no-headers | cut -d" " -f7)

    if [[ $pipestat != "Succeeded" ]]; then
        oc get pipelinerun $plrun -n ci
        return
    fi
    oc rollout restart deploy/create-customer-details-rest-is -n staging

}

# Specific components - enabled using ENVIRONMENT variable
apply_apic_recipe() {
    echo -e "${WHITE}Applying MQ recipe${NC}"
    
    pushd ${OUTPUT_DIR}/gitops-0-bootstrap
    
    source ${SCRIPTDIR}/recipe-apic.sh
    
    popd
    
    sleep 60
    echo -e -n "${WHITE}Waiting till ${LBLUE}API Connect cluser${WHITE} is Ready ${NC}"
    cnt=$(oc get APIConnectCluster apic-cluster -n tools -o=jsonpath='{.status.phase}')
    while [ "$cnt" != "Ready" ]; do
        sleep 60
        echo -n "."
        cnt=$(oc get APIConnectCluster apic-cluster -n tools -o=jsonpath='{.status.phase}')
    done
    echo ""
    
    oc get APIConnectCluster apic-cluster -n tools
    echo -e "${WHITE}APIC recipe ready${NC}"
    
}


if [ -f "${SOURCE_DIR}/install-config.yaml" ]; then
    echo "The install-config.yaml is found"
    create_cluster
    ADD_INFRA="yes"
else
    ADD_INFRA=""
fi

oc_ready=$(oc whoami 2>&1 | grep Error | wc -l)
if [[ "oc_ready" -gt 0 ]]; then
    echo "Not logged into OpenShift cli"
    exit 1
fi

#fork_repos

run_bootstrap

if [[ "${ADD_INFRA}" == "yes" ]]; then 
    create_infra_components
fi

if [[ "${ADD_MQ}" == "yes" ]]; then 
    apply_mq_recipe
    if [[ "${ADD_MQAPPS}" == "yes" ]]; then 
        apply_mqapps_recipe
    fi
fi

if [[ "${ADD_ACE}" == "yes" ]]; then 
    apply_ace_recipe
    if [[ "${ADD_ACEAPPS}" == "yes" ]]; then 
        apply_aceapps_recipe
    fi
fi

if [[ "${ADD_APIC}" == "yes" ]]; then 
    apply_apic_recipe
    if [[ "${ADD_APICAPPS}" == "yes" ]]; then 
        apply_apicapps_recipe
    fi
fi

popd