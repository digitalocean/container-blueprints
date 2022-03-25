## Overview

[WordPress](https://wordpress.org/about/) is an Open Source software designed for everyone, emphasizing accessibility, performance, security, and ease of use to create a website, blog, or app. [WordPress](https://en.wikipedia.org/wiki/WordPress) is a content managment system (CMS) built on PHP and using MySQL as a data store, powering over 30% of internet sites today.

In this tutorial, we’ll use Helm for setting up [WordPress](https://wordpress.com/) on top of a Kubernetes cluster, in order to create a highly-available website. In addition to leveraging the intrinsic scalability and high availability aspects of Kubernetes, this setup will help keeping WordPress secure by providing simplified upgrade and rollback workflows via Helm.

We’ll be using an external MySQL server in order to abstract the database component, since it can be part of a separate cluster or managed service for extended availability. After completing the steps described in this tutorial, you will have a fully functional WordPress installation within a containerized cluster environment managed by Kubernetes.

## Table of Contents

- [Overview](#overview)
- [Table of Contents](#table-of-contents)
- [Prerequisites](#prerequisites)
- [Setup the DigitalOcean Managed Kubernetes Cluster (DOKS)](#setup-the-digitalocean-managed-kubernetes-cluster-doks)
- [Setup DigitalOcean’s Managed Databases MySQL](#setup-digitaloceans-managed-databases-mysql)
- [Deploy WordPress](#deploy-wordpress)
  - [Deploying the Helm Chart](#deploying-the-helm-chart)
  - [Secure traffic with TLS and Let's Encrypt SSL certificates](#secure-traffic-with-tls-and-lets-encrypt-ssl-certificates)
    - [Installing the Nginx Ingress Controller](#installing-the-nginx-ingress-controller)
    - [Installing the Cert-Mananger](#installing-the-cert-mananger)
    - [Configuring Production Ready TLS Certificates for WordPress](#configuring-production-ready-tls-certificates-for-wordpress)
  - [Confiugre plugins](#confiugre-plugins)
  - [Upgrade WordPress](#upgrade-wordpress)
- [Conclusion](#conclusion)

## Prerequisites

To complete this tutorial, you will need:

1. [Doctl](https://github.com/digitalocean/doctl/releases) CLI, for `DigitalOcean` API interaction.
2. [Kubectl](https://kubernetes.io/docs/tasks/tools) CLI, for `Kubernetes` interaction.
3. Basic knowledge on how to run and operate `DOKS` clusters. You can learn more [here](https://docs.digitalocean.com/products/kubernetes).
4. [MySQL database](https://docs.digitalocean.com/products/databases/mysql/).
5. [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/).
6. [Cert-Manager](https://cert-manager.io/docs/).

## Setup the DigitalOcean Managed Kubernetes Cluster (DOKS)

Before you begin you need to setup the DigitalOcean Managed Kubernetes Cluster (DOKS), the below example will create one for you. If you already have one configured please skip to the next chapter [Setup DigitalOcean’s Managed Databases MySQL](#setup-digitaloceans-managed-databases-mysql).

```console
doctl k8s cluster create <YOUR_CLUSTER_NAME> \
  --auto-upgrade=false \
  --maintenance-window "saturday=21:00" \
  --node-pool "name=basicnp;size=s-4vcpu-8gb-amd;count=3;tag=cluster2;label=type=basic;auto-scale=true;min-nodes=2;max-nodes=4" \
  --region nyc1
```

**Notes:**

- The example is using `4cpu/8gb` AMD nodes (`$48/month`), `3` default, and auto-scale to `2-4`. So, your cluster cost is between `$96-$192/month`, with `hourly` billing. To choose a different node type, pick from the following command `doctl compute size list`.

- Please visit [How to Set Up a DigitalOcean Managed Kubernetes Cluster (DOKS)](https://github.com/digitalocean/Kubernetes-Starter-Kit-Developers/tree/main/01-setup-DOKS) for more details.

## Setup DigitalOcean’s Managed Databases MySQL

In this section, we’ll create a dedicated MySQL database such as [DigitalOcean’s Managed Databases](https://docs.digitalocean.com/products/databases/mysql/) for WordPress. This is necessary because our WordPress installation will live on a separate server inside the Kubernetes cluster.

**Note:**

By default, the WordPress Helm chart installs MariaDB on a separate pod inside the cluster and uses it as the WordPress database, if you want to do not use an external database please continue to the next chapter [Deploy WordPress](#deploy-wordpress).

First, we create a managed database on DigitalOcean:

```console
doctl databases create wordpress-mysql --engine mysql --region nyc1
```

The output looks similar to the following (the `STATE` column should display `online`):

``` text
ID                                      Name                    Engine    Version    Number of Nodes    Region    Status      Size
2f0d0969-a8e1-4f94-8b73-2d43c68f8e72    wordpress-mysql-test    mysql     8          1                  nyc1      online    db-s-1vcpu-1gb
```

**Note:**
In order for finishing the setup for the MySQL database, the database id is required and can be extracted running `doctl databases list`.

Next, we will create the wordpress database user:

```console
doctl databases user create 2f0d0969-a8e1-4f94-8b73-2d43c68f8e72 wordpress_user
```

The output looks similar to the following (the password will be generated automatically):

```text
Name              Role      Password
wordpress_user    normal    *******
```

Next, we will create a database:

```console
doctl databases db create 2f0d0969-a8e1-4f94-8b73-2d43c68f8e72  wordpres
```

The output looks similar to the following (the password will be generated automatically):

```text
Name
wordpres
```

Finnally, we need to setup the trusted sources for the MySQL, steps to follow:

 1. First extract the Kubernetes cluster ID:

    ```console
    doctl kubernetes cluster list
    ```

    The output looks similar to the following:

    ```text
    ID                                      Name                       Region    Version         Auto Upgrade    Status     Node Pools
    c278b4a3-19f0-4de6-b1b2-6d90d94faa3b    k8s-cluster   nyc1      1.21.10-do.0    false           running    basic
    ```

 2. Finally, restrict the incoming connections:

    ```console
    doctl databases firewalls append 2f0d0969-a8e1-4f94-8b73-2d43c68f8e72 --rule k8s:c278b4a3-19f0-4de6-b1b2-6d90d94faa3b
    ````

    **Note:**

    For more details please visit [How to Secure MySQL Managed Database Clusters](https://docs.digitalocean.com/products/databases/mysql/how-to/secure/).

## Deploy WordPress

### Deploying the Helm Chart

Now it’s time to install WordPress on the cluster, the following WordPress [Helm Chart](https://github.com/bitnami/charts/tree/master/bitnami/wordpress/) will be used because is simple and easily to be configured.

**Note:**

 The critical setting are `externalDatabase` and `mariadb.enabled`, this will make WordPress to use an external database or use a different pod inside the cluster where mariadb will be configured.

First, add the `Helm` repo, and list the available `charts`:

```console
helm repo add bitnami https://charts.bitnami.com/bitnami

helm repo update bitnami
```

Next, create a YAML file `(values.yml)` to override the helm values:

```yaml
# WordPress service type
service:
  type: ClusterIP

# Enable persistence using Persistent Volume Claims
persistence:
  enabled: true
  storageClassName: do-block-storage
  accessModes: ["ReadWriteOnce"]
  size: 5Gi

# Level of auto-updates to allow. Allowed values: major, minor or none.
wordpressAutoUpdateLevel: minor

# Scheme to use to generate WordPress URLs
wordpressScheme: https

# WordPress credentials
wordpressUsername: <WORDPRESS_USER_HERE>
wordpressPassword: <WORDPRESS_PASSSWORD_HERE>

# External Database details
externalDatabase:
  host: <MYSQL_HOST_HERE>
  port: 25060
  user: <MYSQL_DB_USER_HERE>
  password: <MYSQL_DB_PASSWORD_HERE>
  database: <MYSQL_DB_NAME_HERE>

# Disabling MariaDB
mariadb:
  enabled: false

```

**Note:**

Most of the overrides are self-explanatory and can be customized. Please visit [wordpress helm values](https://github.com/bitnami/charts/blob/master/bitnami/wordpress/values.yaml) for more details.

Finally, install the chart using Helm:

```console
helm upgrade wordpress bitnami/wordpress \
    --atomic \
    --create-namespace \
    --install \
    --namespace wordpress \
    --version 13.1.4 \
    --timeout 10m0s \
    --values values.yml
```

Check Helm release status:

```console
helm ls -n wordpress
```

The output looks similar to (notice the `STATUS` column which has the `deployed` value):

```text
NAME      NAMESPACE REVISION UPDATED                              STATUS   CHART            APP VERSION
wordpress wordpress 1        2022-03-22 14:22:18.146474 +0200 EET deployed wordpress-13.1.4 5.9.2
```

Verify if the WordPress is up and running:

```console
kubectl get all -n wordpress
```

The output looks similar to (notice the wordpress, which should be UP and RUNNING):

```text
NAME                             READY   STATUS    RESTARTS   AGE
pod/wordpress-6f55c9ffbd-4frrh   1/1     Running   0          23h

NAME                TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
service/wordpress   ClusterIP   10.245.36.237   <none>        80/TCP,443/TCP   23h

NAME                        READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/wordpress   1/1     1            1           23h

NAME                                   DESIRED   CURRENT   READY   AGE
replicaset.apps/wordpress-6f55c9ffbd   1         1         1       23h
```

### Secure traffic with TLS and Let's Encrypt SSL certificates

The Bitnami WordPress Helm chart comes with built-in support for Ingress routes and certificate management through [cert-manager](https://github.com/jetstack/cert-manager). This makes it easy to configure TLS support using certificates from a variety of certificate providers, including [Let's Encrypt](https://letsencrypt.org/).

#### Installing the Nginx Ingress Controller

First, add the Helm repo, and list the available charts:

```console
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

helm repo update ingress-nginx
```

Next, install the Nginx Ingress Controller using Helm:

```console
helm install ingress-nginx ingress-nginx/ingress-nginx --version 4.0.13 \
  --namespace ingress-nginx \
  --create-namespace \
```

Finally, check if the Helm installation was successful by running command below:

```console
helm ls -n ingress-nginx
```

The output looks similar to the following (notice the `STATUS` column which has the `deployed` value):

```text
NAME            NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                   APP VERSION
ingress-nginx   ingress-nginx   1               2022-02-14 12:04:06.670028 +0200 EET    deployed        ingress-nginx-4.0.13    1.1.0
```

#### Installing the Cert-Mananger

First, add the Helm repo, and list the available charts:

```console
helm repo add jetstack https://charts.jetstack.io

helm repo update jetstack
```

Next, install the Cert-Manager using Helm:

```console
helm install cert-manager jetstack/cert-manager --version 1.6.1 \
  --namespace cert-manager \
  --create-namespace
```

Finally, check if the Helm installation was successful by running command below:

```console
helm ls -n cert-manager
```

The output looks similar to the following (notice the `STATUS` column which has the `deployed` value):

```text
NAME            NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                   APP VERSION
cert-manager    cert-manager    1               2021-10-20 12:13:05.124264 +0300 EEST   deployed        cert-manager-v1.6.1     v1.6.1
```

**Notes:**

- For advance configuration of Nginx Ingress Controller and Cert-mananger pelase visit [How to Configure Ingress using Nginx](https://github.com/digitalocean/Kubernetes-Starter-Kit-Developers/blob/main/03-setup-ingress-controller/nginx.md) for more details.

- An alternative way to install [NGINX Ingress Controller](https://marketplace.digitalocean.com/apps/nginx-ingress-controller) and [Cert-Manager](https://marketplace.digitalocean.com/apps/cert-manager) is by using the DigitalOcean market place where you can install them using 1-Click App Addon.

#### Configuring Production Ready TLS Certificates for WordPress

Before creating the certificate is required a cluster issuer to be created for cert-mananger in order to know where the certificate to be created, for eg, we will use the Let's Encrypt production. Create the following YAML file and replace <YOUR-EMAIL-HERE> with the contact email that you want the TLS certificate to show.

```yml
# letsencrypt-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
  namespace: wordpress
spec:
  acme:
    # You must replace this email address with your own.
    # Let's Encrypt will use this to contact you about expiring
    # certificates, and issues related to your account.
    email:  <YOUR-EMAIL-HERE>
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      # Secret resource used to store the account's private key.
      name: prod-issuer-account-key
    # Add a single challenge solver, HTTP01 using nginx
    solvers:
    - http01:
        ingress:
          class: nginx
```

Apply via kubectl:

```console
kubectl apply -f letsencrypt-issuer.yaml
```

To secure the traffic for WordPress, open the helm file `(value.yml)` created earlier and add the following helm values at the end:

```yaml
# Enable ingress record generation for WordPress
ingress:
  enabled: true
  certManager: true
  tls: false
  hostname: <YOUR_DOMAIN_HERE>
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  extraTls:
  - hosts:
      - <YOUR_DOMAIN_HERE>
    secretName: wordpress.local-tls
```

Upgrade via `helm`:

```console
helm upgrade wordpress bitnami/wordpress \
    --create-namespace \
    --namespace wordpress \
    --version 13.1.4 \
    --timeout 10m0s \
    --values values.yml
```

This automatically creates a certificate through cert-manager. You can then verify that you've successfully obtained the certificate by running the following command:

```console
kubectl get certificate -n wordpress wordpress.local-tls
```

If successful, the output's READY column reads True:

```text
NAME                  READY   SECRET                AGE
wordpress.local-tls   True    wordpress.local-tls   24h
```

Now, you can access the WordPress using the domain configured earlier.

### Confiugre plugins

TODO

### Upgrade WordPress

Because of its popularity, WordPress is often a target for malicious exploitation, so it’s important to keep it updated. We can upgrade Helm releases with the command helm upgrade.

First, update the helm repository:

```console
helm repo update
```

Next, upgrade WordPress to the new version:

```console
helm upgrade wordpress bitnami/wordpress \
    --atomic \
    --create-namespace \
    --install \
    --namespace wordpress \
    --version <WORDPRESS_NEW_VERSION> \
    --timeout 10m0s \
    --values values.yml
```

**Note:**

Replace `WORDPRESS_NEW_VERSION` with the new version.

## Conclusion

In this guide, we installed WordPress with an external MySQL server on a Kubernetes cluster using the command-line tool Helm. We also learned how to upgrade a WordPress release to a new chart version, and how to rollback a release if something goes wrong throughout the upgrade process.

If you want to learn more about Kubernetes and Helm, please check out the [DO Kubernetes](https://www.digitalocean.com/community/tags/kubernetes) section of our community page.
