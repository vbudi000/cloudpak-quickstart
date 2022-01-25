#!/bin/bash
# Applying recipes on the primary repo
# Assumption: running from gitops-0-bootstrap; with gh auth login

source cloudpak-quickstart/scripts/prep.sh

pushd ${OUTPUT_DIR}/gitops-0-bootstrap

echo -e "${WHITE}Applying CP4S - Threat Management recipe${NC}"

if [ -d "0-bootstrap/single-cluster" ]; then
    echo "Running from gitops-0-bootstrap"
else
    echo "You should run this recipe script from the gitops-0-bootstrap directory"
    exit 1
fi

if [[ -z ${RWX_STORAGECLASS} ]]; then
    echo "the CP4S recipe needed a Storage Class with RWX access mode"
    echo "RWX_STORAGECLASS=ocs-storagecluster-cephfs $0"
    exit 1
fi

cat > infra-recipe <<EOF
consolenotification.yaml
namespace-ibm-common-services.yaml
namespace-tools.yaml
EOF

cat > services-recipe <<EOF
ibm-cp4s-operator.yaml
ibm-cp4sthreatmanagements-instance.yaml
ibm-foundations.yaml
ibm-foundational-services-instance.yaml
ibm-catalogs.yaml
EOF

cat infra-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/1-infra/kustomization.yaml" }' | bash
rm 0-bootstrap/single-cluster/1-infra/kustomization.yaml.bak

cat services-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/2-services/kustomization.yaml" }' | bash
rm 0-bootstrap/single-cluster/2-services/kustomization.yaml.bak

rm infra-recipe
rm services-recipe

# git add .
# git commit -m "Adding CPD resources"
# git push origin

#popd

#pushd ${OUTPUT_DIR}/gitops-2-services

sed -i.bak 's/managed-nfs-storage/'${RWX_STORAGECLASS}'/g' 0-bootstrap/single-cluster/2-services/argocd/instances/ibm-cp4sthreatmanagements-instance.yaml
rm 0-bootstrap/single-cluster/2-services/argocd/instances/ibm-cp4sthreatmanagements-instance.yaml.bak

git add .
git commit -m "Adding CP4 Security - Threat Management resources and changing storageClass"
git push origin

popd

echo -e -n "${WHITE}Waiting till ${LBLUE}CP4S Threat Management${WHITE} is ready ${NC}"
sleep 20
cnt=$(oc get CP4SThreatManagement threatmgmt -n tools -o jsonpath='{.status.conditions[0].type}')
while [[ "$cnt" != "Success" ]]; do
    sleep 60
    echo -n "."
    cnt=$(oc get CP4SThreatManagement threatmgmt -n tools -o jsonpath='{.status.conditions[0].type}')
done
echo ""

echo -e -n "${WHITE}Deploying OpenLDAP ${NC}"
sleep 10

POD=$(oc get pod --no-headers -n tools -lrun=cp-serviceability | cut -d' ' -f1)
OS=$(uname | tr '[:upper:]' '[:lower:]')
oc cp -n tools $POD:/opt/bin/$OS/cpctl cpctl && chmod +x cpctl
./cpctl load -n tools
./cpctl tools deploy_openldap -n tools --token $(oc whoami -t) --ldap_usernames 'adminUser,user1,user2,user3' --ldap_password cloudpak

cp4sURL=$(oc get route isc-route-default --no-headers -n tools | awk '{print $2}')

echo -e "${WHITE}CP4S recipe ready${NC} login at ${WHITE}https://${cp4sURL}${NC} "
echo -e "The adminUser password is: cloudpak"


