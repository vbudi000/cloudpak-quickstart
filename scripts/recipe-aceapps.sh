#!/bin/bash
# Applying recipes on the primary repo
# Assumption: running from gitops-0-bootstrap; with gh auth login
echo "Enable ACE sample application"

if [ -d "0-bootstrap/single-cluster" ]; then
    echo "Running from gitops-0-bootstrap" 
else
    echo "You should run this recipe script from the gitops-0-bootstrap directory"
    exit 1
fi

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

#cat services-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/2-services/kustomization.yaml" }' | bash
#rm 0-bootstrap/single-cluster/2-services/kustomization.yaml.bak

cat apps-recipe | awk '{print "sed -i.bak '\''/"$1"/s/^#//g'\'' 0-bootstrap/single-cluster/3-apps/kustomization.yaml" }' | bash
rm 0-bootstrap/single-cluster/3-apps/kustomization.yaml.bak

#rm services-recipe
rm apps-recipe

git add .
git commit -m "Adding ACE apps resources"
git push origin