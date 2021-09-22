#!/usr/bin/env bash

DEBUG=""

## Bash color scheme
RED='\033[0;31m'
WHITE='\033[1;37m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
LBLUE='\033[1;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

## Set environment variables

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
GIT_GITOPS_APPLICATIONS_BRANCH=${GIT_GITOPS_APPLICATIONS_BRANCH:-ocp47-2021-2}


pushd () {
    command pushd "$@" > /dev/null
}

popd () {
    command popd "$@" > /dev/null
}

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

SOURCE_DIR=${SOURCE_DIR:-.}
if [ -f "${SOURCE_DIR}/install-config.yaml" ]; then
    echo "The install-config.yaml is found"
else
    echo "No install-config.yaml"
    exit 1
fi

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

if [[ -z ${GIT_USER} ]]; then
    echo "Please pass the environment variable GIT_USER"
    exit 1
fi
if [[ -z ${GIT_TOKEN} ]]; then
    echo "Please pass the environment variable GIT_TOKEN"
    exit 1
fi


mkdir -p "${OUTPUT_DIR}"
echo -e "${WHITE}Creating OpenShift cluster${NC}"
CUR_PATH="${PWD##*/}"
echo -e "[${RED}${CUR_PATH}${NC}] $ openshift-install create cluster"
openshift-install create cluster

echo -e "${WHITE}Logging into OpenShift Cluster${NC}"
pw=$(cat ${SOURCE_DIR}/auth/kubeadmin-password)
api=$(cat ${SOURCE_DIR}/auth/kubeconfig | grep "server:" | cut -d" " -f6)
echo -e "[${RED}${CUR_PATH}${NC}] $ oc login -u kubeadmin -p ${pw} ${api} --insecure-skip-tls-verify"
oc login -u kubeadmin -p ${pw} ${api} --insecure-skip-tls-verify

consoleURL=$(oc get route -n openshift-console console -o template --template='https://{{.spec.host}}')
#open ${consoleURL}

sleep 5
echo -e "${WHITE}Login to OpenShift console as ${GREEN}kubeadmin${WHITE} using ${GREEN}${pw}${NC}"
sleep 5

echo -e "${WHITE}Forking GitOps repository${NC}"

echo -e "[${RED}${CUR_PATH}${NC}] $ gh repo fork vbudi000/multi-tenancy-gitops --clone false --org ${GIT_ORG} --remote"
gh repo fork vbudi000/multi-tenancy-gitops --clone=false --org ${GIT_ORG} --remote
echo -e "[${RED}${CUR_PATH}${NC}] $ gh repo fork vbudi000/multi-tenancy-gitops-infra --clone false --org ${GIT_ORG} --remote"
gh repo fork vbudi000/multi-tenancy-gitops-infra --clone=false --org ${GIT_ORG} --remote
echo -e "[${RED}${CUR_PATH}${NC}] $ gh repo fork vbudi000/multi-tenancy-gitops-services --clone false --org ${GIT_ORG} --remote"
gh repo fork vbudi000/multi-tenancy-gitops-services --clone=false --org ${GIT_ORG} --remote

echo -e "${WHITE}Invoking bootstrap script${NC}"
echo -e "[${RED}${CUR_PATH}${NC}] $ source bootstrap.sh"
curl -sfL https://raw.githubusercontent.com/vbudi000/multi-tenancy-gitops/master/scripts/bootstrap.sh | DEBUG="" GIT_ORG=${GIT_ORG} OUTPUT_DIR=${OUTPUT_DIR} IBM_ENTITLEMENT_KEY=${IBM_ENTITLEMENT_KEY} bash 

gitopsURL=$(oc get route -n openshift-gitops openshift-gitops-cntk-server -o template --template='https://{{.spec.host}}')
gitopsPWD=$(oc get secrets/openshift-gitops-cntk-cluster -o 'go-template={{index .data "admin.password"}}' -n openshift-gitops | base64 -d)

