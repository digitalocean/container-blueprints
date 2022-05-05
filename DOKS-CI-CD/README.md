# DOKS CI/CD using Tekton, Argo CD and Knative Serverless Applications

## Introduction

This blueprint will show you how to implement a CI/CD solution using free and popular open source implementations that run on Kubernetes clusters natively. You will be using the DigitalOcean marketplace to provision each system application to your Kubernetes cluster, such as Tekton, Argo CD, Knative, Cert-Manager. The DigitalOcean marketplace is a collection of pre-configured 1-click apps that you can quickly deploy to your Kubernetes cluster (DOKS).

You will learn how to use Tekton to build a CI pipeline that continuously fetches code changes from a Git repository, and builds a Docker image for your custom application. Then, Tekton will push the docker image to a remote registry and notifies Argo CD to deploy it to your Kubernetes cluster.

The important building blocks are as follows:

1. [Kaniko](https://github.com/GoogleContainerTools/kaniko), for building container images in a Kubernetes cluster directly.
2. [Tekton](https://tekton.dev) pipelines, for implementing the CI process.
3. [Argo CD](https://argoproj.github.io/cd), for implementing the CD process.
4. [Knative](https://knative.dev), for running and exposing applications functionality on Kubernetes with ease. Also enables Tekton Pipelines triggering whenever a push happens on your GitHub repository via the Knative Eventing component.
5. [Cert-Manager](https://cert-manager.io), for managing and enabling TLS termination for Knative Services.

On each code change a Tekton CI pipeline kicks in, builds a container image for your custom application, and uploads it to a Docker registry. Then, Argo CD pulls the Docker image, and deploys it to your DOKS cluster as a Knative application (or service). All described steps run automatically.

After completing this blueprint, you should have a fully functional CI/CD pipeline that continuously builds and deploys code changes for your custom applications.

Following diagram shows the complete setup:

**TODO**

How this blueprint is structured:

1. First, a short introduction is given for each component (such as Kaniko, Tekton, Argo CD, Knative, etc). Each introductory section also tries to explain the role of each component in this guide.
2. Then, you will be guided through the installation steps for each component, using the DigitalOcean 1-click apps marketplace.
3. Next, you will configure Knative Eventing to react on GitHub events and trigger the CI/CD pipeline.
4. Final steps would be to implement and test the CI/CD setup (using Knative, Tekton and Argo CD), and deploy Knative serverless applications.

## Table of Contents

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
- [Getting to Know Kaniko](#getting-to-know-kaniko)
- [Getting to Know Tekton](#getting-to-know-tekton)
  - [Tasks](#tasks)
  - [Pipelines](#pipelines)
  - [Event Listeners and Triggers](#event-listeners-and-triggers)
  - [Tekton Catalog](#tekton-catalog)
  - [Tekton Dashboard](#tekton-dashboard)
- [Getting to Know Argo CD](#getting-to-know-argo-cd)
  - [Applications](#applications)
  - [Projects](#projects)
- [Getting to Know Knative](#getting-to-know-knative)
  - [Serving Component](#serving-component)
  - [Eventing Component](#eventing-component)
- [Getting to Know Cert-Manager](#getting-to-know-cert-manager)
- [Step 1 - Installing Cert-Manager](#step-1---installing-cert-manager)
- [Step 2 - Installing Tekton](#step-2---installing-tekton)
  - [Provisioning Tekton Pipelines](#provisioning-tekton-pipelines)
  - [Provisioning Tekton Triggers](#provisioning-tekton-triggers)
  - [Provisioning Tekton Dashboard](#provisioning-tekton-dashboard)
- [Step 3 - Installing Argo CD](#step-3---installing-argo-cd)
- [Step 4 - Installing Knative](#step-4---installing-knative)
  - [Configuring DO Domain Records](#configuring-do-domain-records)
  - [Enabling Knative Services Auto TLS Feature via Cert-Manager](#enabling-knative-services-auto-tls-feature-via-cert-manager)
- [Step 5 - Setting Up Your First CI/CD Pipeline Using Tekton and Argo](#step-5---setting-up-your-first-cicd-pipeline-using-tekton-and-argo)
- [Step 5 - Testing the CI/CD Setup](#step-5---testing-the-cicd-setup)
- [Conclusion](#conclusion)
- [Additional Resources](#additional-resources)

## Prerequisites

To complete this tutorial, you will need:

1. A working domain that you own. This is required for exposing public services used in this guide (including GitHub webhooks). Make sure to also read the DigitalOcean [DNS Quickstart Guide](https://docs.digitalocean.com/products/networking/dns/quickstart), as well as the additional how to's on this topic.
2. A working `DOKS` cluster running `Kubernetes version >=1.21` that you have access to. The DOKS cluster must have at least `2 nodes`, each with `2 CPUs`, `4 GB` of memory, and `20 GB` of disk storage. For additional instructions on configuring a DigitalOcean Kubernetes cluster, see: [How to Set Up a DigitalOcean Managed Kubernetes Cluster (DOKS)](https://github.com/digitalocean/Kubernetes-Starter-Kit-Developers/tree/main/01-setup-DOKS#how-to-set-up-a-digitalocean-managed-kubernetes-cluster-doks).
3. A [GitHub](https://github.com) repository and branch, to store your Argo CD and custom applications manifests. **Must be created beforehand.**
4. A [Git](https://git-scm.com/downloads) client, to interact with your GitHub repository.
5. [Kubectl](https://kubernetes.io/docs/tasks/tools) CLI, for `Kubernetes` interaction. Follow these [instructions](https://www.digitalocean.com/docs/kubernetes/how-to/connect-to-cluster/) to connect to your cluster with `kubectl` and `doctl`.
6. [Helm](https://www.helm.sh), for interacting with Helm releases created by the DigitalOcean 1-click apps used in this tutorial.
7. [Argo CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation), to interact with `Argo CD` using the command line interface.
8. [Tekton CLI](https://tekton.dev/docs/cli/#installation), to interact with `Tekton Pipelines` using the command line interface.
9. [Knative CLI](https://knative.dev/docs/install/client/install-kn), to interact with `Knative` using the command line interface.

## Getting to Know Kaniko

[Kaniko](https://github.com/GoogleContainerTools/kaniko) is nothing more than a tool to build container images directly from a Dockerfile, inside a container or Kubernetes cluster. It means, you can build and push docker images to a remote registry directly from your Kubernetes cluster. What is nice about this setup is you can have a full CI system running completely in your Kubernetes cluster.

Under the hood, Kaniko doesn't depend on a Docker daemon and executes each command within a Dockerfile completely in userspace. This enables building container images in environments that can't easily or securely run a Docker daemon, such as a standard Kubernetes cluster. Kaniko is meant to be run as an image: `gcr.io/kaniko-project/executor`.

Please visit the [official project page](https://github.com/GoogleContainerTools/kaniko) for more information and details about Kaniko.

In this blueprint, you will use Kaniko to build Docker images for your custom applications from Kubernetes cluster itself.

## Getting to Know Tekton

Continuous integration (or CI) is the process of automating the integration of small code changes from multiple contributors into a single software project. To achieve CI a central repository is used (e.g. Git), where each developer (or contributor) pushes code changes. Then, a CI tool (e.g. Tekton) detects changes and starts the CI automation.

In general, each CI automation consists of several steps:

1. Fetching application code from a remote SCM (Source Control Management) repository, such as Git.
2. Building the application (specific compilers are invoked, depending on the programming language).
3. Testing application code changes (via unit tests, usually).
4. Creating the final artifact (a binary or a zip file, a Docker file, etc) for application delivery.
5. Pushing the application artifact to a remote repository for later use by a continuous delivery system.

[Tekton](https://tekton.dev) is a cloud native solution for building CI/CD systems on top of Kubernetes clusters. It is specifically engineered to run on Kubernetes, and empowers developers to create CI pipelines using reusable blocks called Tasks. Other important components are Tekton CLI and Catalog (collection of reusable Tasks), that make Tekton a complete ecosystem.

In this guide, Tekton is used to implement the CI part via the Pipelines component (and associated components, such as: Tasks, Triggers, etc).

Tekton is modular in nature and very well organized. This tutorial relies on the following Tekton components to implement the CI part:

- [Tasks](https://tekton.dev/docs/pipelines/tasks) - used to organize the steps performing each action such as build and test your application code.
- [Pipelines](https://tekton.dev/docs/pipelines/pipelines) - used to organize tasks and define your custom CI flow.
- [Triggers and EventListeners](https://tekton.dev/docs/triggers) - used to capture and trigger on Git events (e.g. git push events).

### Tasks

A Tekton Task is a collection of Steps that you define and arrange in a specific order of execution as part of your continuous integration flow. Steps are the basic unit of execution in Tekton which perform real actions such as build code, create image, push to Docker registry, etc. To add Steps to a Task you define a steps field containing a list of desired Steps. The order in which the Steps appear in this list is the order in which they will execute.

For each task, Tekton creates a Kubernetes Pod in your cluster to run the steps. Then, each step runs in a docker container, thus it must reference a docker image. The container you choose depends on what your step does. For example:

- Execute shell scripts: use an `Alpine Linux` image.
- Build a Dockerfile: use `Google’s Kaniko` image.
- Run kubectl: use the `bitnami/kubectl` image.
- An image of your own to perform custom actions.

Task definitions are composed of (most important are highlighted):

- [Parameters](https://tekton.dev/docs/pipelines/tasks/#specifying-parameters) - used to specify input parameters for a task such as compilation flags, artifacts name, etc.
- [Resources](https://tekton.dev/docs/pipelines/tasks/#specifying-resources) - each task may have its own inputs and outputs, known as input and output resources in Tekton. A compilation task, for example, may have a git repository as input and a container image as output: the task clones the source code from the repository, runs some tests, and at last builds the source code into an executable container image.
- [Workspaces](https://tekton.dev/docs/pipelines/tasks/#specifying-workspaces) - used to share data (artifacts) between steps defined in a task.
- [Results](https://tekton.dev/docs/pipelines/tasks/#emitting-results) - represent a string value emitted by a Task. Results can be passed between Tasks inside a pipeline. Results are also visible to users, and represent important information such as SHA id for a cloned repository (emitted by the [git-clone](https://hub.tekton.dev/tekton/task/git-clone) Task).

Typical `Tekton Task` definition looks like below:

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: example-task-name
spec:
  params:
    - name: pathToDockerFile
      type: string
      description: The path to the dockerfile to build
      default: /workspace/workspace/Dockerfile
  resources:
    inputs:
      - name: workspace
        type: git
    outputs:
      - name: builtImage
        type: image
  steps:
    - name: ubuntu-example
      image: ubuntu
      args: ["ubuntu-build-example", "SECRETS-example.md"]
    - name: dockerfile-pushexample
      image: gcr.io/example-builders/push-example
      args: ["push", "$(resources.outputs.builtImage.url)"]
      volumeMounts:
        - name: docker-socket-example
          mountPath: /var/run/docker.sock
```

Explanation for the above configuration:

- `spec.params`: defines the list of input parameters for the Task.
- `spec.resources`: defines the input/output resources for the Task (via `spec.resources.inputs`, and `spec.resources.outputs` respectively).
- `spec.steps`: defines the list of steps to be executed in order as part of the Task.

By design, Tekton will not run your Tasks when created. To launch a Task into execution, you need to create a separate [TaskRun](https://tekton.dev/docs/pipelines/taskruns) resource. A TaskRun is what instantiates your Task and begin execution of steps. A TaskRun executes the Steps in the Task in the order they are specified until all Steps have executed successfully or a failure occurs. Also, a TaskRun allows to pass input parameters, as well as specifying resources and workspaces for your custom Task.

What's important to remember is that tasks are reusable building blocks that can be shared and referenced across pipelines. This design aspect makes Tekton unique. To help users even more, Tekton project offers a collection of reusable tasks via the [Tekton Catalog](https://hub.tekton.dev) project.

Below picture illustrates the `Task` and `TaskRun` concepts:

![Tekton Task/TaskRun Overview](assets/images/tekton_tasks_overview.png)

Please visit the [official documentation page](https://tekton.dev/docs/pipelines/tasks) for more information and details about Tekton Tasks.

### Pipelines

A Tekton Pipeline is used to organize your Tekton tasks and orchestrate the CI flow. A Pipeline specifies one or more Tasks in the desired order of execution. You can embed tasks in a pipeline directly, or reference them from external manifest files. By using references, you create task definitions in separate manifest files, and have them reused across different pipelines. This method is encouraged because it avoids code or configuration duplication, and promotes `code reuse` (or configuration reuse). Thus, tasks act as objects (with inputs and outputs) that can be reused (and instantiated) across your pipelines. You can create dedicated pipelines to test, or build and deploy your applications code.

Pipeline definitions are composed of (most important are highlighted):

- [Parameters](https://tekton.dev/docs/pipelines/pipelines/#specifying-parameters) - used to specify input parameters (at a global level) for all tasks within a Pipeline.
- [Resources](https://tekton.dev/docs/pipelines/pipelines/#specifying-resources) - used to specify inputs and outputs for Tasks within a Pipeline.
- [Workspaces](https://tekton.dev/docs/pipelines/pipelines/#specifying-workspaces) - used to specify a workspace for shared artifacts between Tasks within a Pipeline.

Typical `Tekton Pipeline` definition looks like below:

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: kaniko-pipeline
spec:
  params:
    - name: git-url
    - name: git-revision
    - name: image-name
    - name: path-to-image-context
    - name: path-to-dockerfile
  workspaces:
    - name: git-source
  tasks:
    - name: fetch-from-git
      taskRef:
        name: git-clone
      params:
        - name: url
          value: $(params.git-url)
        - name: revision
          value: $(params.git-revision)
      workspaces:
        - name: output
          workspace: git-source
    - name: build-image
      taskRef:
        name: kaniko
      params:
        - name: IMAGE
          value: $(params.image-name)
        - name: CONTEXT
          value: $(params.path-to-image-context)
        - name: DOCKERFILE
          value: $(params.path-to-dockerfile)
      workspaces:
        - name: source
          workspace: git-source
```

Explanation for the above configuration:

- `spec.params`: defines the list of input parameters for the Pipeline.
- `spec.workspaces`: defines a list of workspaces to be used by each Task inside the Pipeline. Workspaces are used to share data (or artifacts) between tasks.
- `spec.tasks`: defines the list of tasks (can be embedded or referenced using `taskRef`) to be executed in order as part of the Pipeline.

By design, Tekton will not run your Pipelines when created. To launch a Pipeline into execution, you need to create a separate [PipelineRun](https://tekton.dev/docs/pipelines/pipelineruns) resource. A PipelineRun allows you to instantiate and execute a Tekton Pipeline in your Kubernetes cluster. A PipelineRun executes the Tasks in the Pipeline in the order they are specified until all Tasks have executed successfully or a failure occurs.

**Note:**

Tasks referenced within a Pipeline will get the corresponding TaskRun objects created automatically (no need to create them separately).

Below picture illustrates Pipelines and Tasks composition:

![Task and Pipelines Concepts](assets/images/tekton_pipelines_overview.png)

Please visit the [official documentation page](https://tekton.dev/docs/pipelines/pipelines) for more information and details about Tekton Pipelines.

### Event Listeners and Triggers

You need a mechanism to tell Tekton how to react and trigger your CI pipeline in response to external events emitted by various sources (such as GitHub for example). This is accomplished via another Tekton component called Triggers (needs to be installed separately). Tekton triggers allows you to detect and extract information from events from a variety of sources and execute TaskRuns and PipelineRuns based on that information. It can also pass information extracted from events directly to TaskRuns and PipelineRuns.

Following resources are required to automatically trigger a CI pipeline using GitHub webhooks:

1. An [EventListener](https://github.com/tektoncd/triggers/blob/main/docs/eventlisteners.md) - listens for events and specifies one or more `Triggers`.
2. A [Trigger](https://github.com/tektoncd/triggers/blob/main/docs/triggers.md) - specifies what happens when the `EventListener` detects an event. A `Trigger` specifies a `TriggerTemplate` and a `TriggerBinding`.
3. A [TriggerTemplate](https://github.com/tektoncd/triggers/blob/main/docs/triggertemplates.md) - specifies what `TaskRun` or `PipelineRun` to execute when your `EventListener` detects an event.
4. A [TriggerBinding](https://github.com/tektoncd/triggers/blob/main/docs/triggerbindings.md) - specifies what data to extract from the event payload, and how to pass that data to the `TriggerTemplate`.

Optionally, you can also create an [Interceptor](https://github.com/tektoncd/triggers/blob/main/docs/interceptors.md) to filter events, perform webhook verification (using secrets), or other processing before the Trigger actions are executed.

The EventListener logic is implemented via a dedicated controller, running as a Pod in your Kubernetes cluster. Following diagram shows how the event listener works:

![Tekton Events Listening Overview](assets/images/tekton_event_listener_overview.png)

In this blueprint you will use Tekton event listeners and triggers to respond to GitHub push events, and run the CI pipeline used to build and publish your custom application image to a remote Docker registry.

Please visit the [official project page](https://tekton.dev/docs/triggers) for more information and details about Tekton event listeners and triggers.

### Tekton Catalog

[Tekton Catalog](https://hub.tekton.dev) is a collection of reusable tasks that you can use in your pipelines. The main idea is to promote the modular design of Tekton and abstract implementation details for common situations. For example, in most of the pipelines you will want to use git clone tasks, application image build tasks, push to remote registry tasks, etc.

Following listing contains a few interesting tasks to start with:

- [Git clone](https://hub.tekton.dev/tekton/task/git-clone) - clone a Git repository URL to a workspace.
- [Buildpacks](https://hub.tekton.dev/tekton/pipeline/buildpacks) - builds source into a container image using [Cloud Native Buildpacks](https://buildpacks.io).
- [ArgoCD](https://hub.tekton.dev/tekton/task/argocd-task-sync-and-wait) - deploys an Argo CD application and waits for it to be healthy.

Please visit the [Tekton Catalog](https://github.com/tektoncd/catalog) GitHub project page to learn more.

### Tekton Dashboard

Tekton Dashboard is a web-based interface for Tekton Pipelines and Tekton triggers resources. It allows you to manage and view Tekton resource creation, execution, and completion.

Tekton Dashboard supports:

- Filtering resources by label.
- Realtime view of PipelineRun and TaskRun logs.
- View resource details and YAML.
- Show resources for the whole cluster or limit visibility to a particular namespace.
- Import resources directly from a git repository.
- Adding functionality through extensions.

Please visit the [Tekton Dashboard](https://github.com/tektoncd/dashboard) GitHub project page to learn more.

## Getting to Know Argo CD

[Argo CD](https://argoproj.github.io/cd) is a popular open source implementation for doing GitOps continuous delivery (CD) on top of Kubernetes. Your applications, definitions, configurations, and environments should be declarative and version controlled. Also application deployment and lifecycle management should be automated, auditable, and easy to understand. All this can be done using Argo.

Argo CD adheres to the same GitOps patterns and principles, thus maintaining your cluster state using a declarative approach. Synchronization happens via a Git repository, where your Kubernetes manifests are being stored. Kubernetes manifests can be specified in several ways:

- [Kustomize](https://kustomize.io) applications.
- [Helm](https://helm.sh) charts.
- [Ksonnet](https://ksonnet.io) applications.
- [Jsonnet](https://jsonnet.org) files.
- Plain directory of YAML/json manifests.
- Any custom config management tool configured as a config management plugin.

Why Argo and not Tekton for the CD part ?

While you can accomplish CD using Tekton as well, Argo is more specialized for this task. It's true that every CI systems can be used to perform deployments as well, but it implies more steps and logic to accomplish the same thing. Traditionally, you would use all kind of scripts and glue logic to create the CD part inside a CI system (take Jenkins as an example). Soon you will notice that it's unnatural, hence a dedicated CD solution is more appropriate.

Other important aspects to consider:

1. How do I implement GitOps?
2. How easy can I deploy to multiple environments and Kubernetes clusters?
3. What happens if my CI/CD system goes down?

First, the most important aspect is to have a setup where a specialized system takes care of the CD part, and doesn't interfere or it's not dependent on the CI part. If the CI system goes down for some reason, it shouldn't affect the CD part and vice-versa. On the other hand, a system or a component that does multiple things at once can be prone to failure in accomplishing both. So, it's best to follow the single responsibility principle in general, and let Tekton take care of the CI part, and Argo to handle CD. On top of that, you can use Argo to deploy and maintain configuration for system applications used in this blueprint as well, such as Tekton and Knative.

### Applications

Argo CD is using the [Application](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#applications) core concept to manage applications deployment and lifecycle. Inside an Argo CD application manifest you define the Git repository hosting your application definitions, as well as the corresponding Kubernetes cluster to deploy applications. In other words, an Argo CD application defines the relationship between a source repository and a Kubernetes cluster. It's a very concise and scalable design, where you can associate multiple sources (Git repositories) and corresponding Kubernetes clusters.

A major benefit of using applications is that you don't need to deploy Argo to each cluster individually. You can use a dedicated cluster for Argo, and deploy applications to all clusters at once from a single place. This way, you avoid Argo CD downtime or loss, in case other environments have issues or get decommissioned.

### Projects

You can group similar applications into a [Project](https://argo-cd.readthedocs.io/en/stable/user-guide/projects). Projects permit logical grouping of applications and associated roles/permissions, when working with multiple teams. When not specified, each new application belongs to the `default` project. The `default` project is created automatically, and it doesn't have any restrictions. The default project can be modified, but not deleted.

This tutorial is using the `default` project in all examples.

Please visit the official documentation website to read more about Argo CD [core concepts](https://argo-cd.readthedocs.io/en/stable/core_concepts).

In this blueprint you will learn how to use Argo CD to continuously deploy code changes for your custom applications.

## Getting to Know Knative

[Knative](https://knative.dev) is an open-source solution to build and deploy serverless applications using Kubernetes as the underlying platform. In addition to application development, developers may also have infrastructure tasks such as maintaining Kubernetes manifests for application deployment, rolling back to a previous revision, traffic routing, scaling up or down workloads to meet load demand, etc.

Knative reduces the boilerplate needed for spinning up workloads in Kubernetes, such as creating deployments, services, ingress objects, etc. Knative also helps you implement best practices in production systems (e.g. blue-green, canary deployments), application observability (logs and metrics), and support for event-driven applications.

Knative has two main components:

- [Serving](https://knative.dev/docs/serving): Abstracts all required parts needed for your application to run and be accessible to the outside world.
- [Eventing](https://knative.dev/docs/eventing): Adds support for event based programming, thus making it easy to create event driven architectures.

### Serving Component

This blueprint makes use of the Knative Serving component to run and expose a sample web application ([2048 game](https://en.wikipedia.org/wiki/2048_(video_game))) for testing Knative Services. You will also learn how to run serverless applications by creating Knative Services (not to be confused with Kubernetes Services).

For each application you want to run and expose publicly via Knative, you need to create a Knative Service CRD. A Knative Service represents the basic unit of execution for the Knative Serving component. Going further, a Knative Service resource takes care of abstracting all the details needed to run and expose your application, such as: creating Kubernetes deployments (including autoscaling), services, ingress configurations, etc.

Knative can automatically scale down your applications to zero when not in use or idle (for example, when no HTTP traffic is present), which make your applications serverless.

Knative Serving features include:

- Deploy serverless applications quickly.
- Autoscaling for application pods (down scaling to zero is supported).
- Point-in-time snapshots for application code and configurations (via revisions).
- Routing and network programming. Supports multiple networking layers, like: Kourier, Contour, Istio.

### Eventing Component

The Knative Eventing component is used in this blueprint to connect GitHub events source with Tekton Pipelines for automatic triggering of the CI flow. The Tekton CI pipeline rebuilds the application image whenever a git push event is triggered by the GitHub repository hosting the application source code.

Knative Eventing helps address common tasks for cloud native development such as:

- Enabling late-binding for event sources and consumers.
- Loose coupling between services, thus making easy to deploy individual application components.
- Various services can be connected without modifying consumers or producers, thus facilitating building new applications.

Event-driven architectures allow loose coupling between components in the system. This has a tremendous advantage, meaning that new functionality can be added easily, without interfering or breaking other components. Event-based architectures use a message broker such as [Apache Kafka](https://kafka.apache.org/) or [RabbitMQ](https://www.rabbitmq.com/) (or an `in-memory` one - not recommended for production systems). Using brokers abstracts the details of event routing from the event producer and event consumer. In other words, applications need not to worry how a message (or event) travels from point A to B. The broker takes care of all the details, and routes each message (or event) correctly from the source to the destination (or multiple destinations).

For more information about Knative and its features, please visit the [official documentation website](https://knative.dev/docs).

## Getting to Know Cert-Manager

[Cert-Manager](https://cert-manager.io) is an open-source certificate management tool designed to work with Kubernetes. It supports all the required operations for obtaining, renewing, and using SSL/TLS certificates. Cert-Manager can talk with various certificate authorities (CAs), like [Let's Encrypt](https://letsencrypt.org), [HashiCorp Vault](https://www.vaultproject.io), and [Venafi](https://www.venafi.com). It can also automatically issue valid certificates for you and renew them before they expire.

SSL/TLS certificates secure your connections and data by verifying the identity of hosts/sites and encrypting your data. Cert-Manager manages them by integrating with your Kubernetes cluster's Ingress Controller, which is your cluster's main entry point and sits in front of its backend services. Then, you can provide identity information to users by presenting them a valid SSL/TLS certificate whenever they visit your website(s).

This blueprint configures Knative Serving to work with Cert-Manager, and enables automatic creation and renewal of TLS certificates for each Knative Service. The Knative component providing the auto TLS features is called [net-certmanager](https://github.com/knative-sandbox/net-certmanager), and it's a separate project developed by Knative.

Cert-Manager relies on several CRDs to do its work and obtain the final TLS certificates for your domain. Most important ones are:

- [Issuer](https://cert-manager.io/docs/concepts/issuer): Defines a `namespaced` certificate issuer, allowing you to use `different CAs` in each `namespace`.
- [ClusterIssuer](https://cert-manager.io/docs/concepts/issuer): Similar to `Issuer`, but it doesn't belong to a namespace, hence can be used to `issue` certificates in `any namespace`.
- [Certificate](https://cert-manager.io/docs/concepts/certificate): Defines a `namespaced` resource that references an `Issuer` or `ClusterIssuer` for issuing certificates.

In this blueprint, you will make use of the cluster based issuer (`ClusterIssuer`) provided by Cert-Manager to enable TLS termination for the default Knative Ingress Controller (`Kourier`). Next, the `net-certmanager` component of Knative takes care of managing the TLS certificates automatically for you via the `ClusterIssuer` resource.

For more information about Cert-Manager and its features, please visit the [official documentation website](https://cert-manager.io/docs).

Next, you will install each software component required by this guide using the DigitalOcean marketplace collection of 1-click apps for Kubernetes.

## Step 1 - Installing Cert-Manager

Cert-Manager is available and ready to install as a [1-click Kubernetes application](https://marketplace.digitalocean.com/apps/cert-manager) from the DigitalOcean Marketplace. To install Cert-Manager please navigate to the [1-click application link](https://marketplace.digitalocean.com/apps/cert-manager) from the DigitalOcean marketplace. Then, click on the `Install App` button from the right side, and follow the instructions:

![Cert-Manager 1-click App Install](assets/images/certmanager_1-click_app_install.png)

After finishing the UI wizard, you should see the new application listed in the `Marketplace` tab of your Kubernetes cluster. The output looks similar to:

![Cert-Manager 1-click App Listing](assets/images/mp_1-click_apps_listing_cm.png)

Finally, check if the installation was successful by following the [Getting started after deploying Cert-Manager](https://marketplace.digitalocean.com/apps/cert-manager) section from the Cert-Manager 1-click app documentation page.

Next, you will install `Tekton` 1-click app using the DigitalOcean marketplace.

## Step 2 - Installing Tekton

Tekton installation is divided in two parts:

1. [Tekton Pipelines](https://github.com/tektoncd/pipeline) - represents the main component of Tekton and provides pipelines support (as well as other core components, such as Tasks).
2. [Tekton Triggers](https://github.com/tektoncd/triggers) - additional component providing support for triggering pipelines whenever events emitted by various sources (such as GitHub) are detected.

Tekton Pipelines is available and ready to install as a [1-click Kubernetes application](https://marketplace.digitalocean.com/apps/tekton-pipelines) from the DigitalOcean Marketplace. On the other hand, Tekton triggers is not at this time of writing, so it will be installed using `kubectl`.

Next, you will start by provisioning `Tekton Pipelines` on your Kubernetes cluster via the [DigitalOcean Marketplace](https://marketplace.digitalocean.com).

### Provisioning Tekton Pipelines

To install Tekton Pipelines please navigate to the [1-click application link](https://marketplace.digitalocean.com/apps/tekton-pipelines) from the DigitalOcean marketplace. Then, click on the `Install App` button from the right side, and follow the instructions:

![Tekton Pipelines 1-click App Install](assets/images/tekton_pipelines_1-click_app_install.png)

After finishing the UI wizard, you should see the new application listed in the `Marketplace` tab of your Kubernetes cluster. The output looks similar to:

![Tekton Pipelines 1-click App Listing](assets/images/mp_1-click_apps_listing.png)

Finally, check if the installation was successful by following the [Getting started after deploying Tekton Pipelines](https://marketplace.digitalocean.com/apps/tekton-pipelines) section from the Tekton Pipelines 1-click app documentation page.

Next, you will continue with provisioning `Tekton Triggers` on your Kubernetes cluster using `kubectl`.

### Provisioning Tekton Triggers

Tekton Triggers is not available as a 1-click application yet, so it will be installed using `kubectl` as recommended in the [official installation page](https://tekton.dev/docs/triggers/install/#installing-tekton-triggers-on-your-cluster). Please run below commands to install Tekton Triggers and dependencies using `kubectl` (latest stable version available at this time of writing is [v0.19.1](https://github.com/tektoncd/triggers/releases/tag/v0.19.1)):

```shell
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/previous/v0.19.1/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/previous/v0.19.1/interceptors.yaml
```

**Note:**

Tekton Triggers requires Tekton Pipelines to be installed first as a dependency (covered in the [Provisioning Tekton Pipelines](#provisioning-tekton-pipelines) section of this guide). By default it will use the same namespace to create required resources - `tekton-pipelines`.

Next, check if the Tekton Triggers installation was successful:

```shell
kubectl get pods --namespace tekton-pipelines -l app.kubernetes.io/part-of=tekton-triggers
```

The output looks similar to:

```text
NAME                                                 READY   STATUS    RESTARTS   AGE
tekton-triggers-controller-75b9b7b77d-5nk76          1/1     Running   0          2m
tekton-triggers-core-interceptors-7769dc7cbc-8hjkn   1/1     Running   0          2m
tekton-triggers-webhook-79c866dc85-xz64m             1/1     Running   0          2m
```

All `tekton-triggers` pods should be running and healthy. You can also list installed Tekton components and corresponding version using Tekton CLI:

```shell
tkn version
```

The output looks similar to:

```text
Client version: 0.23.1
Pipeline version: v0.29.0
Triggers version: v0.19.1
```

Next, you will continue with provisioning `Tekton Dashboard` on your Kubernetes cluster using `kubectl`.

### Provisioning Tekton Dashboard

Tekton Dashboard is not available as a 1-click application yet, so it will be installed using `kubectl` as recommended in the [official installation page](https://github.com/tektoncd/dashboard/blob/main/docs/install.md). Please run below commands to install Tekton Dahsboard and dependencies using `kubectl` (latest stable version available at this time of writing is [v0.25.0](https://github.com/tektoncd/dashboard/releases/tag/v0.25.0)):

```shell
kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/previous/v0.25.0/tekton-dashboard-release.yaml
```

**Note:**

Tekton Dashboard requires Tekton Pipelines to be installed first as a dependency (covered in the [Provisioning Tekton Pipelines](#provisioning-tekton-pipelines) section of this guide). By default it will use the same namespace to create required resources - `tekton-pipelines`.

Next, check if the Tekton Dashboard installation was successful:

```shell
kubectl get pods --namespace tekton-pipelines -l app.kubernetes.io/part-of=tekton-dashboard
```

The output looks similar to:

```text
NAME                                READY   STATUS    RESTARTS   AGE
tekton-dashboard-56fcdc6756-p848r   1/1     Running   0          5m
```

All `tekton-dashboard` pods should be running and healthy. You can also list installed Tekton components and corresponding version using Tekton CLI:

```shell
tkn version
```

The output looks similar to:

```text
Client version: 0.23.1
Pipeline version: v0.29.0
Triggers version: v0.19.1
Dashboard version: v0.25.0
```

The Tekton dashboard can be accessed by port-forwarding the associated Kubernetes service. First, check what service is associated via:

```shell
kubectl get svc --namespace tekton-pipelines -l app.kubernetes.io/part-of=tekton-dashboard
```

The output looks similar to (notice that it's named `tekton-dashboard` and listening on port `9097`):

```text
NAME               TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
tekton-dashboard   ClusterIP   10.245.127.170   <none>        9097/TCP   23s
```

Now, port-forward the `tekton-dashboard` Kubernetes service:

```shell
kubectl port-forward svc/tekton-dashboard -n tekton-pipelines 9097:9097
```

Finally, open a web browser and navigate to [localhost:9097](http://localhost:9097). You should see the welcome page:

![Tekton Dashboard Welcome Page](assets/images/tekton_dashboard_welcome_page.png)

Next, you will install Argo CD 1-click app using the DigitalOcean marketplace.

## Step 3 - Installing Argo CD

Argo CD is available and ready to install as a [1-click Kubernetes application](https://marketplace.digitalocean.com/apps/argocd) from the DigitalOcean Marketplace. To install Argo CD please navigate to the [1-click application link](https://marketplace.digitalocean.com/apps/argocd) from the DigitalOcean marketplace. Then, click on the `Install App` button from the right side, and follow the instructions:

![Argo CD 1-click App Install](https://link)

After finishing the UI wizard, you should see the new application listed in the `Marketplace` tab of your Kubernetes cluster. The output looks similar to:

![Argo CD 1-click App Listing](https://link)

Finally, check if the installation was successful by following the [Getting started after deploying Argo CD](https://marketplace.digitalocean.com/apps/argocd) section from the Argo CD 1-click app documentation page.

Next, you will install `Knative` 1-click app using the DigitalOcean marketplace.

## Step 4 - Installing Knative

Knative is available and ready to install as a [1-click Kubernetes application](https://marketplace.digitalocean.com/apps/knative) from the DigitalOcean Marketplace. To install Knative please navigate to the [1-click application link](https://marketplace.digitalocean.com/apps/knative) from the DigitalOcean marketplace. Then, click on the `Install App` button from the right side, and follow the instructions:

![Knative 1-click App Install](assets/images/knative_1-click_app_install.png)

After finishing the UI wizard, you should see the new application listed in the `Marketplace` tab of your Kubernetes cluster. The output looks similar to:

![Knative 1-click App Listing](assets/images/mp_1-click_apps_listing.png)

Finally, check if the installation was successful by following the [Getting started after deploying Knative](https://marketplace.digitalocean.com/apps/knative) section from the Knative 1-click app documentation page.

**Important note:**

The Knative 1-click app installs both `Knative Serving` and `Eventing` components in your DOKS cluster.

### Configuring DigitalOcean Domain Records for Knative

In this section, you will configure DNS within your DigitalOcean account, using a domain that you own. Then, you will create a wildcard record to match a specific set of hosts/subdomains under your root domain (even if they don't exist yet). This simplifies the process because Knative Services follow a specific pattern, such as: `*.<k8s_namespace>.<your_root_domain>`. Please bear in mind that DigitalOcean is not a domain name registrar. You need to buy a domain name first from [Google](https://domains.google), [GoDaddy](https://uk.godaddy.com), etc.

First, please issue the below command to register your domain with DigitalOcean (make sure to replace the `<>` placeholders with your own domain name):

```shell
doctl compute domain create "<YOUR_DOMAIN_NAME_HERE>"
```

The output looks similar to the following (`starter-kit.online` domain is used as an example here):

```text
Domain                TTL
starter-kit.online    0
```

**Note:**

**YOU NEED TO ENSURE THAT YOUR DOMAIN REGISTRAR IS CONFIGURED TO POINT TO DIGITALOCEAN NAME SERVERS**. More information on how to do that is available [here](https://www.digitalocean.com/community/tutorials/how-to-point-to-digitalocean-nameservers-from-common-domain-registrars).

Next, you will add a wildcard record (of type `A`) for the Kubernetes namespace used in this guide (`default` in this case, but can be any of your choice). First, you need to identify the load balancer external IP created by the Knative Serving component:

```shell
kubectl get svc -n knative-serving
```

The output looks similar to (notice the `EXTERNAL-IP` column value for the `kourier` service):

```text
NAME                         TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)                           AGE
activator-service            ClusterIP      10.245.219.95    <none>          9090/TCP,8008/TCP,80/TCP,81/TCP   4h30m
autoscaler                   ClusterIP      10.245.42.109    <none>          9090/TCP,8008/TCP,8080/TCP        4h30m
autoscaler-bucket-00-of-01   ClusterIP      10.245.236.8     <none>          8080/TCP                          4h30m
autoscaler-hpa               ClusterIP      10.245.230.149   <none>          9090/TCP,8008/TCP                 4h30m
controller                   ClusterIP      10.245.13.134    <none>          9090/TCP,8008/TCP                 4h30m
domainmapping-webhook        ClusterIP      10.245.113.122   <none>          9090/TCP,8008/TCP,443/TCP         4h30m
kourier                      LoadBalancer   10.245.23.78     159.65.208.64   80:31060/TCP,443:31014/TCP        4h30m
kourier-internal             ClusterIP      10.245.25.137    <none>          80/TCP                            4h30m
net-certmanager-controller   ClusterIP      10.245.0.224     <none>          9090/TCP,8008/TCP                 4h30m
net-certmanager-webhook      ClusterIP      10.245.204.61    <none>          9090/TCP,8008/TCP,443/TCP         4h30m
net-kourier-controller       ClusterIP      10.245.32.241    <none>          18000/TCP                         4h30m
webhook                      ClusterIP      10.245.151.117   <none>          9090/TCP,8008/TCP,443/TCP         4h30m
```

Then, add the wildcard record (please replace the <> placeholders accordingly). The `default` Kubernetes namespace is assumed. You can change the `TTL` value as per your requirement:

```shell
doctl compute domain records create "<YOUR_DOMAIN_NAME_HERE>" \
  --record-name "*.default.<YOUR_DOMAIN_NAME_HERE>" \
  --record-data "<YOUR_KOURIER_LOAD_BALANCER_EXTERNAL_IP_ADDRESS_HERE>" \
  --record-type "A" \
  --record-ttl "30"
```

For example, if the domain name is `starter-kit.online`, and the Kourier LoadBalancer has an external IP value of `159.65.208.64`, then the above command becomes:

```shell
doctl compute domain records create "starter-kit.online" \
  --record-name "*.default.starter-kit.online" \
  --record-data "159.65.208.64" \
  --record-type "A" \
  --record-ttl "30"
```

Finally, you can check the records created for the `starter-kit.online` domain:

```shell
doctl compute domain records list starter-kit.online
```

The output looks similar to:

```text
ID           Type    Name         Data                    Priority    Port    TTL     Weight
274640149    SOA     @            1800                    0           0       1800    0
274640150    NS      @            ns1.digitalocean.com    0           0       1800    0
274640151    NS      @            ns2.digitalocean.com    0           0       1800    0
274640152    NS      @            ns3.digitalocean.com    0           0       1800    0
309782452    A       *.default    159.65.208.64           0           0       3600    0
```

### Enabling Knative Services Auto TLS Feature via Cert-Manager

Knative is able to enable TLS termination for all your services (existing or new ones), and automatically fetch or renew TLS certificates from [Let's Encrypt](https://letsencrypt.org). This feature is provided via [cert-manager](https://cert-manager.io) and a special component (or adapter) named [net-certmanager](https://github.com/knative-sandbox/net-certmanager).

First, you need to create a [ClusterIssuer](https://cert-manager.io/docs/concepts/issuer) CRD for cert-manager. This blueprint provides a ready to use manifest which can be installed using `kubectl`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: kn-letsencrypt-http01-issuer
spec:
  acme:
    privateKeySecretRef:
      name: kn-letsencrypt
    server: https://acme-v02.api.letsencrypt.org/directory
    solvers:
      - http01:
          ingress:
            class: kourier
```

Explanations for the above configuration:

- `spec.acme.privateKeySecretRef.name` - defines what name should be given to the private key of the TLS certificate (must be unique).
- `spec.acme.server` - this is the Let's Encrypt server endpoint used to issue certificates.
- `spec.acme.solvers` - defines acme client challenge type and what ingress class to use (above configuration is using the HTTP-01 challenge, and Knative Kourier ingress controller).

Next, clone the `container-blueprints` repo:

```shell
git clone https://github.com/digitalocean/container-blueprints.git
```

Now, change directory to your local clone and apply the Knative ClusterIssuer manifest using `kubectl`:

```shell
kubectl apply -f DOKS-CI-CD/assets/manifests/knative-serving/kn-cluster-issuer.yaml
```

Check the ClusterIssuer state:

```shell
kubectl get clusterissuer kn-letsencrypt-http01-issuer
```

The output looks similar to:

```text
NAME                           READY   AGE
kn-letsencrypt-http01-issuer   True    22h
```

The ClusterIssuer `READY` column should print `True`.

Next, you will configure and then test a CI/CD pipeline for a sample application (the [2048 game](https://en.wikipedia.org/wiki/2048_(video_game))), using Tekton Pipelines and Argo CD. You will also learn how to automatically trigger the pipeline on GitHub events (e.g. when pushing commits), using the Tekton Triggers component.

## Step 5 - Setting Up Your First CI/CD Pipeline Using Tekton and Argo

In this part, you will set up a Tekton CI Pipeline that builds a Docker image for your custom application using Kaniko, and publishes it to a remote Docker registry. Then, the Tekton pipeline will trigger Argo CD to deploy the application to your Kubernetes cluster. The web application used in this tutorial is a implementation for the [2048 game](https://en.wikipedia.org/wiki/2048_(video_game)).

At a high level overview, the following steps are involved:

1. Implementing the CI/CD Pipeline workflow using Tekton and Argo CD.
2. Configuring Tekton Triggers for automatic triggering of the CI/CD Pipeline by Git events (e.g. pushing commits).

Next, the CI/CD implementation part is comprised of:

1. Fetching sample application source code from Git.
2. Build application code and store the resulting artifact(s) as well as dependencies in a Docker image.
3. Push the sample application image to the specified Docker registry.
4. Trigger Argo CD to deploy the sample application in your Kubernetes cluster.

Finally, configuring the CI/CD pipeline to trigger on Git events is comprised of:

1. Setting up an `EventListener` that accepts and processes GitHub push events.
2. Setting up a `TriggerTemplate` that instantiates a `PipelineResource` and executes a `PipelineRun` and its associated `TaskRuns` when the `EventListener` detects the `push event` from your `GitHub` repository.
3. Setting up a `TriggerBinding` resource to populate the `TriggerTemplate` input parameters with data extracted from the GitHub event.

Below diagram illustrates the CI/CD process implemented using Tekton and Argo:

![Tekton Pipeline Overview](assets/images/tekton_pipeline_overview.png)

## Step 5 - Testing the CI/CD Setup

## Conclusion

## Additional Resources
