#!/bin/bash
# Applying recipes on the primary repo
# Assumption: running from gitops-0-bootstrap; with gh auth login
echo "Enable ACE services"

if [[ -z ${RWX_STORAGECLASS} ]]; then
  echo "the MQ recipe needed a Storage Class with RWX access mode"
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
namespace-ci.yaml
namespace-dev.yaml
namespace-staging.yaml
namespace-prod.yaml
namespace-sealed-secrets.yaml
namespace-tools.yaml
EOF

cat > services-recipe <<EOF
ibm-ace-operator.yaml
ibm-platform-navigator.yaml
ibm-platform-navigator-instance.yaml
ibm-foundations.yaml
ibm-foundational-services-instance.yaml
ibm-automation-foundation-core-operator.yaml
ibm-catalogs.yaml
sealed-secrets.yaml
EOF

cat infra-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/1-infra/kustomization.yaml" }' | bash
rm 0-bootstrap/single-cluster/1-infra/kustomization.yaml.bak

cat services-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/2-services/kustomization.yaml" }' | bash
rm 0-bootstrap/single-cluster/2-services/kustomization.yaml.bak

sed -i.bak 's/managed-nfs-storage/'${RWX_STORAGECLASS}'/g' 0-bootstrap/single-cluster/2-services/argocd/instances/ibm-platform-navigator-instance.yaml
rm 0-bootstrap/single-cluster/2-services/argocd/instances/ibm-platform-navigator-instance.yaml.bak

rm infra-recipe
rm services-recipe

git add .
git commit -m "Adding ACE resources"
git push origin

