#!/bin/bash
# Applying recipes on the primary repo
# Assumption: running from gitops-0-bootstrap; with gh auth login
echo "Enable MQ sample application"

if [ -d "0-bootstrap/single-cluster" ]; then
    echo "Running from gitops-0-bootstrap" 
else
    echo "You should run this recipe script from the gitops-0-bootstrap directory"
    exit 1
fi

cat > services-recipe <<EOF
artifactory.yaml
sonarqube.yaml
EOF
#ci-scc.yaml

cat > apps-recipe <<EOF
mq\/cicd.yaml
mq\/dev.yaml
EOF

cat services-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/2-services/kustomization.yaml" }' | bash
rm 0-bootstrap/single-cluster/2-services/kustomization.yaml.bak

cat apps-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/3-apps/kustomization.yaml" }' | bash
rm 0-bootstrap/single-cluster/3-apps/kustomization.yaml.bak

rm services-recipe
rm apps-recipe

git add .
git commit -m "Adding MQ resources"
git push origin