echo -e "${WHITE}GitOps password:${NC} ${gitopsPWD}"
#open ${gitopsURL}
echo -e "${WHITE}Adding infrastructure components${NC}"

pushd ${OUTPUT_DIR}/gitops-0-bootstrap
echo -e "[${RED}${CUR_PATH}${NC}] $ cd ${OUTPUT_DIR}/gitops-0-bootstrap"
CUR_PATH="${PWD##*/}"
echo -e "[${RED}${CUR_PATH}${NC}] $ source ./scripts/infra-mod.sh"

source ./scripts/infra-mod.sh
popd
echo -e "[${RED}${CUR_PATH}${NC}] $ cd -"
CUR_PATH="${PWD##*/}"

echo -e -n "${WHITE}Waiting till ${LBLUE}machines${WHITE} for infra and storage are available ${NC}"
cnt=$(oc get machines -n openshift-machine-api | grep "storage\|infra" | grep "Running" | wc -l)
while [ $cnt -lt 6 ]; do
  sleep 60
  echo -n "."
  cnt=$(oc get machines -n openshift-machine-api | grep "storage\|infra" | grep "Running" | wc -l)
done
echo ""

echo -e "[${RED}${CUR_PATH}${NC}] $ oc get machines -n openshift-machine-api"
oc get machines -n openshift-machine-api

echo -e "${WHITE}Applying recipes${NC}"

pushd ${OUTPUT_DIR}/gitops-0-bootstrap
echo -e "[${RED}${CUR_PATH}${NC}] $ cd ${OUTPUT_DIR}/gitops-0-bootstrap"
CUR_PATH="${PWD##*/}"
echo -e "[${RED}${CUR_PATH}${NC}] $ source ./scripts/recipe-mq.sh"

source ./scripts/recipe-mq.sh

popd
echo -e "[${RED}${CUR_PATH}${NC}] $ cd -"
CUR_PATH="${PWD##*/}"

echo -e -n "${WHITE}Waiting till ${LBLUE}integration-navigator-pn${WHITE} route is available ${NC}"
cnt=$(oc get route -n tools 2>/dev/null | grep "integration-navigator-pn" | wc -l)
while [ $cnt -eq 0 ]; do
  sleep 60
  echo -n "."
  cnt=$(oc get route -n tools 2>/dev/null  | grep "integration-navigator-pn" | wc -l)
done
echo ""

echo -e "[${RED}${CUR_PATH}${NC}] $ oc get route -n tools integration-navigator-pn"

oc get route -n tools integration-navigator-pn

echo -e "${WHITE}Preparing additional repos for sample applications${NC}"

pushd ${OUTPUT_DIR}
echo -e "[${RED}${CUR_PATH}${NC}] $ cd ${OUTPUT_DIR}"
CUR_PATH="${PWD##*/}"

echo -e "[${RED}${CUR_PATH}${NC}] $ gh repo fork cloud-native-toolkit-demos/multi-tenancy-gitops-apps --clone --org ${GIT_ORG} --remote"
gh repo fork vbudi000/multi-tenancy-gitops-apps --clone --org ${GIT_ORG} --remote
echo -e "[${RED}${CUR_PATH}${NC}] $ mv multi-tenancy-gitops-apps gitops-3-apps"
mv multi-tenancy-gitops-apps gitops-3-apps
echo -e "[${RED}${CUR_PATH}${NC}] $ gh repo fork cloud-native-toolkit-demos/mq-infra --clone --org ${GIT_ORG} --remote"
gh repo fork cloud-native-toolkit-demos/mq-infra --clone --org ${GIT_ORG} --remote
echo -e "[${RED}${CUR_PATH}${NC}] $ gh repo fork cloud-native-toolkit-demos/mq-spring-app --clone --org ${GIT_ORG} --remote"
gh repo fork cloud-native-toolkit-demos/mq-spring-app --clone --org ${GIT_ORG} --remote

