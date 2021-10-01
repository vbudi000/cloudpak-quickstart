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

if [[ -z ${RWX_STORAGECLASS} ]]; then
    echo "the CP4D recipe needed a Storage Class with RWX access mode"
    echo "RWX_STORAGECLASS=ocs-storagecluster-cephfs $0"
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

popd

pushd ${OUTPUT_DIR}/gitops-2-services

sed -i.bak 's/ibmc-file-gold-gid    /'${RWX_STORAGECLASS}'/g' instances/ibm-cpd-instance/ibmcpd-instance.yaml
rm instances/ibm-cpd-instance/ibmcpd-instance.yaml.bak

git add .
git commit -m "Adding CPD resources - changing storageClass"
git push origin

popd

echo -e -n "${WHITE}Waiting till ${LBLUE}CP4D ZenService${WHITE} is ready ${NC}"
sleep 20
cnt=$(oc -n tools get ZenService lite-cr -o jsonpath="{.status.zenStatus}")
while [[]"$cnt" != "Ready" ]; do
    sleep 60
    echo -n "."
    cnt=$(oc -n tools get ZenService lite-cr -o jsonpath="{.status.zenStatus}")
done
echo ""

zenURL=$(oc -n tools get ZenService lite-cr -o jsonpath="{.status.url}")
echo -e "${WHITE}CP4D recipe ready${NC} login at ${WHITE}https://${zenURL}${NC} "
echo -e "The admin password is:"
oc -n tools extract secret/admin-user-details --keys=initial_admin_password --to=-

echo -e -n "${WHITE}Completed CP4D recipe${NC}"
