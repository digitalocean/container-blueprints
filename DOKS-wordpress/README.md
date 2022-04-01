## Overview

[WordPress](https://wordpress.org/about/) is an open source software designed for everyone, emphasising accessibility, performance, security, and ease of use to create a website, blog, or app. [WordPress](https://en.wikipedia.org/wiki/WordPress) is a content managment system (CMS) built on PHP and using MySQL as a data store, powering over 30% of internet sites today.

In this tutorial, you will use Helm for setting up [WordPress](https://wordpress.com/) on top of a Kubernetes cluster, in order to create a highly-available website. In addition to leveraging the intrinsic scalability and high availability aspects of Kubernetes, this setup will help keeping WordPress secure by providing simplified upgrade and rollback workflows via Helm.

You will be using an external MySQL server in order to abstract the database component, since it can be part of a separate cluster or managed service for extended availability. After completing the steps described in this tutorial, you will have a fully functional WordPress installation within a containerized cluster environment managed by Kubernetes.

## WordPress Setup Diagram

![WordPress Setup Overview](assets/images/arch_wordpress.png)

## Table of contents

- [Overview](#overview)
- [WordPress Setup Diagram](#wordpress-setup-diagram)
- [Prerequisites](#prerequisites)
- [Setting up a DigitalOcean Managed Kubernetes Cluster (DOKS)](#setting-up-a-digitalocean-managed-kubernetes-cluster-doks)
- [Configuring the WordPress MySQL DO Managed Database](#configuring-the-wordpress-mysql-do-managed-database)
- [Installing WordPress](#installing-wordpress)
  - [Deploying the Helm Chart](#deploying-the-helm-chart)
  - [Securing Traffic using Let's Encrypt Certificates](#securing-traffic-using-lets-encrypt-certificates)
    - [Installing the Nginx Ingress Controller](#installing-the-nginx-ingress-controller)
    - [Installing Cert-Manager](#installing-cert-manager)
    - [Configuring Production Ready TLS Certificates for WordPress](#configuring-production-ready-tls-certificates-for-wordpress)
  - [Enabling WordPress Monitoring Metrics](#enabling-wordpress-monitoring-metrics)
  - [Configuring WordPress Plugins](#configuring-wordpress-plugins)
  - [Upgrading WordPress](#upgrading-wordpress)
- [Conclusion](#conclusion)

## Prerequisites

To complete this tutorial, you will need:

1. [Helm](https://www.helm.sh/), for managing WordPress, Nginx Ingress Controller and Cert-Mananger releases and upgrades.
2. [Doctl](https://github.com/digitalocean/doctl/releases) CLI, for `DigitalOcean` API interaction.
3. [Kubectl](https://kubernetes.io/docs/tasks/tools) CLI, for `Kubernetes` interaction.
4. Basic knowledge on how to run and operate `DOKS` clusters. You can learn more [here](https://docs.digitalocean.com/products/kubernetes).

## Setting up a DigitalOcean Managed Kubernetes Cluster (DOKS)

Before proceeding with tutorial steps, you need a DigitalOcean Managed Kubernetes Cluster (DOKS) available and ready to use. If you already have one configured, you can skip to the next section - [Configuring the WordPress MySQL DO Managed Database](#configuring-the-wordpress-mysql-do-managed-database).

You can use below command to create a new DOKS cluster:

```console
doctl k8s cluster create <YOUR_CLUSTER_NAME> \
  --auto-upgrade=false \
  --maintenance-window "saturday=21:00" \
  --node-pool "name=basicnp;size=s-4vcpu-8gb-amd;count=3;tag=cluster2;label=type=basic;auto-scale=true;min-nodes=2;max-nodes=4" \
  --region nyc1
```

**Notes:**

- The example from this tutorial is using 3 worker nodes, 4cpu/8gb (`$48/month`) each, and the autoscaler configured between 2 and 4 nodes max. So, your cluster cost is between `$96-$192/month` with `hourly` billing. To choose a different node type, you can pick another slug from `doctl compute size list`.

- Please visit [How to Set Up a DigitalOcean Managed Kubernetes Cluster (DOKS)](https://github.com/digitalocean/Kubernetes-Starter-Kit-Developers/tree/main/01-setup-DOKS) for more details.

## Configuring the WordPress MySQL DO Managed Database

In this section, you will create a dedicated MySQL database such as [DigitalOcean’s Managed Databases](https://docs.digitalocean.com/products/databases/mysql/) for WordPress. This is necessary because your WordPress installation will live on a separate server inside the Kubernetes cluster.

**Note:**

By default, WordPress Helm chart installs MariaDB on a separate pod inside the cluster and configures it as the default database. If you don't want to use an external database, please skip to the next chapter - [Installing WordPress](#installing-wordpress).

First, create the MySQL managed database:

```console
doctl databases create wordpress-mysql --engine mysql --region nyc1 --num-nodes 2 --size db-s-2vcpu-4gb
```

**Note:**

The example from this tutorial is using one master node and one slave node, 2cpu/4gb (`$100 monthly billing`). For a list of available sizes, visit: <https://docs.digitalocean.com/reference/api/api-reference/#tag/Databases>.

The output looks similar to the following (the `STATE` column should display `online`):

``` text
ID                                      Name                    Engine    Version    Number of Nodes    Region    Status      Size
2f0d0969-a8e1-4f94-8b73-2d43c68f8e72    wordpress-mysql-test    mysql     8          1                  nyc1      online    db-s-1vcpu-1gb
```

**Note:**

- To finish setting up MySQL, the database ID is required. You can run below command, to print your MySQL database ID:

  ```console
  doctl databases list
  ```

Next, create the WordPress database user:

```console
doctl databases user create 2f0d0969-a8e1-4f94-8b73-2d43c68f8e72 wordpress_user
```

The output looks similar to the following (the password will be generated automatically):

```text
Name              Role      Password
wordpress_user    normal    *******
```

**Note:**

The new users will receive the full permissions at entire database by default, the privileges can be changed using the following instructions [How to Modify User Privileges in MySQL Databases](https://docs.digitalocean.com/products/databases/mysql/how-to/modify-user-privileges/).

Next, create the main WordPress database:

```console
doctl databases db create 2f0d0969-a8e1-4f94-8b73-2d43c68f8e72 wordpress
```

The output looks similar to the following (the password will be generated automatically):

```text
Name
wordpress
```

Finally, you need to setup the trusted sources between your MySQL database and your Kubernetes Cluster (DOKS):

 1. First extract the Kubernetes Cluster ID:

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

    - 2f0d0969-a8e1-4f94-8b73-2d43c68f8e72: represents the database id
    - c278b4a3-19f0-4de6-b1b2-6d90d94faa3b: represents the kubernetes id

**Note:**

For more details please visit [How to Secure MySQL Managed Database Clusters](https://docs.digitalocean.com/products/databases/mysql/how-to/secure/) for more details.

## Installing WordPress

### Deploying the Helm Chart

In this section, you will install WordPress in your Kubernetes cluster using the [Bitnami WordPress Helm Chartt](https://github.com/bitnami/charts/tree/master/bitnami/wordpress/).

Most important Helm chart values are:

- `externalDatabase`- configures WordPress to use an external database (such as a DO managed MySQL database).
- `mariadb.enabled` - configures WordPress to use an in-cluster database (e.g. MariaDB).

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

# Prometheus Exporter / Metrics configuration
metrics:
  enabled: false

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

Verify if WordPress is up and running:

```console
kubectl get all -n wordpress
```

The output looks similar to (all `wordpress` pods should be UP and RUNNING):

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

### Securing Traffic using Let's Encrypt Certificates

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

#### Installing Cert-Manager

First, add the `jetstack` Helm repo, and list the available charts:

```console
helm repo add jetstack https://charts.jetstack.io

helm repo update jetstack
```

Next, install Cert-Manager using Helm:

```console
helm install cert-manager jetstack/cert-manager --version 1.6.1 \
  --namespace cert-manager \
  --create-namespace
```

Finally, check if Cert-Manager installation was successful by running below command:

```console
helm ls -n cert-manager
```

The output looks similar to (`STATUS` column should print `deployed`):

```text
NAME            NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                   APP VERSION
cert-manager    cert-manager    1               2021-10-20 12:13:05.124264 +0300 EEST   deployed        cert-manager-v1.6.1     v1.6.1
```

**Notes:**

- For more details about Nginx Ingress Controller and Cert-Manager, please visit Starter Kit chapter - [How to Configure Ingress using Nginx](https://github.com/digitalocean/Kubernetes-Starter-Kit-Developers/blob/main/03-setup-ingress-controller/nginx.md).

- An alternative way to install [NGINX Ingress Controller](https://marketplace.digitalocean.com/apps/nginx-ingress-controller) and [Cert-Manager](https://marketplace.digitalocean.com/apps/cert-manager) is via the DigitalOcean 1-click apps platform.

#### Configuring Production Ready TLS Certificates for WordPress

A cluster issuer is required first, in order to obtain the final TLS certificate. Create the following YAML file, and replace using a valid email address for TLS certificate registration.

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

Now, you can access WordPress using the domain configured earlier.

### Enabling WordPress Monitoring Metrics

In this section, you will learn how to enable metrics for monitoring your WordPress instance.

First, open the `values.yml` created earlier in this tutorial, and set `metrics.enabled` field to `true`:

```yaml
# Prometheus Exporter / Metrics configuration
metrics:
  enabled: true
```

Apply changes using Helm:

```console
helm upgrade wordpress bitnami/wordpress \
    --create-namespace \
    --namespace wordpress \
    --version 13.1.4 \
    --timeout 10m0s \
    --values values.yml
```

Next, port-forward the wordpress service to inspect the available metrics:

```console
kubectl port-forward --namespace wordpress svc/wordpress-metrics 9150:9150
```

Now, open a web browser and navigate to [localhost:9150/metrics](http://127.0.0.1:9150/metrics), to see all WordPress metrics.

Finally, you need to configure Grafana and Prometheus to visualise metrics exposed by your new WordPress instance. Please visit [How to Install the Prometheus Monitoring Stack](https://github.com/digitalocean/Kubernetes-Starter-Kit-Developers/tree/main/04-setup-prometheus-stack) to learn more how to install and configure Grafana and Prometheus.

### Configuring WordPress Plugins

Plugins are the building blocks of your WordPress site. They bring in important functions to your website, whether you need to add contact forms, improve SEO, increase site speed, create an online store, or offer email opt-ins. Whatever you need your website to do can be done with a plugin.

Below you can find a list of recommended plugins:

- [Contact Form by WPForms](https://wordpress.org/plugins/wpforms-lite/): allows you to create beautiful contact forms, feedback form, subscription forms, payment forms, and other types of forms for your site.

- [MonsterInsights](https://wordpress.org/plugins/google-analytics-for-wordpress/): is the best Google Analytics plugin for WordPress. It allows you to “properly” connect your website with Google Analytics, so you can see exactly how people find and use your website.

- [All in One SEO](https://wordpress.org/plugins/all-in-one-seo-pack/): helps you get more visitors from search engines to your website. While WordPress is SEO friendly out of the box, there is so much more you can do to increase your website traffic using SEO best practices.

- [SeedProd](https://wordpress.org/plugins/coming-soon/): is the best drag and drop page builder for WordPress. It allows you to easily customize your website design and create custom page layouts without writing any code.

- [LiteSpeed Cache](https://wordpress.org/plugins/litespeed-cache/): is an all-in-one site acceleration plugin, featuring an exclusive server-level cache and a collection of optimization feature

- [UpdraftPlus](https://wordpress.org/plugins/updraftplus/): simplifies backups and restoration.  Backup your files and database backups into the cloud and restore with a single click.

Please visit <https://wordpress.org/plugins/> for more plugins

### Upgrading WordPress

Being so popular, WordPress becomes often a target for malicious exploitation, so it’s important to keep it up to date. You can upgrade WordPress via the `helm upgrade` command.

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

In this guide, you learned how to install WordPress the Kubernetes way, using Helm and an external MySQL database. You also learned how to upgrade WordPress to a new version, and how to rollback to a previous release, in case of errors.

If you want to learn more about Kubernetes and Helm, please check out the [DO Kubernetes](https://www.digitalocean.com/community/tags/kubernetes) section of our community page.
