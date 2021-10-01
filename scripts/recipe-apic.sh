#!/bin/bash
# Applying recipes on the primary repo
# Assumption: running from gitops-0-bootstrap; with gh auth login
source scripts/prep.sh
echo -e "${WHITE}Applying APIC recipe${NC}"

pushd ${OUTPUT_DIR}/gitops-0-bootstrap

echo "Enable APIC services"

if [[ -z ${RWX_STORAGECLASS} ]]; then
    echo "the APIC recipe needed a Storage Class with RWX access mode"
    echo "RWX_STORAGECLASS=ocs-storagecluster-cephfs $0"
    exit 1
fi

if [ -d "0-bootstrap/single-cluster" ]; then
    echo "Running from gitops-0-bootstrap"
else
    echo "You should run this recipe script from the gitops-0-bootstrap directory"
    exit 1
fi

cat > infra-recipe <<EOF
consolenotification.yaml
namespace-ibm-common-services.yaml
namespace-sealed-secrets.yaml
namespace-tools.yaml
EOF

cat > services-recipe <<EOF
ibm-apic-operator.yaml
ibm-apic-instance.yaml
ibm-datapower-operator.yaml
ibm-foundations.yaml
ibm-catalogs.yaml
sealed-secrets.yaml
EOF

cat infra-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/1-infra/kustomization.yaml" }' | bash
rm 0-bootstrap/single-cluster/1-infra/kustomization.yaml.bak

cat services-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/2-services/kustomization.yaml" }' | bash
rm 0-bootstrap/single-cluster/2-services/kustomization.yaml.bak

sed -i.bak 's/ibmc-block-gold/'${RWX_STORAGECLASS}'/g' 0-bootstrap/single-cluster/2-services/argocd/instances/ibm-apic-instance.yaml
rm 0-bootstrap/single-cluster/2-services/argocd/instances/ibm-platform-navigator-instance.yaml.bak

rm infra-recipe
rm services-recipe

git add .
git commit -m "Adding APIC resources"
git push origin


popd

sleep 60
echo -e -n "${WHITE}Waiting till ${LBLUE}API Connect cluser${WHITE} is Ready ${NC}"
cnt=$(oc get APIConnectCluster apic-cluster -n tools -o=jsonpath='{.status.phase}' 2>/dev/null)
while [ "$cnt" != "Ready" ]; do
    sleep 60
    echo -n "."
    cnt=$(oc get APIConnectCluster apic-cluster -n tools -o=jsonpath='{.status.phase}' 2>/dev/null)
done
echo ""

oc get APIConnectCluster apic-cluster -n tools
echo -e "${WHITE}APIC recipe ready${NC}"
