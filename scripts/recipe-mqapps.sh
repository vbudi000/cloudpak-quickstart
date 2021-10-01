#!/bin/bash
# Applying recipes on the primary repo
# Assumption: running from gitops-0-bootstrap; with gh auth login

source scripts/prep.sh

echo -e "${WHITE}Preparing mq-apps recipe${NC}"

pushd ${OUTPUT_DIR}/gitops-0-bootstrap
echo "Enable MQ sample application"

if [ -d "0-bootstrap/single-cluster" ]; then
    echo "Running from gitops-0-bootstrap"
else
    echo "You should run this recipe script from the gitops-0-bootstrap directory"
    exit 1
fi

cat > infra-recipe <<EOF
namespace-ci.yaml
namespace-dev.yaml
namespace-staging.yaml
namespace-prod.yaml
EOF

cat > services-recipe <<EOF
artifactory.yaml
sonarqube.yaml
EOF
#ci-scc.yaml

cat > apps-recipe <<EOF
mq\/cicd.yaml
mq\/dev.yaml
EOF

cat infra-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/1-infra/kustomization.yaml" }' | bash
rm 0-bootstrap/single-cluster/1-infra/kustomization.yaml.bak

cat services-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/2-services/kustomization.yaml" }' | bash
rm 0-bootstrap/single-cluster/2-services/kustomization.yaml.bak

cat apps-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/3-apps/kustomization.yaml" }' | bash
rm 0-bootstrap/single-cluster/3-apps/kustomization.yaml.bak

rm services-recipe
rm apps-recipe

git add .
git commit -m "Adding MQ resources"
git push origin

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
echo "Pipeline output is stored in mq-infra.log"

if [[ $pipestat != "Succeeded" ]]; then
    oc get pipelinerun $infra-plrun -n ci
    return
fi

piperun=$(tkn pipeline start mq-spring-app-dev -n ci -p git-url="https://github.com/${GIT_ORG}/mq-spring-app.git" 2>/dev/null | grep pipelinerun)
app-plrun=$(echo $piperun | cut -d" " -f4)
$piperun 2>/dev/null >> mq-spring-app.log
pipestat=$(oc get pipelinerun $app-plrun -n ci --no-headers | cut -d" " -f7)
echo "Pipeline output is stored in mq-spring-app.log"

if [[ $pipestat != "Succeeded" ]]; then
    oc get pipelinerun $app-plrun -n ci
    return
fi

oc get pipelinerun -n ci

echo -e "${WHITE}Sample MQ application deployed${NC}"
