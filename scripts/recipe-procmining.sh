#!/bin/bash
# Applying recipes on the primary repo
# Assumption: running from gitops-0-bootstrap; with gh auth login

source cloudpak-quickstart/scripts/prep.sh

pushd ${OUTPUT_DIR}/gitops-0-bootstrap

echo -e "${WHITE}Applying Process Mining recipe${NC}"

if [ -d "0-bootstrap/single-cluster" ]; then
    echo "Running from gitops-0-bootstrap"
else
    echo "You should run this recipe script from the gitops-0-bootstrap directory"
    exit 1
fi

cat > infra-recipe <<EOF
consolenotification.yaml
namespace-ibm-common-services.yaml
namespace-tools.yaml
namespace-sealed-secrets.yaml
namespace-ci.yaml
namespace-dev.yaml
namespace-tools.yaml
namespace-staging.yaml
namespace-prod.yaml
EOF

cat > services-recipe <<EOF
ibm-process-mining-operator.yaml
ibm-process-mining-instance.yaml
ibm-automation-foundation-core-operator.yaml
ibm-foundations.yaml
ibm-foundational-services-instance.yaml
ibm-catalogs.yaml
sealed-secrets.yaml
EOF

cat infra-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/1-infra/kustomization.yaml" }' | bash
rm 0-bootstrap/single-cluster/1-infra/kustomization.yaml.bak

cat services-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/2-services/kustomization.yaml" }' | bash
rm 0-bootstrap/single-cluster/2-services/kustomization.yaml.bak

rm infra-recipe
rm services-recipe

git add .
git commit -m "Adding Process Mining resources"
git push origin

popd

echo -e -n "${WHITE}Waiting till ${LBLUE}Process mining${WHITE} is available ${NC}"
pmuri=$( oc get processmining -n tools processmining -o jsonpath='{.status.components.processmining.endpoints[0].uri}' 2>/dev/null)
while [[ $pmuri == "" ]]; do
    sleep 60
    echo -n "."
    pmuri=$( oc get processmining -n tools processmining -o jsonpath='{.status.components.processmining.endpoints[0].uri}' 2>/dev/null)
done
echo ""

echo -e "${WHITE}Process Mining is ready at ${LBLUE}https://${pmuri}${NC}"
