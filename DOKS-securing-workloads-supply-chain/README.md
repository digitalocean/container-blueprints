# Overview

Kubernetes gained a lot of popularity over time and for a good reason. It's widely being used today in every modern infrastructure based on microservices. Kubernetes takes away the burden of managing high availability (or HA) setups, such as scheduling and replicating workloads on different nodes, thus assuring resiliency. Then, at the networking layer it also takes care of load balancing and distributes traffic evenly to workloads. At its core, Kubernetes is a modern container scheduler offering additional features such as application configuration and secrets management, to mention a few. You can also set quotas and control applications access to various resources (such as CPU and memory) by fine tuning resource limits requests. In terms of security, you can restrict who has access to what resources via RBAC, which is an acronym standing for Resource Based Access Control.

Kubernetes has grown a lot in terms of stability and maturity in the past years. On the other hand, it has become a more complex ecosystem by leveraging more functional components. No matter where you run Kubernetes clusters (cloud or on-premise), at its core Kubernetes is divided into two major components:

1. [Control Plane](https://kubernetes.io/docs/concepts/overview/components/#control-plane-components) - takes care of scheduling your workloads (Pods) and responding to cluster events (such as starting up a new pod when a deployment's replicas field is unsatisfied).
2. [Worker Nodes](https://kubernetes.io/docs/concepts/overview/components/#node-components) - these are the actual machines running your Kubernetes workloads. Node components run on every node, maintaining running pods and providing the Kubernetes runtime environment.

Below picture shows the typical architecture of a Kubernetes cluster:

![DOKS Overview](assets/images/DOKS_Overview.png)

Cloud providers offer today ready to run Kubernetes solutions thus taking away the burden of managing the cluster itself (or the control plane component). This way, you can focus more on application development rather than spending precious time to deal with infrastructure tasks, such as maintaining the control plane components (e.g. ETCD database backups), worker nodes maintenance (e.g. performing regular OS updates and security patching), etc. DigitalOcean offers an easy to use Kubernetes platform called [DOKS](https://docs.digitalocean.com/products/kubernetes/), which stands for DigitalOcean Kubernetes. DOKS is a [managed Kubernetes](https://docs.digitalocean.com/products/kubernetes/resources/managed/) service that lets you deploy Kubernetes clusters without the complexities of handling the control plane and containerized infrastructure.

Going further, a very important aspect which is often overlooked is **security**. Security is a broader term and covers many areas such as: supply chain, infrastructure, networking, etc. Because Kubernetes is such popular nowadays it has become a potential target so care must be taken. Another aspect is system complexity which means it can have multiple weak points, thus opening doors to external attacks and exploits. Most of the security flaws are caused by improperly configured Kubernetes clusters. A typical example is cluster administrators forgetting to set RBAC rules, or allowing applications to run as root in the Pod specification. Going further, Kubernetes offers a simple but very powerful isolation mechanism (both at the application level and networking layer) - namespaces. By using namespaces, administrators can isolate application resources and configure access rules to various users and/or teams in a very well defined manner.

Approaching Kubernetes security is a multi step process, and usually consists of:

1. Securing the Control Plane:
   - Reduce surface attacks by securing the public REST API of Kubernetes (authorization, authentication, TLS encryption).
   - Regularly update the operating system kernel (Linux) to include security fixes. Also, system libraries and binaries must be updated and patched regularly.
   - Enforce network policies and configure firewalls to allow minimum to zero access if possible from the outside. Start by denying everything, and then allow only required services. **Do not expose the ETCD database publicly!**
   - Restrict access to a very limited group of people (system administrators usually).
   - Perform system checks regularly by installing/configuring an audit tool, and receive alerts in real time in case of a security breach.
2. Securing Worker Nodes. Most of the control plane recommendations apply here as well, with a few notes such as:
   - Never expose Kubelets or Kube-Proxies publicly.
   - Avoid exposing the SSH service to the public. This is recommended to reduce surface attacks.
3. Securing Kubernetes workloads and the supply chain:
   - Source code and 3rd party libraries scanning for known vulnerabilities.
   - Application container images scanning for known vulnerabilities.
   - YAML manifests scanning (avoid running Pods as root, etc).
   - Secrets management.
   - Proper configuring of RBAC policies.

**Note:**

For system administration, such as logging via SSH on the nodes you can use a VPN setup, SSH jump hosts, or both.

In case of DOKS, you don't have to worry about control plane and worker nodes security because this is already taken care by the cloud provider (DigitalOcean). That's one of the main reasons it is called a managed Kubernetes service. Still, users have access to the underlying machines (Droplets) and firewall settings, so it all circles back to administrators diligence to pay attention and not expose services or ports that are not really required.

What's left is taking measures to harden the Kubernetes workloads and applications. To build an application and run it on Kubernetes, you need a list of ingredients which are part of the so called supply chain. The supply chain is usually composed of:

- A Git repository from where your application source code is retrieved.
- Third party libraries that your application may use (fetched via a project management tool, such as npm, maven, gradle, etc).
- Docker images hosting your application.

Naturally, the next required step is to secure the supply chain. Below picture illustrates the concept better:

![alt](https://)
