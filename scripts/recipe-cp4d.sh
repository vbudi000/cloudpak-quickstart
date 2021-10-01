!/bin/bash
# Applying recipes on the primary repo
# Assumption: running from gitops-0-bootstrap; with gh auth login

source scripts/prep.sh

pushd ${OUTPUT_DIR}/gitops-0-bootstrap

echo -e "${WHITE}Applying CP4D recipe${NC}"

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
EOF

cat > services-recipe <<EOF
ibm-cpd-scheduling-operator.yaml
ibm-cpd-platform-operator.yaml
ibm-cpd-instance.yaml
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
git commit -m "Adding CPD resources"
git push origin

echo -e -n "${WHITE}Waiting till ${LBLUE} -- ${WHITE} ${NC}"
cnt=$(echo "0")
while [ $cnt -eq 0 ]; do
    sleep 60
    echo -n "."
    cnt=$(echo "1")
done
echo ""

oc get route -n tools integration-navigator-pn
echo -e "${WHITE}CP4D recipe ready${NC}"

popd