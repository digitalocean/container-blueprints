# Using the Kubescape Vulnerability Scan Tool

## Introduction

[Kubescape](https://github.com/armosec/kubescape/) is a Kubernetes open-source tool developed by [Armosec](https://www.armosec.io) used for risk analysis, security compliance, RBAC visualizer, and image vulnerabilities scanning. In addition, Kubescape is able to scan Kubernetes manifests to detect potential configuration issues that expose your deployments to the risk of attack. It can also scan Helm charts, detect RBAC (role-based-access-control) violations, performs risk score calculations and shows risk trends over time.

Kubescape key features:

- Detect Kubernetes misconfigurations and provide remediation assistance via the [Armosec Cloud Portal](https://cloud.armosec.io).
- Risk analysis and trending over time is simplified via the [Armosec Cloud Portal](https://cloud.armosec.io).
- Includes multiple security and compliance frameworks, such as ArmoBest, NSA, MITRE and Devops Best Practices.
- Exceptions management support.
- Integrates with various tools such as Jenkins, Github workflows, Prometheus, etc.
- Image scanning - scan images for vulnerabilities and easily see, sort and filter (which vulnerability to patch first).
- Simplifies RBAC complexity by providing an easy-to-understand visual graph which shows the RBAC configuration in your cluster.

Kubescape can be run in two different ways:

- Via the command line interface (or CLI). In this mode you run Kubescape on demand and get quick insights about Kubernetes clusters and objects from a security point of view. The Kubescape CLI can be used in a CI/CD pipeline as well. Results can be uploaded to the [Armosec Cloud Portal](https://cloud.armosec.io) for later inspection and risk analysis.
- As a cronjob inside your Kubernetes cluster. In this mode Kubescape is constantly watching your Kubernetes cluster for changes and uploads scan results to the [Armosec Cloud Portal](https://cloud.armosec.io) .

Kubescape is using different frameworks to detect misconfigurations such as:

- [ArmoBest](https://www.armosec.io/blog/armobest-kubernetes-framework/)
- [NSA](https://www.nsa.gov/Press-Room/News-Highlights/Article/Article/2716980/nsa-cisa-release-kubernetes-hardening-guidance/)
- [MITRE ATT&CK](https://www.microsoft.com/security/blog/2021/03/23/secure-containerized-environments-with-updated-threat-matrix-for-kubernetes/)

In this guide you will use Kubescape to perform risk analysis for your DOKS cluster and application YAML manifests. Then, you will learn how to take the appropriate action to remediate the situation. Finally, you will learn how to integrate Kubescape in a Tekton CI/CD pipeline to scan for vulnerabilities in the early stages of development.

## Table of Contents

- [Introduction](#introduction)
- [Requirements](#requirements)
- [Step 1 - Getting to Know the Kubescape CLI](#step-1---getting-to-know-the-kubescape-cli)
- [Step 2 - Getting to Know the Armosec Cloud Portal](#step-2---getting-to-know-the-armosec-cloud-portal)
  - [Risk Score Analysis and Trending](#risk-score-analysis-and-trending)
  - [Assisted Remediation for Reported Security Issues](#assisted-remediation-for-reported-security-issues)
- [Step 3 - Configuring Kubescape Automatic Scans for DOKS](#step-3---configuring-kubescape-automatic-scans-for-doks)
- [Step 4 - Example Tekton CI/CD Pipeline Implementation using Kubescape CLI](#step-4---example-tekton-cicd-pipeline-implementation-using-kubescape-cli)

## Requirements

To complete all steps from this guide, you will need:

1. A working `DOKS` cluster running `Kubernetes version >=1.21` that you have access to. The DOKS cluster must have at least `2 nodes`, each with `2 CPUs`, `4 GB` of memory, and `5 GB` of disk storage for PVCs (needed for Tekton workspaces). For additional instructions on configuring a DigitalOcean Kubernetes cluster, see: [How to Set Up a DigitalOcean Managed Kubernetes Cluster (DOKS)](https://github.com/digitalocean/Kubernetes-Starter-Kit-Developers/tree/main/01-setup-DOKS#how-to-set-up-a-digitalocean-managed-kubernetes-cluster-doks).
2. [Tekton 1-click application](https://marketplace.digitalocean.com/apps/tekton-pipelines) installed in your DOKS cluster for the CI part.
3. [ArgoCD 1-click application](https://marketplace.digitalocean.com/apps/argocd) installed in your DOKS cluster for the CD part.
4. A [Git](https://git-scm.com/downloads) client to interact with GitHub repositories.
5. [Kubectl](https://kubernetes.io/docs/tasks/tools) CLI for `Kubernetes` interaction. Follow these [instructions](https://www.digitalocean.com/docs/kubernetes/how-to/connect-to-cluster/) to connect to your cluster with `kubectl` and `doctl`.
6. [Argo CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation) to interact with `Argo CD` using the command line interface.
7. [Tekton CLI](https://tekton.dev/docs/cli/#installation) to interact with `Tekton Pipelines` using the command line interface.
8. [Kubescape CLI](https://hub.armosec.io/docs/installing-kubescape/) to interact with [Kubescape](https://github.com/armosec/kubescape/) vulnerabilities scanner.

## Step 1 - Getting to Know the Kubescape CLI

You can manually scan for vulnerabilities via the `kubescape` command line interface. The kubescape CLI is designed to run in a CI/CD environment as well (such as Tekton). Next, you can scan a whole Kubernetes cluster (REST API, Kubernetes objects, etc) or limit scans to specific namespaces, enable host scanning (worker nodes), perform local or remote repository scanning (e.g. GitHub), detect YAML misconfigurations and scan container images for vulnerabilities. Various frameworks can be selected via the `framework` command, such as ArmoBest, NSA, MITRE, etc.

When kubescape CLI is invoked, it will download (or update on subsequent runs) the vulnerabilities database on your local machine. Then, it will start the scanning process and report back issues in a specific format. By default it will print a summary table using the standard output or the console. Kubescape can generate reports in other formats as well, such as JSON, HTML, etc.

You can opt to push the results to the [Armosec Cloud Portal](https://cloud.armosec.io) via the `--submit` flag to store and visualize scan results later.

**Note:**

It's not mandatory to submit results to the Armosec cloud portal. The big advantage of using the portal is visibility because it gives you a nice graphical overview for Kubescape scan results and the overall risk score. It also helps with the investigations and provides remediation hints.

Some examples to try with Kubescape CLI:

- Scan a whole Kubernetes cluster and generate a summary report in the console (standard output):

   ```shell
   kubescape scan
   ```

- Use a specific namespace only for scanning:

   ```shell
   kubescape scan --include-namespaces tekton-ci
   ```

- Exclude specific namespaces from scanning:

   ```shell
   kubescape scan --exclude-namespaces kube-system,kube-public
   ```

- Scan a specific namespace and submit results to the Armosec cloud portal:

   ```shell
   kubescape scan --include-namespaces default --submit
   ```

- Perform cluster scan using a specific framework (e.g. NSA):

   ```shell
   kubescape scan framework nsa --exclude-namespaces kube-system,kube-public
   ```

Kubescape can scan your Kubernetes cluster hosts (worker nodes) as well for OS vulnerabilities. To enable this feature you need to pass the `--enable-host-scan` flag to the kubescape CLI. When this flag is enabled, kubescape deploys `sensors` via a Kubernetes DaemonSet in your cluster to scan each host for known vulnerabilities. At the end when the scan process is completed, the sensors are removed from your cluster.

Kubescape CLI provides help pages for all available options. Below command can be used to print the help page:

```shell
kubescape --help
```

The output looks similar to:

```text
Kubescape is a tool for testing Kubernetes security posture. Docs: https://hub.armo.cloud/docs

Usage:
  kubescape [command]

Available Commands:
  completion  Generate autocompletion script
  config      Handle cached configurations
  delete      Delete configurations in Kubescape SaaS version
  download    Download controls-inputs,exceptions,control,framework,artifacts
  help        Help about any command
  list        List frameworks/controls will list the supported frameworks and controls
  scan        Scan the current running cluster or yaml files
  submit      Submit an object to the Kubescape SaaS version
  version     Get current version
...
```

There is a help page for each command or subcommand as well which can be accessed via `kubescape [command] --help`.

Please visit the official [documentation page](https://hub.armosec.io/docs/examples/) for more Kubescape examples.

## Step 2 - Getting to Know the Armosec Cloud Portal

Armosec provides a nice [cloud based portal](https://cloud.armosec.io) where you can upload your Kubescape scan results and perform risk analysis. This is pretty useful because you will want to visualize and inspect each scan report, take the appropriate action to remediate the situation, and then run the scan again to check results. By having a good visual representation for each report and the associated risk score helps you on the long term with the investigations and iterations required to fix the reported security issues.

You can create an account for free limited to **10 worker nodes** and **1 month of data retention** which should be sufficient in most cases (e.g. for testing or development needs). You can read more about how to create the kubescape cloud account on the [official documentation page](https://hub.armosec.io/docs/kubescape-cloud-account).

Once you have the account created, an unique user ID is generated which you can use to upload scan results for that specific account. For example, you may have a specific automation such as a CI/CD pipeline where you need to upload scan results, hence the associated user ID is required to distinguish between multiple tenants.

### Risk Score Analysis and Trending

For each scan report uploaded to your Armosec cloud account, a new history record is added containing the list of issues found and the associated risk score. This way you can get trends and the associated graphs showing risk score evolution over time. Also, a list with topmost security issues is generated as well in the main dashboard.

Below picture illustrates these features:

![Kubescape Cloud Portal Dashboard](assets/images/kubescape_portal_dashboard.png)

**What is risk score and how do you interpret it?**

On each scan, kubescape verifies your resources for potential security risks using internal controls. A [Kubescape Control](https://hub.armosec.io/docs/controls) is a concept used by the kubescape tool to denote the tests used under the hood to check for a particular aspect of your cluster (or resources being scanned). Going further, a framework is a collection of controls or tests used internally to scan your particular resource(s) for issues. So, depending on what framework you use, a different suite of checks is performed (still, some tests share same things in common). Finally, depending on the risk factor associated with each test the final score is computed.

The final score is a positive number ranging from **0** to **100%**. A lower value indicates a good score, whereas a higher value denotes the worst case scenario. So, if you want to be on the safe side you should aim for the lowest value possible. In practice, a score equal to or lower than **30%** should be a good starting point.

### Assisted Remediation for Reported Security Issues

Another useful feature provided by the Armosec cloud portal is security issues remediation assistance. It means, you receive a recommendation about how to fix each security issue found by the kubescape scanner. This is very important because it simplifies the process and closes the loop for each iteration that you need to perform to fix each reported security issue. Below picture illustrates this process better:

![Security Compliance Scanning and Iterations](assets/images/security_compliance_scanning_process.png)

For each reported security issue there is a wrench tool icon displayed which you can click on and get remediation assistance:

![Access Kubescape Cloud Portal Remediation Assistance](assets/images/kubescape_cp_remediation_assist.png)

Next, a new window opens giving you details about each affected Kubernetes object, highlighted in green color:

![Kubescape Cloud Portal Remediation Hints](assets/images/kubescape_cp_remediation_hints.png)

## Step 3 - Configuring Kubescape Automatic Scans for DOKS

## Step 4 - Example Tekton CI/CD Pipeline Implementation using Kubescape CLI

How do you benefit from embedding a security compliance scanning tool in your CI/CD pipeline and avoid unpleasant situations in a production environment?

It all starts at the foundation or the infrastructure level where software development starts. In general, you will want to use a dedicated environment for each stage. So, in the early stages of development when code changes happen frequently, you have a dedicated development environment (called the lower environment usually). Then, the application gets more and more refined in the QA environment where QA teams perform manual and/or automated testing. Next, if the application gets the QA team approval it is promoted to upper environments, such as staging and finally into production. In this process, where the application is promoted from one stage to another (or from lower to upper environments), a dedicated pipeline runs which continuously scans application artifacts and computes the security risk score. If the score doesn't meet a specific threshold, the pipeline fails immediately and promotion of application artifacts to upper environments (such as production) is stopped in the early stages.

So, the security scanning tool (e.g. kubescape) acts as a gate stopping unwanted artifacts from getting in your production environment from the early stages of development. In the same manner, upper environments pipelines use kubescape to allow or forbid application artifacts entering the final production stage.

How do you fail the pipeline if a certain security compliance level is not met ?

Kubescape CLI provides a flag named `--fail-threshold` for this purpose. Remember what the risk score is and how do you interpret the numbers ?

TBD.
