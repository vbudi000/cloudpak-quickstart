#!/bin/bash
# Applying recipes on the primary repo
# Assumption: running from gitops-0-bootstrap; with gh auth login
source scripts/prep.sh
echo -e "${WHITE}Preparing ACE-apps recipe${NC}"

pushd ${OUTPUT_DIR}/gitops-0-bootstrap

echo "Enable ACE sample application"

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

#cat > services-recipe <<EOF
#artifactory.yaml
#sonarqube.yaml
#ci-scc.yaml
#EOF

cat > apps-recipe <<EOF
argocd\/ace\/cicd.yaml
argocd\/ace\/dev.yaml
argocd\/ace\/stage.yaml
argocd\/soapserver\/soapserver.yaml
EOF

cat infra-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/1-infra/kustomization.yaml" }' | bash
rm 0-bootstrap/single-cluster/1-infra/kustomization.yaml.bak

#cat services-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/2-services/kustomization.yaml" }' | bash
#rm 0-bootstrap/single-cluster/2-services/kustomization.yaml.bak

cat apps-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/3-apps/kustomization.yaml" }' | bash
rm 0-bootstrap/single-cluster/3-apps/kustomization.yaml.bak

#rm services-recipe
rm apps-recipe

git add .
git commit -m "Adding ACE apps resources"
git push origin

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

echo -e "${WHITE}Sample ACE application deployed${NC}"
