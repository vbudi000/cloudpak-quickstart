#!/usr/bin/env bash

source prep.sh

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

fork_gh_repo() {
    repoorg=$1
    reponame=$2
    dirname=$3
    pushd ${OUTPUT_DIR}
    echo -e "${WHITE}Forking GitOps repository \"${reponame}\"${NC}"
    GHREPONAME=$(gh api /repos/${GIT_ORG}/${reponame} -q .name || true)
    if [[ ! ${GHREPONAME} = "${reponame}" ]]; then
        echo "Fork not found, creating fork and cloning"
        gh repo fork ${repoorg}/${reponame} --clone --org ${GIT_ORG} --remote
        if [[ -z "${dirname} " ]]; then
            dirname=${reponame}
        else
            mv ${reponame} ${dirname}
        fi
        elif [[ ! -d ${dirname} ]]; then
        echo "Fork found, repo not cloned, cloning repo"
        gh repo clone ${GIT_ORG}/${reponame} ${dirname}
    fi
    cd ${dirname}
    git remote set-url --push upstream no_push
    git checkout ${GIT_BRANCH} || git checkout --track origin/${GIT_BRANCH}
    cd ..
    popd
}

fork_repos() {
    echo -e "${WHITE}Forking GitOps repository ${reponame}${NC}"
    
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
    source ${SCRIPTDIR}/recipe-mq.sh
}

apply_mqapps_recipe() {
    pushd ${OUTPUT_DIR}
    
    fork_gh_repo cloud-native-toolkit-demos multi-tenancy-gitops-apps gitops-3-apps
    fork_gh_repo cloud-native-toolkit-demos mq-infra 
    fork_gh_repo cloud-native-toolkit-demos mq-spring-app 
    
    popd
    
    source ${SCRIPTDIR}/recipe-mqapps.sh
    
}

apply_ace_recipe() {
    source ${SCRIPTDIR}/recipe-ace.sh
}

apply_aceapps_recipe() {
    pushd ${OUTPUT_DIR}
    
    fork_gh_repo cloud-native-toolkit-demos multi-tenancy-gitops-apps gitops-3-apps
    fork_gh_repo cloud-native-toolkit-demos ace-customer-details src-ace-app-customer-details
    
    popd
    
    source ${SCRIPTDIR}/recipe-aceapps.sh
}

# Specific components - enabled using ENVIRONMENT variable
apply_apic_recipe() {
    source ${SCRIPTDIR}/recipe-apic.sh
}

apply_apicapps_recipe() {
    echo "TBD ${WHITE} Not implemented ${NC}"
}

apply_cpd_recipe() {
    source ${SCRIPTDIR}/recipe-cp4d.sh
}

apply_cpdsample_recipe() {
    # source ${SCRIPTDIR}/recipe-cp4dsample.sh
    echo "TBD ${WHITE} Not implemented ${NC}"
}

apply_procmining_recipe() {
    echo "TBD ${WHITE} Not implemented ${NC}"
}

apply_procminingapps_recipe() {
    echo "TBD ${WHITE} Not implemented ${NC}"
}

apply_ads_recipe() {
    echo "TBD ${WHITE} Not implemented ${NC}"
}

apply_adsapps_recipe() {
    echo "TBD ${WHITE} Not implemented ${NC}"
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
    #if [[ "${ADD_APICAPPS}" == "yes" ]]; then
    #    apply_apicapps_recipe
    #fi
fi

if [[ "${ADD_CPD}" == "yes" ]]; then
    apply_cpd_recipe
    #if [[ "${ADD_CPDSAMPLE}" == "yes" ]]; then
    #    apply_cpdsample_recipe
    #fi
fi


if [[ "${ADD_PROCMINING}" == "yes" ]]; then
    apply_procmining_recipe
    #if [[ "${ADD_PROCMININGAPPS}" == "yes" ]]; then
    #    apply_procminingapps_recipe
    #fi
fi


if [[ "${ADD_ADS}" == "yes" ]]; then
    apply_ads_recipe
    #if [[ "${ADD_ADSAPPS}" == "yes" ]]; then
    #    apply_adsapps_recipe
    #fi
fi

popd