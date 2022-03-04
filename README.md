# IBM Cloud Pak - QuickStart script collection

This repository collects invocation scripts for setting up OpenShift cluster for a Quick Start scenario in the Production Deployment Guide. 

For more information on Production Deployment Guide, see [https://pages.github.ibm.com/cloudpakbringup/production-deployment-guides/](https://pages.github.ibm.com/cloudpakbringup/production-deployment-guides/). 

## How to use this repository

![flow](images/flow.png)

These are the pre-requisites:

- Provided bash environment
- Install the [Github CLI](https://github.com/cli/cli) (version 1.14.0+)
- Install the [Git CLI](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- Install the [OpenShift CLI](https://access.redhat.com/downloads/content/290) - `oc` (version 4.7 or 4.8) and `openshift-install` 
- Install the [kubeseal CLI](https://github.com/bitnami-labs/sealed-secrets#homebrew) 
- Install the [Tekton CLI](https://tekton.dev/docs/cli/)
- Install the [ArgoCD CLI](https://argoproj.github.io/argo-cd/cli_installation/)
- Install [jq](https://stedolan.github.io/jq/) and [yq](https://github.com/mikefarah/yq) tools: 
- Access to a newly installed cluster or sufficient access to a platfor to setup a new OpenShift cluster
- Setup a [sealed secret certificate](https://github.com/bitnami-labs/sealed-secrets/blob/main/docs/bring-your-own-certificates.md) - [Sample Demo secret](https://bit.ly/demo-sealed-master)

GIT Personal Access Token and GitHub Organization instruction can be read at [Personal Access Token](https://pages.github.ibm.com/cloudpakbringup/production-deployment-guides/snippets/gitops-cluster-prereq/#create-a-git-personal-access-token-pat) and [GitHub Organization](https://pages.github.ibm.com/cloudpakbringup/production-deployment-guides/snippets/gitops-cluster-prereq/#create-a-custom-git-organization).

Sample environment variables for running in various GIT backend:

- GitHub 
    ```bash
    export GIT_TARGET="github"
    export GIT_USER="gituser"
    export GIT_TOKEN="ghp_nnnnnnnnnnnnnnnnnnnnn" 
    export GIT_BRANCH="master"
    export GIT_ORG="git_org1"
    export SEALED_SECRET_KEY_FILE=./ss.yaml
    export RWX_STORAGECLASS="ocs-storagecluster-cephfs"
    export IBM_ENTITLEMENT_KEY="xxxxxxxxxxxxxxxxxx"
    ```

- GitLab
    ```bash
    export GIT_TARGET=gitlab
    export GIT_USER="user000"
    export GIT_TOKEN="glpat-sasdasdasasdas"
    export GIT_HOST="gitlab.com"
    export GIT_BRANCH=main
    export GIT_BASEURL=https://gitlab.com
    export GIT_ORG="org000"
    export SEALED_SECRET_KEY_FILE=./ss.yaml
    export RWX_STORAGECLASS="ocs-storagecluster-cephfs"
    export IBM_ENTITLEMENT_KEY="xxxxxxxxxxxxxxxxxx"
    ```

- Gitea

    ```bash
    OCDOMAIN=$(oc get ingresscontrollers.operator.openshift.io -n openshift-ingress-operator   default -o jsonpath='{.status.domain}')
    export GIT_TARGET=gitea
    export GIT_USER="user1"
    export GIT_BRANCH=main
    export GIT_BASEURL=https://gitea-tools.${OCDOMAIN}/
    export GIT_HOST=gitea-tools.${OCDOMAIN}
    export DEBUG=true
    export GIT_ORG="org1"
    export SEALED_SECRET_KEY_FILE=./ss.yaml
    export RWX_STORAGECLASS="ocs-storagecluster-cephfs"
    export IBM_ENTITLEMENT_KEY="xxxxxxxxxxxxxxxxxx"
    ```

Run the quickstart program

``` bash
git clone https://github.com/vbudi000/cloudpak-quickstart
echo $GITHUB_TOKEN | gh auth login --with-token
./cloudpak-quickstart/scripts/quickstart.sh
```

## Using the startqs invoker

You can initiate the script using the following procedure, on a working directory that is not under git, download `startqs.sh`:

```bash
curl -sfL https://raw.githubusercontent.com/vbudi000/cloudpak-quickstart/master/startqs.sh > startqs.sh
```

Edit the environment parameters section of the downloaded script: 

```bash 
###########################################################
# Change the following environment variables
###########################################################
export GIT_TARGET="github"
export GIT_USER="gituser"
export GIT_TOKEN="ghp_key"
export GIT_BRANCH="master"
export GIT_ORG="git-org"
export GIT_HOST="github.com"
export IBM_ENTITLEMENT_KEY="entitlement-key"
export SEALED_SECRET_KEY_FILE=./shared-secret.yaml
export RWX_STORAGECLASS="ocs-storagecluster-cephfs"
###########################################################
# Start deployment of Quick Start - pick and choose the components to enable
###########################################################
export ADD_INFRA=yes
export ADD_MQ=yes
export ADD_MQAPPS=yes
export ADD_ACE=yes
export ADD_ACEAPPS=yes
export ADD_APIC=yes
export ADD_CPD=yes
export ADD_WS=yes
export ADD_CP4S=yes
export ADD_PROCMINING=yes
###########################################################
# End environment variable changes
###########################################################
```

Either provide the OpenShift environment using `oc login` or create `install-config.yaml` file in the directory and invoke the script 

```bash
bash startqs.sh
```

See it in action:

- App Connect Enterprise sample [![asciicast](https://asciinema.org/a/439530.svg)](https://asciinema.org/a/439530)
- Process Mining sample [![asciicast](https://asciinema.org/a/439944.svg)](https://asciinema.org/a/439944)
- IBM Cloud Pak for Data sample [![asciicast](https://asciinema.org/a/439439.svg)](https://asciinema.org/a/439439)
- MQ sample (older version) [![asciicast](https://asciinema.org/a/435864.svg)](https://asciinema.org/a/435864)