popd
echo -e "[${RED}${CUR_PATH}${NC}] $ cd -"
CUR_PATH="${PWD##*/}"

pushd ${OUTPUT_DIR}/gitops-0-bootstrap
echo -e "[${RED}${CUR_PATH}${NC}] $ cd ${OUTPUT_DIR}/gitops-0-bootstrap"
CUR_PATH="${PWD##*/}"
echo -e "[${RED}${CUR_PATH}${NC}] $ source ./scripts/recipe-mqapps.sh"

source ./scripts/recipe-mqapps.sh

popd
echo -e "[${RED}${CUR_PATH}${NC}] $ cd -"
CUR_PATH="${PWD##*/}"

echo -e -n "${WHITE}Waiting till ${LBLUE}artifactory-access${WHITE} secret is available ${NC}"
cnt=$(oc get secret -n tools | grep "artifactory-access" | wc -l)
while [ $cnt -eq 0 ]; do
  sleep 60
  echo -n "."
  cnt=$(oc get secret -n tools | grep "artifactory-access" | wc -l)
done
echo ""

echo -e "[${RED}${CUR_PATH}${NC}] $ oc get secret -n tools artifactory-access"
oc get secret -n tools artifactory-access

echo -e "${WHITE}Fixing sealed secrets${NC}"

pushd ${OUTPUT_DIR}/gitops-3-apps/scripts
echo -e "[${RED}${CUR_PATH}${NC}] $ cd ${OUTPUT_DIR}/gitops-3-apps/scripts"
CUR_PATH="${PWD##*/}"
alias exit=return
echo -e "[${RED}${CUR_PATH}${NC}] $ source mq-kubeseal.sh"
source mq-kubeseal.sh
unalias exit
popd
echo -e "[${RED}${CUR_PATH}${NC}] $ cd -"
CUR_PATH="${PWD##*/}"

echo -e "${WHITE}Preparing Tekton pipelines${NC}"

echo -e "[${RED}${CUR_PATH}${NC}] $ tkn pipeline start mq-infra-dev -n ci -p git-url=\"https://github.com/${GIT_ORG}/mq-infra.git\""

tkn pipeline start mq-infra-dev -n ci -p git-url="https://github.com/${GIT_ORG}/mq-infra.git"
plrun=$(tkn pipelinerun list -n ci | grep mq-infra-dev | cut -d" " -f1)
sleep 5
echo -e -n "${WHITE}Waiting till ${LBLUE}mq-infra-dev${WHITE} done ${NC}"
plactive=$(tkn pr list -n ci | grep "${plrun}" | grep "Running" | wc -l)
while [ $plactive -gt 0 ]; do
  sleep 60
  echo -n "."
  plactive=$(tkn pr list -n ci | grep "${plrun}" | grep "Running" | wc -l)
done
echo ""
echo -e "[${RED}${CUR_PATH}${NC}] $ tkn pipelinerun list -n ci"
tkn pipelinerun list -n ci

echo -e "[${RED}${CUR_PATH}${NC}] $ tkn pipeline start mq-spring-app-dev -n ci -p git-url=\"https://github.com/${GIT_ORG}/mq-spring-app.git\""

tkn pipeline start mq-spring-app-dev -n ci -p git-url="https://github.com/${GIT_ORG}/mq-spring-app.git"
plrun=$(tkn pipelinerun list -n ci | grep mq-spring-app-dev | cut -d" " -f1)
sleep 5
echo -e -n "${WHITE}Waiting till ${LBLUE}mq-spring-app-dev${WHITE} done ${NC}"
plactive=$(tkn pr list -n ci | grep "${plrun}" | grep "Running" | wc -l)
while [ $plactive -gt 0 ]; do
  sleep 60
  echo -n "."
  plactive=$(tkn pr list -n ci | grep "${plrun}" | grep "Running" | wc -l)
done
echo ""
echo -e "[${RED}${CUR_PATH}${NC}] $ tkn pipelinerun list -n ci"
tkn pipelinerun list -n ci

