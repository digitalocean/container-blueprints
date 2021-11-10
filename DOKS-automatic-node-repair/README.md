# Replacing Unhealthy DOKS Cluster Nodes Automatically

This tutorial provides an automated way to recycle unhealthy nodes in a DigitalOcean Kubernetes (DOKS) cluster.  When a node in a DOKS cluster is unhealthy, it is a manual and cumbersome process to replace the node. Without replacing the nodes, the cluster will operate at lower capacity because the unhealthy nodes will not run any Pods. 

You can automatically replace unhealthy nodes using one of the following applications:

 - [Digital Mobius](https://github.com/Qovery/digital-mobius)
 
 - [Draino](https://github.com/planetlabs/draino) and [Kubernetes Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)

For this tutorial, we will deploy Digital Mobius on a running DOKS cluster. Digital Mobius is an open-source application written in Go and is specifically built for DOKS cluster nodes recycling. The application monitors DOKS cluster nodes that are in an unhealthy state at specified regular interval. A node is considered to be unhealthy if the [node condition](https://kubernetes.io/docs/concepts/architecture/nodes/#condition) is `Ready` and the status is `False` or `Unknown`. The application recreates the affected node(s) using the DigitalOcean [Delete Kubernetes Node API](https://docs.digitalocean.com/reference/api/api-reference/#operation/delete_kubernetes_node). It is [Helm chart-ready](https://github.com/Qovery/digital-mobius/tree/main/charts/Digital-Mobius) and available for easy Kubernetes deployment (or [artifacthub.io](https://artifacthub.io/packages/helm/digital-mobius/digital-mobius)).

The following diagram shows how Digital Mobius checks the worker node(s) state:

 ![Digital Mobius Flow](https://github.com/digitalocean/container-blueprints/blob/main/DOKS-automatic-node-repair/content/img/digital-mobius-flow.png?raw=true)

## Prerequisites

To complete this tutorial, you will need:

- A [DigitalOcean access token](https://docs.digitalocean.com/reference/api/create-personal-access-token) for managing the DOKS cluster. Ensure that the access token has read-write scope.

Copy the token value and save it in a local environment variable to use later:

```bash
export DIGITALOCEAN_TOKEN="<your_do_personal_access_token>"
```

- [`doctl`](https://docs.digitalocean.com/reference/doctl/how-to/install) for interacting with the DOKS cluster.

Initialize `doctl` using the following command:
   
 ```bash
 doctl auth init --access-token "$DIGITALOCEAN_TOKEN"
 ```

## STEP 1: Cloning the Sample GitHub Repository

Clone the repository on your local machine and navigate to the appropriate directory:

```shell
git clone https://github.com/digitalocean/container-blueprints.git

cd container-blueprints/DOKS-automatic-node-repair
```

## STEP 2: Creating a DOKS Cluster

1. Spin up the cluster and wait for it to be provisioned:

```bash
export CLUSTER_NAME="mobius-testing-cluster"
export CLUSTER_REGION="lon1"                  # choose a region that is more close to you using doctl k8s options regions
export CLUSTER_NODE_SIZE="s-2vcpu-4gb"
export CLUSTER_NODE_COUNT=2                   # need 2 nodes at least to test the real world scenario
export CLUSTER_NODE_POOL_NAME="mbt-np"
export CLUSTER_NODE_POOL_TAG="mbt-cluster"
export CLUSTER_NODE_POOL_LABEL="type=basic"

doctl k8s cluster create "$CLUSTER_NAME" \
  --auto-upgrade=false \
  --node-pool "name=${CLUSTER_NODE_POOL_NAME};size=${CLUSTER_NODE_SIZE};count=${CLUSTER_NODE_COUNT};tag=${CLUSTER_NODE_POOL_TAG};label=${CLUSTER_NODE_POOL_LABEL}" \
      --region "$CLUSTER_REGION"
```

The output looks similar to the following:

```
Notice: Cluster is provisioning, waiting for cluster to be running
......................................................................
Notice: Cluster created, fetching credentials
Notice: Adding cluster credentials to kubeconfig file found in "~/.kube/config"
Notice: Setting current-context to do-lon1-mobius-testing-cluster
ID                                      Name                       Region    Version        Auto Upgrade    Status     Node Pools
11bdd0f1-8bd0-42dc-a3af-7a83bc319295    mobius-testing-cluster     lon1      1.21.2-do.2    false           running    basicnp
```

2. [Authenticate](https://docs.digitalocean.com/products/kubernetes/how-to/connect-to-cluster/#doctl) your cluster:

```shell
doctl k8s cluster kubeconfig save <your_doks_cluster_name>
```

3. [Check that the current context](https://docs.digitalocean.com/products/kubernetes/how-to/connect-to-cluster/#contexts) points to your cluster:

```shell
kubectl config get-contexts
```

4. Get the worker nodes status:

```bash
kubectl get nodes
```

The output looks similar to the following:

```
NAME            STATUS   ROLES    AGE     VERSION
basicnp-8k4ep   Ready    <none>   2m52s   v1.21.2
basicnp-8k4es   Ready    <none>   2m16s   v1.21.2
```

## STEP 3: Configuring Digital Mobius

Digital Mobius needs a set of environment variables to be configured and available. You can see these variables in the [Helm Chart  values file](https://github.com/Qovery/digital-mobius/blob/main/charts/Digital-Mobius/values.yaml):

```
LOG_LEVEL: "info"
DELAY_NODE_CREATION: "10m"                                  # A worker node gets recycled after being unhealthy for this period of time
DIGITALOCEAN_TOKEN: "<your_digitalocean_api_token>"       # Personal DO API token value
DIGITALOCEAN_CLUSTER_ID: "<your_digitalocean_cluster_id>" # DOKS cluster ID that needs to be monitored
```

You must specify the DigitalOcean API token `DIGITALOCEAN_TOKEN`, the Cluster ID `DIGITALOCEAN_CLUSTER_ID`, and the node creation delay time interval `DELAY_NODE_CREATION` in seconds or minutes, such as, `10s` or `10m`.

**Note:**

Choose an appropriate value for `DELAY_NODE_CREATION`. A value that is too low will interfere with the time interval needed for a node to become ready and available after it gets recycled. From real-world situations, this can take several minutes or more to complete. A good starting point is `10m`, which is the value used in this tutorial.

## STEP 4: Deploying Digital Mobius

Use Helm to perform the deployment:

1. Add the required Helm repository:

    ```bash
    helm repo add digital-mobius https://qovery.github.io/digital-mobius
    ```
    
2. Fetch the cluster ID that you want to monitor for node failures:

    ```bash
    doctl k8s cluster list
    export DIGITALOCEAN_CLUSTER_ID="<your_cluster_id_here>"
    ```

    **Hint:**
  
    If you have only one cluster, then you can use `jq`:

    ```bash
    export DIGITALOCEAN_CLUSTER_ID="$(doctl k8s cluster list -o json | jq -r '.[].id')"
    echo "$DIGITALOCEAN_CLUSTER_ID"
    ```
    
3. Set the DigitalOcean access token:

    ```bash
    export DIGITALOCEAN_TOKEN="<your_do_personal_access_token>"
    echo "$DIGITALOCEAN_TOKEN"
    ```
    
4. Start the deployment in a dedicated namespace. This example uses `maintenance` as the namespace:

    ```bash
    helm install digital-mobius digital-mobius/digital-mobius --version 0.1.4 \
      --set environmentVariables.DIGITALOCEAN_TOKEN="$DIGITALOCEAN_TOKEN" \
      --set environmentVariables.DIGITALOCEAN_CLUSTER_ID="$DIGITALOCEAN_CLUSTER_ID" \
      --set enabledFeatures.disableDryRun=true \
      --namespace maintenance --create-namespace
    ```
    **Note:**

    The `enabledFeatures.disableDryRun` option enables or disables the `DRY RUN` mode of the tool. Setting it to `true` which means that the dry run mode is disabled and the clutser nodes will be recycled. Enabling the dry run mode is helpful if you want to test it first without performing any changes to the real cluster nodes.

5. Check the deployment once it completes.

    List the deployments:

    ```bash
    helm ls -n maintenance
    ```

    The output looks similar to the following:
    ```
    NAME            NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                   APP VERSION
    digital-mobius  maintenance     1               2021-08-06 11:24:10.131055 +0300 EEST   deployed        digital-mobius-0.1.4    0.1.4 
    ```

    Verify the running Pod(s):

    ```bash
    kubectl get pods -n maintenance
    ```

    The output looks similar to the following:
    ```
    NAME                             READY   STATUS    RESTARTS   AGE
    digital-mobius-55fbc9fdd-dzxbh   1/1     Running   0          8s
    ```

    Inspect the logs:

    ```bash
    kubectl logs -l app.kubernetes.io/name=digital-mobius -n maintenance
    ```

    The output looks similar to the following:
    ```
        _ _       _ _        _                      _     _           
     __| (_) __ _(_) |_ __ _| |     _ __ ___   ___ | |__ (_)_   _ ___ 
    / _` | |/ _` | | __/ _` | |    | '_ ` _ \ / _ \| '_ \| | | | / __|
    | (_|| | (_| | | || (_| | |    | | | | | | (_) | |_) | | |_| \__ \
    \__,_|_|\__, |_|\__\__,_|_|    |_| |_| |_|\___/|_.__/|_|\__,_|___/
            |___/                                                     
    time="2021-08-06T08:29:52Z" level=info msg="Starting Digital Mobius 0.1.4
    ```

## STEP 5: Testing the Digital Mobius Setup

To test the Digital Mobius setup, we disconnect one or more of the DOKS cluster nodes. In order to achieve this, kill the kubelet service from the corresponding worker node(s) using [doks-debug](https://github.com/digitalocean/doks-debug). This creates some debug pods, which run containers in the privileged mode. Then, use `kubectl exec` to execute commands in one of the running containers and get access to the worker node system services.

1. Create DOKS debug pods:

Create a DaemonSet. This will spin up the debug pods in the `kube-system` namespace:
   
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/digitalocean/doks-debug/master/k8s/daemonset.yaml
   ```

Verify the DaemonSet:

   ```bash
   kubectl get ds -n kube-system
   ```

   The output looks similar to the following (notice the `doks-debug` entry):

   ```
   NAME            DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR                 AGE
   cilium          2         2         2       2            2           <none>                        22h
   csi-do-node     2         2         2       2            2           <none>                        2d21h
   do-node-agent   2         2         2       2            2           beta.kubernetes.io/os=linux   2d21h
   doks-debug      2         2         2       2            2           <none>                        112m
   kube-proxy      2         2         2       2            2           <none>                        44h
   ```

Verify the debug pods:

   ```bash
   kubectl get pods -l name=doks-debug -n kube-system
   ```

   The output looks similar to the following:

   ```
   NAME               READY   STATUS    RESTARTS   AGE
   doks-debug-m6xlj   1/1     Running   0          105m
   doks-debug-qgw2m   1/1     Running   0          115m
   ```

2. Kill the kubelet. 

Use `kubectl exec` in one of the debug pods and get access to worker node system services. Then, stop the kubelet service, which results in the node going away from the `kubectl get nodes` command output.

Open a new terminal window and watch the worker nodes:

    ```bash
    watch "kubectl get nodes"
    ```

Pick the first debug pod and get a shell working on it:

    ```bash
    DOKS_DEBUG_POD_NAME=$(kubectl get pods -l name=doks-debug -ojsonpath='{.items[0].metadata.name}' -n kube-system)
    kubectl exec -it "$DOKS_DEBUG_POD_NAME" -n kube-system -- bash
    ```

A prompt that looks similar to the following appears:

    ```
    root@basicnp-8hx1a:~#
    ```
Inspect the system service:

    ```bash
    chroot /host /bin/bash
    systemctl status kubelet
    ```

    The output looks similar to the following:

    ```
    ● kubelet.service - Kubernetes Kubelet Server
   Loaded: loaded (/etc/systemd/system/kubelet.service; enabled; vendor preset: enabled)
   Active: active (running) since Fri 2021-08-06 08:48:42 UTC; 2h 18min ago
    Docs: https://kubernetes.io/docs/concepts/overview/components/#kubelet
    Main PID: 1053 (kubelet)
        Tasks: 17 (limit: 4701)
    Memory: 69.3M
    CGroup: /system.slice/kubelet.service
            └─1053 /usr/bin/kubelet --config=/etc/kubernetes/kubelet.conf --logtostderr=true --image-pull-progress-deadline=5m
    ...
    ```
Stop the kubelet:

    ```bash
    systemctl stop kubelet
    ```

**Tip:**

You can also kill the kubelet service using the following command:

```bash
DOKS_DEBUG_POD_NAME=$(kubectl get pods -l name=doks-debug -ojsonpath='{.items[0].metadata.name}' -n kube-system)
kubectl exec -it "$DOKS_DEBUG_POD_NAME" -n kube-system -- chroot /host systemctl stop kubelet
```

## STEP 6: Observing the Nodes

After you stop the kubelet service, you will be kicked out of the shell session. This means that the node controller lost its connection with the affected node where the kubelet service was killed.
 
You can see the `NotReady` state of the affected node in the other terminal window where you set the watch:

```
NAME            STATUS     ROLES    AGE    VERSION
basicnp-8hc5d   Ready      <none>   28h    v1.21.2
basicnp-8hx1a   NotReady   <none>   144m   v1.21.2
```

After the time interval you specified in `DELAY_NODE_CREATION` expires, the node vanishes as expected:

```
NAME            STATUS   ROLES    AGE   VERSION
basicnp-8hc5d   Ready    <none>   28h   v1.21.2
```

Next, check how Digital Mobius monitors the DOKS cluster. Open a terminal window and inspect the logs first:

```bash
kubectl logs -l app.kubernetes.io/name=digital-mobius -n maintenance
```

The output looks like below (watch for the `Recycling node {...}` lines):

```
     _ _       _ _        _                      _     _           
  __| (_) __ _(_) |_ __ _| |     _ __ ___   ___ | |__ (_)_   _ ___ 
 / _` | |/ _` | | __/ _` | |    | '_ ` _ \ / _ \| '_ \| | | | / __|
| (_| | | (_| | | || (_| | |    | | | | | | (_) | |_) | | |_| \__ \
 \__,_|_|\__, |_|\__\__,_|_|    |_| |_| |_|\___/|_.__/|_|\__,_|___/
         |___/                                                     
time="2021-08-06T08:29:52Z" level=info msg="Starting Digital Mobius 0.1.4 \n"
time="2021-08-06T11:13:09Z" level=info msg="Recyling node {11bdd0f1-8bd0-42dc-a3af-7a83bc319295 f8d76723-2b0e-474d-9465-d9da7817a639 379826e4-8d1b-4ba4-97dd-739bbfa69023}"
...
```

In the terminal window where you set the watch for `kubectl get nodes`, a new node appears after a minute or so, and replaces the old one. The new node has a different ID and a new `AGE` value:

```
NAME            STATUS   ROLES    AGE   VERSION
basicnp-8hc5d   Ready    <none>   28h   v1.21.2
basicnp-8hoav   Ready    <none>   22s   v1.21.2
```

As you can see, the node was recycled.

## Summary

In this tutorial, we automatically recover cluster nodes in case the kubelet service dies or becomes unresponsive. This can happen when the worker node is overloaded or due to unexpected networking issues. High load can be caused if you do not follow good practices for Pod resources limits, such as not setting them at all or using inadequate values.

## Contributing

For suggestions or ideas, please open a PR or create an issue. We value your feedback!

## Credits

Credits go to [Qovery](https://github.com/Qovery) and contributors for providing the original software used in this tutorial.
