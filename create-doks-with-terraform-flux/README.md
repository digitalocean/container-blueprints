# Create a GitOps Stack Using DigitalOcean Kubernetes and Flux CD

[Terraform](https://www.terraform.io) is one of the most popular tools to write infrastructure as code using declarative configuration files. You can write concise descriptions of resources using blocks, arguments, and expressions. 

[Flux](https://fluxcd.io) is used for managing the continuous delivery of applications inside a DOKS cluster and enable GitOps. The built-in [controllers](https://fluxcd.io/docs/components) help you create the required GitOps resources.

This tutorial will guide you on how to use [Flux](https://fluxcd.io) to manage application deployments on a DigitalOcean Kubernetes(DOKS) cluster in a GitOps fashion. Terraform will be responsible with spinning up the DOKS cluster as well as Flux. In the end, you will also tell Flux to perform a basic deployment of the BusyBox Docker application.

The following diagram illustrates the DOKS cluster, Terraform and Flux setup:

![TF-DOKS-FLUX-CD](https://github.com/digitalocean/container-blueprints/blob/main/create-doks-with-terraform-flux/assets/img/tf_doks_fluxcd_flow.png?raw=true)

{{< notice note >}}Following the steps below will result in charges for the use of DigitalOcean resources. [Delete the resources](#step-6-deleting-the-resources) to avoid being billed for additional resources.
{{< /notice >}}


## Prerequisites

To complete this tutorial, you will need:

- A [GitHub](https://github.com) repository and branch for Flux CD to store cluster and your Kubernetes custom application deployment manifests.

- A GitHub [personal access token](https://github.com/settings/tokens) that has the repo permissions set. The [Terraform module](https://www.terraform.io/docs/language/modules/index.html) provided in this tutorial needs it in order to create the SSH deploy key, and to commit the Flux CD cluster manifests in your Git repository.

- A [git client](https://git-scm.com/downloads). For example, use the following commands to install on MacOS:

  ```shell
  brew info git
  brew install git
  ```

- A [DigitalOcean access token](https://docs.digitalocean.com/reference/api/create-personal-access-token) for creating and managing the DOKS cluster. Copy the token value and save it somewhere safe.

- A [DigitalOcean Space](https://docs.digitalocean.com/products/spaces/how-to/create/) for storing the Terraform state file. Make sure that it is set to restrict file listing for security reasons.

- [Access keys](https://docs.digitalocean.com/products/spaces/how-to/manage-access/) for DigitalOcean Spaces. Copy the `key` and `secret` values and save each in a local environment variable for using later:

  ```shell
  export DO_SPACES_ACCESS_KEY="<YOUR_DO_SPACES_ACCESS_KEY>"
  export DO_SPACES_SECRET_KEY="<YOUR_DO_SPACES_SECRET_KEY>"
  ```

- [Terraform](https://www.terraform.io/downloads.html). For example, use the following commands to install on MacOS:

  ```shell
  brew info terraform
  brew install terraform
  ```

- [`doctl`](https://docs.digitalocean.com/reference/doctl/how-to/install) for interacting with DigitalOcean API.

- [`kubectl`](https://kubernetes.io/docs/tasks/tools) for interacting with Kubernetes.

- [`flux`](https://fluxcd.io/docs/installation) for interacting with Flux.  

## STEP 1: Cloning the Sample GitHub Repository

Clone the repository on your local machine and navigate to the appropriate directory:

```shell
git clone https://github.com/digitalocean/container-blueprints.git

cd container-blueprints/create-doks-with-terraform-flux
```

This repository is a Terraform module. You can inspect the options available inside the [variables.tf](https://github.com/digitalocean/container-blueprints/blob/main/create-doks-with-terraform-flux/variables.tf) file.

## Step 2: Bootstrapping DOKS and Flux

The bootstrap process creates a DOKS cluster and provisions Flux using Terraform. 

First, you are going to initialize the Terraform backend. Next, you will create a Terraform plan to inspect the infrastructure and then apply it to create all the required resources. After it finishes, you should have a fully functional DOKS cluster with Flux CD deployed and running. Follow these steps to bootstrap DOKS and Flux:

1. Rename the provided [`backend.tf.sample`](https://github.com/digitalocean/container-blueprints/blob/main/create-doks-with-terraform-flux/backend.tf.sample) file to `backend.tf`. Edit the file and replace the placeholders with your bucket and name of the Terraform state file you want to create.

    We strongly recommend using a [DigitalOcean Spaces](https://cloud.digitalocean.com/spaces) bucket for storing the Terraform state file. As long as the space is private, your sensitive data is secure. The data is also backed up and you can perform collaborative work using your Space.

    ```text
    # Store the state file using a DO Spaces bucket

    terraform {
      backend "s3" {
        skip_credentials_validation = true
        skip_metadata_api_check     = true
        endpoint                    = "<region>.digitaloceanspaces.com"  # replace <region>, leave the rest as is (e.g: fra1.digitaloceanspaces.com)
        region                      = "us-east-1"                        # leave this as is (Terraform expects the AWS format - N/A for DO Spaces)
        bucket                      = "<BUCKET_NAME>"                    # replace this with your bucket name
        key                         = "<TF_STATE_FILE_NAME>"             # replaces this with your state file name (e.g. terraform.tfstate)
      }
    }
    ```

2. Initialize the Terraform backend. 

    Use the previously created DO Spaces access and secret keys to initialize the Terraform backend:

    ```shell
    terraform init  --backend-config="access_key=$DO_SPACES_ACCESS_KEY" --backend-config="secret_key=$DO_SPACES_SECRET_KEY"
    ```

    The output looks similar to the following:

    ```text
    Initializing the backend...

    Successfully configured the backend "s3"! Terraform will automatically
    use this backend unless the backend configuration changes.

    Initializing provider plugins...
    - Finding hashicorp/kubernetes versions matching "2.3.2"...
    - Finding gavinbunney/kubectl versions matching "1.11.2"...
    ...
    ```

3. Rename the `terraform.tfvars.sample` file to `terraform.tfvars`. Edit the file and replace the placeholders with your DOKS and GitHub information.

    ```text
    # DOKS 
    do_api_token                 = "<YOUR_DO_API_TOKEN_HERE>"                 # DO API TOKEN
    doks_cluster_name            = "<YOUR_DOKS_CLUSTER_NAME_HERE>"            # Name of this `DOKS` cluster 
    doks_cluster_region          = "<YOUR_DOKS_CLUSTER_REGION_HERE>"          # What region should this `DOKS` cluster be provisioned in?
    doks_cluster_version         = "<YOUR_DOKS_CLUSTER_VERSION_HERE>"         # What Kubernetes version should this `DOKS` cluster use ?
    doks_cluster_pool_size       = "<YOUR_DOKS_CLUSTER_POOL_SIZE_HERE>"       # What machine type to use for this `DOKS` cluster ?
    doks_cluster_pool_node_count = <YOUR_DOKS_CLUSTER_POOL_NODE_COUNT_HERE>   # How many worker nodes this `DOKS` cluster should have ?

    # GitHub
    github_user               = "<YOUR_GITHUB_USER_HERE>"               # Your `GitHub` username
    github_token              = "<YOUR_GITHUB_TOKEN_HERE>"              # Your `GitHub` personal access token
    git_repository_name       = "<YOUR_GIT_REPOSITORY_NAME_HERE>"       # Git repository where `Flux CD` manifests should be stored
    git_repository_branch     = "<YOUR_GIT_REPOSITORY_BRANCH_HERE>"     # Branch name to use for this `Git` repository (e.g.: `main`)
    git_repository_sync_path  = "<YOUR_GIT_REPOSITORY_SYNC_PATH_HERE>"  # Git repository path where the manifests to sync are committed (e.g.: `clusters/dev`)
    ```

4. Create a Terraform plan and inspect the infrastructure changes:

    ```shell
    terraform plan -out doks_fluxcd_cluster.out
    ```

5. Apply the changes:

    ```shell
    terraform apply "doks_fluxcd_cluster.out"
    ```

    The output looks similar to the following:

    ```text
    tls_private_key.main: Creating...
    kubernetes_namespace.flux_system: Creating...
    github_repository.main: Creating...
    tls_private_key.main: Creation complete after 2s [id=1d5ddec06b0f4daeea57d3a987029c1153ebcb21]
    kubernetes_namespace.flux_system: Creation complete after 2s [id=flux-system]
    kubectl_manifest.install["v1/serviceaccount/flux-system/source-controller"]: Creating...
    kubectl_manifest.sync["kustomize.toolkit.fluxcd.io/v1beta1/kustomization/flux-system/flux-system"]: Creating...
    kubectl_manifest.install["v1/serviceaccount/flux-system/helm-controller"]: Creating...
    kubectl_manifest.install["networking.k8s.io/v1/networkpolicy/flux-system/allow-egress"]: Creating...
    ...
    ```  
    
    The DOKS cluster and Flux are up and running.

      ![DOKS state](https://github.com/digitalocean/container-blueprints/blob/main/create-doks-with-terraform-flux/assets/img/doks_created.png?raw=true)

    Check that the Terraform state file is saved in your Spaces bucket.

      ![DO Spaces Terraform state file](https://github.com/digitalocean/container-blueprints/blob/main/create-doks-with-terraform-flux/assets/img/tf_state_s3.png?raw=true)

    Check that the Flux CD manifests for your DOKS cluster are also present in your Git repository.

      ![GIT repo state](https://github.com/digitalocean/container-blueprints/blob/main/create-doks-with-terraform-flux/assets/img/flux_git_res.png?raw=true)

## Step 3: Inspecting DOKS Cluster State

List the available Kubernetes clusters:

```shell
doctl kubernetes cluster list
```

[Authenticate](https://docs.digitalocean.com/products/kubernetes/how-to/connect-to-cluster/#doctl) your cluster:

```shell
doctl k8s cluster kubeconfig save <your_doks_cluster_name>
```

[Check that the current context](https://docs.digitalocean.com/products/kubernetes/how-to/connect-to-cluster/#contexts) points to your cluster:

```shell
kubectl config get-contexts
```
 
List the cluster nodes and check the `STATUS` column to make sure that they're in a healthy state:

```shell
kubectl get nodes
```

The output looks similar to:

```text
NAME                            STATUS   ROLES    AGE    VERSION
dev-fluxcd-cluster-pool-8z9df   Ready    <none>   3d2h   v1.21.3
dev-fluxcd-cluster-pool-8z9dq   Ready    <none>   3d2h   v1.21.3
dev-fluxcd-cluster-pool-8z9dy   Ready    <none>   3d2h   v1.21.3
```

## Step 4: Inspecting Flux Deployment and Configuration

Check the status of Flux:

```shell
flux check
```

The output looks similar to the following:

```text
► checking prerequisites
✔ kubectl 1.21.3 >=1.18.0-0
✔ Kubernetes 1.21.2 >=1.16.0-0
► checking controllers
✗ helm-controller: deployment not ready
► ghcr.io/fluxcd/helm-controller:v0.11.1
✔ kustomize-controller: deployment ready
► ghcr.io/fluxcd/kustomize-controller:v0.13.1
✔ notification-controller: deployment ready
► ghcr.io/fluxcd/notification-controller:v0.15.0
✔ source-controller: deployment ready
► ghcr.io/fluxcd/source-controller:v0.15.3
✔ all checks passed
```

Flux comes with [CRDs](https://fluxcd.io/docs/components/helm/helmreleases#crds) that let you define the required components for a GitOps-enabled environment. An associated controller must also be present to handle the CRDs and maintain their state, as defined in the manifest files.

The following controllers come with Flux:

- [Source Controller](https://fluxcd.io/docs/components/source/) - responsible for handling the [Git Repository](https://fluxcd.io/docs/components/source/gitrepositories) CRD.
- [Kustomize Controller](https://fluxcd.io/docs/components/kustomize) - responsible for handling the [Kustomization](https://fluxcd.io/docs/components/kustomize/kustomization) CRD.

By default, Flux uses a [Git repository](https://fluxcd.io/docs/components/source/gitrepositories) and a [Kustomization](https://fluxcd.io/docs/components/kustomize/kustomization) resource. The Git repository tells Flux where to sync files from, and points to a Git repository and branch. The Kustomization resource tells Flux where to find your application `kustomizations`.

Inspect all the Flux resources:

```shell
flux get all
```

The output looks similar to the following:

```text
NAME                      READY MESSAGE                        REVISION      SUSPENDED 
gitrepository/flux-system True  Fetched revision: main/1d69... main/1d69...  False     

NAME                      READY MESSAGE                        REVISION      SUSPENDED 
kustomization/flux-system True  Applied revision: main/1d69... main/1d69c... False  
```

Terraform provisions the `gitrepository/flux-system` and `kustomization/flux-system` resources for your DOKS cluster. Inspect the Git repository resource:

```shell
flux export source git flux-system
```

The output looks similar to:

```text
---
apiVersion: source.toolkit.fluxcd.io/v1beta1
kind: GitRepository
metadata:
  ...
spec:
  gitImplementation: go-git
  interval: 1m0s
  ref:
    branch: main
  secretRef:
    name: flux-system
  timeout: 20s
  url: ssh://git@github.com/test-github-user/test-git-repo.git
```
    
In the `spec`, note the following parameter values:

- `url`: The Git repository URL to sync manifests from, set to `ssh://git@github.com/test-github-user/test-git-repo.git` in this example.
- `branch`:  The Git to use - set to `main` in this example.
- `interval`: The time interval to use for syncing, set to `1 minute` by default. 

Next, inspect the Kustomization resource:

```shell
flux export kustomization flux-system
```

The output looks similar to:

```text
---
apiVersion: kustomize.toolkit.fluxcd.io/v1beta1
kind: Kustomization
metadata:
...
spec:
  interval: 10m0s
  path: ./clusters/dev
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  validation: client
```

In the `spec`, note the following parameter values:

- `interval`:  The time interval to use for syncing, set to `10 minutes` by default.
- `path`: The path from the Git repository where this Kustomization manifest is kept.
- `sourceRef`: Shows that it is using another resource to fetch the manifests - a `GitRepository` in this case. The `name` field uniquely identifies the referenced resource - `flux-system`.

In case you need to troubleshoot or see what Flux CD is doing, you can access the logs by running the following command:

```shell
flux logs
```

The output looks similar to the following:

```text
...
2021-07-20T12:31:36.696Z info GitRepository/flux-system.flux-system - Reconciliation finished in 1.193290329s, next run in 1m0s 
2021-07-20T12:32:37.873Z info GitRepository/flux-system.flux-system - Reconciliation finished in 1.176637507s, next run in 1m0s 
...
```

## Step 5: Creating a BusyBox Example Application Using Flux

Configure Flux to create a simple BusyBox application, using the sample manifests provided in the sample Git repository.

The `kustomization/flux-system` CRD you inspected previously, expects the Kustomization manifests to be present in the Git repository path specified by the `git_repository_sync_path` Terraform variable specified in the `terraform.tfvars` file.

1. Clone the Git repository specified in the `terraform.tfvars` file. This is the main repository used for DOKS cluster reconciliation.

    ```shell
    git clone git@github.com:<github_user>/<git_repository_name>.git
    ```

2. Change to the directory where you cloned the repository:

    ```shell
    cd <git_repository_name>
    ```

3. Optionally, checkout the branch if you are not using the `main` branch:

    ```shell
    git checkout <git_repository_branch>
    ```

4. Next, create the `applications` directory, to store the `busybox` example manifests:

    ```shell
    APPS_PATH="<git_repository_sync_path>/apps/busybox"

    mkdir -p "$APPS_PATH"
    ```

5. Download the following manifests, using the directory path created in the previous step:
- [busybox-ns](https://github.com/digitalocean/container-blueprints/blob/main/create-doks-with-terraform-flux/assets/manifests/busybox-ns.yaml): Creates the `busybox` app namespace

- [busybox](https://github.com/digitalocean/container-blueprints/blob/main/create-doks-with-terraform-flux/assets/manifests/busybox.yaml): Creates the `busybox` app

- [kustomization](https://github.com/digitalocean/container-blueprints/blob/main/create-doks-with-terraform-flux/assets/manifests/kustomization.yaml): `kustomization` for BusyBox

**Hint:**

If you have `curl` installed, you can fetch the required files using the following command:

```shell
curl https://raw.githubusercontent.com/digitalocean/container-blueprints/main/create-doks-with-terraform-flux/assets/manifests/busybox-ns.yaml > "${APPS_PATH}/busybox-ns.yaml"

curl https://raw.githubusercontent.com/digitalocean/container-blueprints/main/create-doks-with-terraform-flux/assets/manifests/busybox.yaml > "${APPS_PATH}/busybox.yaml"

curl https://raw.githubusercontent.com/digitalocean/container-blueprints/main/create-doks-with-terraform-flux/assets/manifests/kustomization.yaml > "${APPS_PATH}/kustomization.yaml"
```

6. Commit the files and push the changes:

```shell
git add -A

git commit -am "Busybox Kustomization manifests"

git push origin
```

## STEP 6: Inspecting the Results

If you are using the default settings, a `busybox` namespace and an associated pod is created and running after one minute or so. If you do not want to wait, you can force reconciliation using the following command:

```shell
flux reconcile source git flux-system

flux reconcile kustomization flux-system
```

The output looks similar to:

```text
$ flux reconcile source git flux-system

► annotating GitRepository flux-system in flux-system namespace
✔ GitRepository annotated
◎ waiting for GitRepository reconciliation
✔ GitRepository reconciliation completed
✔ fetched revision main/b908f9b47b3a568ae346a74c277b23a7b7ef9602

$ flux reconcile kustomization busybox

► annotating Kustomization flux-system in flux-system namespace
✔ Kustomization annotated
◎ waiting for Kustomization reconciliation
✔ Kustomization reconciliation completed
✔ applied revision main/b908f9b47b3a568ae346a74c277b23a7b7ef9602
```

Get Kustomization status:

```shell
flux get kustomizations
```

The output looks similar to:

```text
NAME        READY MESSAGE                                                         REVISION                                      SUSPENDED     
flux-system True  Applied revision: main/fa69f917302bcfd35d2959ebc398b3aa13102480 main/fa69f917302bcfd35d2959ebc398b3aa13102480 False 
```

Examine the Kubernetes namespaces:

```shell
kubectl get ns
```

The output looks similar to the following:

```text
NAME              STATUS   AGE
busybox           Active   30s
default           Active   26h
flux-system       Active   26h
kube-node-lease   Active   26h
kube-public       Active   26h
kube-system       Active   26h
```

Check the `busybox` pod:

```shell
kubectl get pods -n busybox
```

The output looks similar to the following:

```text
NAME       READY   STATUS    RESTARTS   AGE
busybox1   1/1     Running   0          42s
```

## Step 6: Deleting the Resources

If you want to clean up the allocated resources, run the following command from the directory where you cloned this repository on your local machine:

```shell
terraform destroy
```

**Note:**

Due to an issue with the Terraform [kubernetes-provider](https://github.com/hashicorp/terraform-provider-kubernetes/issues/1040), the `terraform destroy` command hangs when it tries to clean up the `Flux CD` namespace. Alternatively, you can clean the resources individually:

 - Uninstall all the resources created by Flux, such as namespaces and pods, using the following command:

```shell
flux uninstall
```

- Destroy the DOKS cluster by running the following command:

```shell
terraform destroy --target=digitalocean_kubernetes_cluster.primary
```

**Note** that the command destroys the entire DOKS cluster (Flux and all the applications you deployed).

## Summary

In this tutorial, you used Terraform and Flux to manage application deployments on a DigitalOcean Kubernetes(DOKS) cluster in a GitOps fashion. You completed the following prerequisites for the tutorial:

- Created a GitHub repository and GitHub personal access token, and installed `git` client.

- Created a DigitalOcean access token.

- Created a DigitalOcean Space and access keys.

- Installed Terraform 

- Installed `doctl`, `kubectl`, and `flux`.

Terraform allows you to re-use code via `modules`. The [DRY](https://en.wikipedia.org/wiki/Don%27t_repeat_yourself) principle is strongly encouraged when using Terraform. The sample repository is a Terraform module which you can reference and re-use like this:

```text
module "doks_flux_cd" {
  source = "github.com/digitalocean/container-blueprints/create-doks-with-terraform-flux"

  # DOKS 
  do_api_token                 = "<YOUR_DO_API_TOKEN_HERE>"                 # DO API TOKEN
  doks_cluster_name            = "<YOUR_DOKS_CLUSTER_NAME_HERE>"            # Name of this `DOKS` cluster ?
  doks_cluster_region          = "<YOUR_DOKS_CLUSTER_REGION_HERE>"          # What region should this `DOKS` cluster be provisioned in?
  doks_cluster_version         = "<YOUR_DOKS_CLUSTER_VERSION_HERE>"         # What Kubernetes version should this `DOKS` cluster use ?
  doks_cluster_pool_size       = "<YOUR_DOKS_CLUSTER_POOL_SIZE_HERE>"       # What machine type to use for this `DOKS` cluster ?
  doks_cluster_pool_node_count = <YOUR_DOKS_CLUSTER_POOL_NODE_COUNT_HERE>   # How many worker nodes this `DOKS` cluster should have ?
  
  # GitHub
  github_user               = "<YOUR_GITHUB_USER_HERE>"               # Your `GitHub` username
  github_token              = "<YOUR_GITHUB_TOKEN_HERE>"              # Your `GitHub` personal access token
  git_repository_name       = "<YOUR_GIT_REPOSITORY_NAME_HERE>"       # Git repository where `Flux CD` manifests should be stored
  git_repository_branch     = "<YOUR_GIT_REPOSITORY_BRANCH_HERE>"     # Branch name to use for this `Git` repository (e.g.: `main`)
  git_repository_sync_path  = "<YOUR_GIT_REPOSITORY_SYNC_PATH_HERE>"  # Git repository path where the manifests to sync are committed (e.g.: `clusters/dev`)

}
```

You can instantiate it as many times as required and target different cluster configurations and environments. For more information, see the official [Terraform Modules](https://www.terraform.io/docs/language/modules/index.html) documentation page.

## What's Next

To help you start very quickly, as well as to demonstrate the basic functionality of Flux, this example uses  a single cluster, synced from one Git repository and branch. There are many options available depending on your setup and what the final goal is. You can create as many Git Repository resources as you want, that point to different repositories and/or branches (for example, a separate branch per environment). You can find more information and examples on the Flux CD [Repository Structure Guide](https://fluxcd.io/docs/guides/repository-structure).

Flux supports other Controllers, such as the following, which you can configure and enable:

- [Notification Controller](https://fluxcd.io/docs/components/notification) which is specialized in handling inbound and outbound events for Slack, etc.
- [Helm Controller](https://fluxcd.io/docs/components/helm) for managing [Helm](https://helm.sh) chart releases.
- [Image Automation Controller](https://fluxcd.io/docs/components/image) which can update a Git repository when new container images are available.

See [Flux CD Guides](https://fluxcd.io/docs/guides) for more example such as how to structure your Git repositories, as well as application manifests for multi-cluster and multi-environment setups.