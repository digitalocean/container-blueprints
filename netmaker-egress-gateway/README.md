# Setting up an Egress Gateway Using Netmaker

## Overview

What is an `Egress Gateway` and more important, why do you need one?

`Ingress` deals with `inbound` traffic, whereas `Egress` deals with `outbound` traffic. Going further, there are two key aspects to keep in mind:

1. Security implications.
2. Having a well defined model and set of measures for your infrastructure (either cloud based or on-premise), so that each entity from the system cannot compromise the others.

Suppose you have a private network and a bunch of machines or nodes inside the network. Do you really trust any machine in the network doing the right thing? In a sense you do, because you set up all those machines, thus knowing what applications are running on each. But even so, you may have many people working with you and accessing those machines, thus performing various operations. Of course, as a system administrator you would limit access and assign roles (RBAC), so that you have a finer control of who has access and to what resources.

What about network traffic ? In the same way, you should consider limiting or restricting both inbound and outbound traffic. Basically, nothing goes in or out without explicitly being allowed to, via explicit network policies in place. On the long term, imagine what would happen if any machine (or application running on it) is allowed to carry network traffic (in our out) without explicitly being allowed to do so. Soon, things can get out of control. By having a dedicated node (or gateway) in your network to control in or out traffic, things become much easier to manage and observe. Not only that, it also allows you to enforce more strict policies, and watch it more thoroughly by performing audits.

You already have `Firewalls` in place to allow or restrict traffic, which is an important security measure as well. `VPCs` isolate your resources (`Droplets`, `Load Balancers`, etc) between clusters in same or different regions. The `Egress` use case, is more related to how you control and route traffic between VPCs. An `Egress Gateway` is just a `NAT Gateway` in essence.

This guide is about setting up an `Egress Gateway` to control and route traffic between a `Kubernetes` cluster (e.g. `DOKS`) or a `Droplet`, from one `VPC` to another, in same or different regions. Another use case is to allow secure connections to an external service, like a managed database for example. The `Egress Gateway` is usually deployed to a dedicated machine with a `static public IP` (or `floating IP`, in case of `DigitalOcean`), and runs dedicated software. Such an example is [Netmaker](https://github.com/gravitl/netmaker), which you will discover in this tutorial.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Introducing Netmaker](#introducing-netmaker)
- [Installing the Netmaker Server](#installing-the-netmaker-server)
  - [DigitalOcean Marketplace Guide](#digitalocean-marketplace-guide)
  - [Finishing the Netmaker Server Setup](#finishing-the-netmaker-server-setup)
- [Exploring the Netmaker Server Dashboard](#exploring-the-netmaker-server-dashboard)
  - [Accessing the Netmaker Dashboard](#accessing-the-netmaker-dashboard)
  - [Exploring the Networks Section](#exploring-the-networks-section)
  - [Exploring the Access Keys Section](#exploring-the-access-keys-section)
  - [Exploring the Nodes Section](#exploring-the-nodes-section)
- [Creating an Egress Gateway for DOKS](#creating-an-egress-gateway-for-doks)
  - [Configuring Netmaker Server](#configuring-netmaker-server)
  - [Configuring DOKS](#configuring-doks)

## Prerequisites

To complete this tutorial, you will need:

1. [Doctl](https://github.com/digitalocean/doctl/releases) CLI, for `DigitalOcean` API interaction.
2. [Kubectl](https://kubernetes.io/docs/tasks/tools) CLI, for `Kubernetes` interaction.
3. Basic knowledge on how to run and operate `DOKS` clusters. You can learn more [here](https://docs.digitalocean.com/products/kubernetes).
4. Basic knowledge on how to create and manage `Droplets`. You can learn more [here](https://docs.digitalocean.com/products/droplets).
5. Basic knowledge and experience with shell commands (e.g. `Bash`).

## Introducing Netmaker

[Netmaker](https://github.com/gravitl/netmaker) is a tool for creating and managing virtual overlay networks. You can create as many overlay networks as you want, and connect different machines from different data centers transparently. At its heart Netmaker is using [WireGuard](https://www.wireguard.com) to do the magic. Being an overlay network, it doesn't affect your existing network setup, it just sits on top of it offering a lot of flexibility and possibilities.

`Netmaker` allows you to define and create `private networks`, just as `VPCs` are. It's built with `security` in mind as well. The way it works is by creating `secure tunnels` across machines, a feature offered by `WireGuard`. Netmaker follows a `client-server` model, and consists of two parts:

1. The `admin server`, called `Netmaker`.
2. `Agents` (or `clients`) deployed on each machine (or node), called `Netclients`.

The Netmaker server doesn't deal with network traffic (although it can be told to, if needed). The main role of the server is to keep configuration state, and control or manage user defined networks. Each machine participating in the network, is called a `Node`. For the most part, Netmaker serves `configuration` data to `Nodes`, telling them how they should configure themselves. The `Netclient` is the `agent` that actually does that configuration.

Traffic goes between nodes, peer to peer. On the other hand, each node can relay messages as well and improve network resiliency. Netmaker allows you to define and create `mesh networks`, which is a really powerful feature. Mesh networks add resiliency because the network can heal itself. All nodes are interconnected and contribute to traffic. If one node dies, others will take its place, thus offering transparency.

`Netmaker` also allows you to define `Egress Gateways` in a very simple manner. You just select one node from your private network and an interface for outbound traffic, and then tell Netmaker to configure it as an Egress Gateway (all the hard work is handled by Netmaker).

Being based on `WireGuard` it has `VPN` support, so you can create various configurations, like:

1. Personal (Private Browsing).
2. Remote Access.
3. Site-to-Site.
4. Mesh (virtual LAN/WAN).

`WireGuard` is `fast` and industry proven, which is another real advantage. Below picture shows the Netmaker architecture and how it manages networks:

![Netmaker Architecture](assets/images/netmaker_arch.png)

For more information and details about the inner workings and architecture, please visit the official Netmaker [design](https://netmaker.readthedocs.io/en/master/architecture.html) page related to this topic.

Next, you're going to learn how to install and configure the main `Netmaker` server, as well as `Netclients` on each node from your private network. For now Netmaker doesn't offer `High Availability` features, but it is planned in a future release.

## Installing the Netmaker Server

Netmaker server can be installed very quickly and painless via the [DigitalOcean Marketplace](https://marketplace.digitalocean.com/apps). Just choose the desired application that you want to install, and a wizard will pop-up, which will guide you through the process.

### DigitalOcean Marketplace Guide

Please follow below steps to install the Netmaker server via the DigitalOcean `Marketplace` platform:

1. First, navigate to the marketplace page, for the [Netmaker Application](https://marketplace.digitalocean.com/apps/netmaker), and click on the `Create Netmaker Droplet` blue button:

    ![Netmaker Marketplace App](assets/images/netmaker_marketplace_app.png)
2. Next, you will be redirected to the Droplet creation page. Choose a plan that suffices your needs. A basic one of `$5 per month`, should be sufficient in most of the cases:

    ![Netmaker Droplet Plan](assets/images/netmaker_droplet_plan.png)
3. Then, choose a region that's closest to you (and corresponding VPC):

    ![Netmaker Droplet Region & VPC](assets/images/netmaker_droplet_region_vpc.png)
4. Now, add your `SSH` key for authentication:

    ![Netmaker Droplet Auth](assets/images/netmaker_droplet_auth.png)
5. Finally, create the `Netmaker Droplet`. Optionally, you can change the `hostname`, and add custom `tags`. It's a good idea to have backups enabled as well:

    ![Netmaker Droplet Final Steps](assets/images/netmaker_droplet_finalize.png)

Now, please wait for the Netmaker Droplet to be created and provisioned. In the end, you should get something similar to:

![Netmaker Droplet Finished](assets/images/netmaker_droplet_status_complete.png)

Clicking the `Get Started` link should present you another window containing additional guides, as well as other interesting topics for Netmaker to study:

![Netmaker Guides and Walkthrough](assets/images/netmaker_additional_guides.png)

Next, you will be presented with the initial configuration steps for the Netmaker server and how to access the web management console.

### Finishing the Netmaker Server Setup

To use the Netmaker server, you need to finish a few more steps, by following a one-time interactive guide. The interactive guide will show up only once, after you log in for the first time into the Netmaker machine, via SSH.

First, please `list` the available `Droplets`, using `doctl` (below command will show only the `machine name`, and the corresponding `public IP address`):

```shell
doctl compute droplet list --format Name,PublicIPv4
```

The output looks similar to (please note down the `Public IPv4` address for the Netmaker server from the list):

```text
Name                                   Public IPv4
basicnp-uan1e                          167.172.62.197
basicnp-uan1g                          167.172.53.77
netmaker-ubuntu-s-1vcpu-1gb-lon1-01    209.97.179.143
```

Next, please open a terminal and SSH into the Netmaker server (please replace the `<>` placeholders accordingly):

```bash
ssh -i <YOUR_SSH_PRIVATE_KEY_FILE_NAME_HERE> root@<YOUR_NETMAKER_SERVER_PUBLIC_IP_HERE>
```

**Note:**

The private SSH key file from the above command, is the one used when installing your Netmaker server. It is not necessarily required to specify the SSH key file, if it's the same as the one from your `~/.ssh` folder.

When asked, please accept the new SSH fingerprint, and follow the on-screen instructions. Please leave the default domain name, unless you have a specific one already set up, and you want to use it here as well. Next, what's important to remember is that you don't need a default network to be created just now (answer `n` to the question) - will be touched shortly. Going further, when asked for a VPN server, answer no (`n`) again, and don't override the master key (type `n` for this question as well).

The output looks similar to:

```text
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    ______     ______     ______     __   __   __     ______   __                        
   /\  ___\   /\  == \   /\  __ \   /\ \ / /  /\ \   /\__  _\ /\ \                       
   \ \ \__ \  \ \  __<   \ \  __ \  \ \ \'/   \ \ \  \/_/\ \/ \ \ \____                  
    \ \_____\  \ \_\ \_\  \ \_\ \_\  \ \__|    \ \_\    \ \_\  \ \_____\                 
     \/_____/   \/_/ /_/   \/_/\/_/   \/_/      \/_/     \/_/   \/_____/                 
                                                                                         
 __   __     ______     ______   __    __     ______     __  __     ______     ______    
/\ "-.\ \   /\  ___\   /\__  _\ /\ "-./  \   /\  __ \   /\ \/ /    /\  ___\   /\  == \   
\ \ \-.  \  \ \  __\   \/_/\ \/ \ \ \-./\ \  \ \  __ \  \ \  _"-.  \ \  __\   \ \  __<   
 \ \_\\"\_\  \ \_____\    \ \_\  \ \_\ \ \_\  \ \_\ \_\  \ \_\ \_\  \ \_____\  \ \_\ \_\ 
  \/_/ \/_/   \/_____/     \/_/   \/_/  \/_/   \/_/\/_/   \/_/\/_/   \/_____/   \/_/ /_/ 
                                                                                                                                                                                                 
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Default Base Domain: nm.209-97-179-143.nip.io
To Override, add a Wildcard (*.netmaker.example.com) DNS record pointing to 209.97.179.143
Or, add three DNS records pointing to 209.97.179.143 for the following (Replacing 'netmaker.example.com' with the domain of your choice):
   dashboard.netmaker.example.com
         api.netmaker.example.com
        grpc.netmaker.example.com
-----------------------------------------------------
Domain (Hit 'enter' to use nm.209-97-179-143.nip.io): 
Contact Email: test@gmail.com
Configure a default network automatically (y/n)? n
Configure a VPN gateway automatically (y/n)? n
Override master key (***************) (y/n)? n
-----------------------------------------------------------------
                SETUP ARGUMENTS
-----------------------------------------------------------------
        domain: nm.209-97-179-143.nip.io
         email: test@gmail.com
    coredns ip: 209.97.179.143
     public ip: 209.97.179.143
    master key: ***************
   setup mesh?: false
    setup vpn?: false
Does everything look right (y/n)? y
```

Now, the Netmaker automation script will take care of provisioning the required server components via `docker-compose`:

```text
Beginning installation in 5 seconds...
Setting Caddyfile...
Setting docker-compose...
Starting containers...
Creating network "root_default" with the default driver
Creating volume "root_caddy_data" with default driver
Creating volume "root_caddy_conf" with default driver
Creating volume "root_sqldata" with default driver
Creating volume "root_dnsconfig" with default driver
...
Creating netmaker ... done
Creating caddy    ... done
Creating coredns     ... done
Creating netmaker-ui ... done
Netmaker setup is now complete. You are ready to begin using Netmaker.
Visit dashboard.nm.209-97-179-143.nip.io to log in
```

At the end, you will be presented with the Netmaker server dashboard link. You can also check the core components and their status, via `docker-compose`:

```shell
docker-compose ps
```

The output looks similar to (notice all components being in the `Up` state: `CoreDNS`, Netmaker `Server`, Netmaker `UI`, etc):

```text
   Name                  Command               State   Ports                                                                                 
------------------------------------------------------------------------------------------------------------
caddy         caddy run --config /etc/ca ...   Up                     
coredns       /coredns -conf /root/dnsco ...   Up      209.97.179.143:53->53/tcp, 209.97.179.143:53->53/udp                                                                                                                   
netmaker      ./netmaker                       Up      0.0.0.0:50051->50051/tcp ...                                  
netmaker-ui   /docker-entrypoint.sh            Up      0.0.0.0:8082->80/tcp,:::8082->80/tcp
```

Next, a quick walkthrough for the Netmaker administration web console is presented, to get you familiarized with the user interface, as well as some basic tasks, like: creating a private network, managing access keys and nodes inspection.

## Exploring the Netmaker Server Dashboard

In general, Netmaker is managed via a simple web interface that let's you perform administrative tasks like:

- Managing networks, Egress Gateways, Nodes, etc.
- Managing access keys for devices or nodes that need access to Netmaker resources.
- Managing external clients, like: phones, tablets or laptops accessing Netmaker resources.
- Internal DNS configuration and management.
- Users and roles for accessing the web dashboard.

### Accessing the Netmaker Dashboard

To access the Netmaker server web interface or dashboard, you can use the following URL (make sure to replace the `<>` placeholders accordingly):

```text
https://dashboard.nm.<YOUR_NETMAKER_DROPLET_DASHED_PUBLIC_IP_HERE>.nip.io
```

Notes:

- `YOUR_NETMAKER_DROPLET_DASHED_PUBLIC_IP_HERE` represents your Netmaker Droplet public IP having all dots replaced with the dash symbol: `-`. For example, if your droplet public IP is `209.97.179.143`, then the dashed version becomes: `209-97-179-143`.
- Based on the above example, the dashboard URL becomes: `https://dashboard.nm.209-97-179-143.nip.io`.
- Another way of finding the Netmaker dashboard URL is by SSH-ing as root to the Droplet, and then inspecting the `Caddyfile` from the home folder:

    ```shell
    cat Caddyfile
    ```

    The output looks similar to (notice the `# Dashboard` section):

    ```text
    {
        # LetsEncrypt account
        email test@gmail.com
    }

    # Dashboard
    https://dashboard.nm.209-97-179-143.nip.io {
        reverse_proxy http://127.0.0.1:8082
    }

    # API
    https://api.nm.209-97-179-143.nip.io {
        reverse_proxy http://127.0.0.1:8081
    }

    # gRPC
    https://grpc.nm.209-97-179-143.nip.io {
        reverse_proxy h2c://127.0.0.1:50051
    }
    ```

When you log in for the first time, a pop-up window will appear asking you to set the administrator user credentials. Please go ahead and set those now:

![Netmaker Server Create Admin](assets/images/netmaker_admin_create.png)

Then, you will be asked to log in using the credentials set previously:

![Netmaker Server Login](assets/images/netmaker_log_in.png)

After successfully logging in, you will be presented with the main dashboard interface:

![Netmaker Main Web Interface](assets/images/netmaker_main_dashboard.png)

Next, you will discover each important section from the main dashboard that are relevant for this tutorial, like:

- `Networks`: Lets you define and manage private networks.
- `Access Keys`: Lets you manage access keys for various devices or nodes accessing private resources.
- `Nodes`: Lets you inspect and manage nodes that are part of your private network.

### Exploring the Networks Section

The `Networks` feature that Netmaker provides, lets you define and manage private networks for seamlessly connecting various systems, like: Kubernetes clusters (e.g. `DOKS`), managed databases, virtual machines (e.g. Droplets) across different regions (or data centers), even across different cloud providers.

From the Netmaker main dashboard page, you can access the `Networks` section by clicking the corresponding tile, as shown below:

![Networks Tile](assets/images/netmaker_networks_tile.png)

Next, you can define a new private network by clicking the `Create Network` blue button from the right side:

![Netmaker Network Creation](assets/images/netmaker_create_network.png)

Now, give it a name and give it an address range, making sure that it **doesn't overlap with existing `CIDRs`** for other resources in your DO account (like other DOKS clusters, for example). There's an autofill feature available as well, but please bear in mind the previous note. Then, click on the `Create` button from the bottom:

![Netmaker Network Set Configuration](assets/images/netmaker_set_network_config.png)

After completing the step, the new network should be present in the listing:

![Networks Listing](assets/images/netmaker_networks_listing.png)

Going further, you can click on it and fine tune if necessary. Usually the default values are just fine, but there might be some special cases when you need to touch the defaults:

![Network Editing](assets/images/netmaker_network_edit.png)

### Exploring the Access Keys Section

The `Access Keys` feature that Netmaker provides, lets you define a set of keys which will then be used to allow access for other devices or nodes that needs to be part of your private network, and exchange data in a secure manner.

From the Netmaker main dashboard page, you can navigate to the `Access Keys` section by clicking the corresponding tile, as shown below:

![Access Keys Tile](assets/images/netmaker_access_keys_tile.png)

Next, you need to select a network to create access keys for, by expanding the drop down list:

![Access Keys Network Select](assets/images/netmaker_access_keys_select_network.png)

In the next page, make sure that your desired network is selected, then click on the `Create Access Key` blue button down below:

![Access Keys Create First Step](assets/images/netmaker_create_access_key.png)

Next, give it a proper name and number of uses, then press `Create` button:

![Access Keys Create Last Step](assets/images/netmaker_access_key_create_final.png)

Finally, you will be presented with a pop-up window giving you the access key and token for your clients (or nodes), as well as some instructions for various OS-es:

![Access Keys Instructions](assets/images/netmaker_access_keys_and_instructions.png)

The above information can be accessed anytime, by navigating to the access keys page and clicking on the corresponding key in the list.

### Exploring the Nodes Section

The `Nodes` tile that Netmaker provides, lets you inspect the nodes that are part of each private network. You can also set other node(s) features, like `Egress` or `Ingress Gateway` functionality for example.

From the Netmaker main dashboard page, you can navigate to the `Nodes` section by clicking the corresponding tile, as shown below:

![Nodes Tile](assets/images/netmaker_nodes_tile.png)

Next, you will be presented with a list of nodes, their name and corresponding network. Other details are shown, like `Egress` or `Ingress` functionality, as well as each node `IP` address, and if it's `Healthy` or not:

![Nodes Listing](assets/images/netmaker_nodes_listing.png)

Finally, if desired you can set advanced settings for each node, as shown below:

![Node Advanced Settings](assets/images/netmaker_node_advanced_settings.png)

**Important note:**

**Please bear in mind that if changing one value in the node settings, you should do this for every node that's part of the respective network. Changes do not propagate automatically to other nodes !!!**

## Creating an Egress Gateway for DOKS

Suppose that you need to use an external service like a legacy database, for example. The database is usually located in another datacenter from another provider. Then, for security reasons, you set up a firewall for the database so that no one is able to access it, only a specific IP or set of IPs.

You can egress from DOKS cluster nodes, but it's not practical because nodes are volatile, hence their IPs. It means that on the other end (meaning the database service), you need to change firewall rules again and again to allow the new IPs. This is the most frequent example where an Egress Gateway becomes useful, and where Netmaker plays an important role.

What you usually do is, have a dedicated machine (or Droplet) where Netmaker runs and has a fixed (or) static IP assigned. Then, you deploy `Netclients` to your DOKS cluster as a `DaemonSet`, so that the cluster nodes become part of your private network that you set up via Netmaker. Going, further the Netmaker server becomes the Egress Gateway, thus allowing outbound traffic to the external service (the database in this example). Finally, the external service (database) firewall is configured to allow inbound traffic from the Netmaker Egress Gateway IP.

Below is a diagram, showing the main setup for egressing DOKS cluster traffic to an external database:

![DOKS Egress Setup](assets/images/netmaker_doks_egress_example.png)

Going further, there are two steps involved:

- Configuring the `Netmaker server` to act as an `Egress Gateway`.
- Configuring `DOKS`, or installing the `Netclients` on each node of the cluster.

### Configuring Netmaker Server

In this section you will define a private network, which your DOKS cluster will be part of in the end. Then, you need to configure the Netmaker server to act as an Egress Gateway. By default, the Netmaker server itself will be part of your private network as well, thus enabling you to send outbound traffic or egress through it.

Please follow below steps to complete this section:

1. Log in to Netmaker server, as explained in the [Accessing the Netmaker Dashboard](#accessing-the-netmaker-dashboard) section of this guide.
2. Once logged in, click the `Networks` tile from the main dashboard:

    ![Access Network Section](assets/images/netmaker_networks_tile.png)
3. Then, click on the `Create Network` blue button on the right corner:

    ![Create New Network](assets/image/../images/netmaker_create_network.png)
4. Now, fill in your own network details. You may choose any IP class and range you wish as long as it doesn't overlap with the one from your DOKS cluster, or any other Droplets from your VPC (make sure to disable `UPD Hole Punching`, as it's not needed in this example). Then, click on the `Create Network` button:

    ![Set Network Configuration](assets/images/netmaker_set_network_config.png)
5. Next, navigate to the `Nodes` section by clicking on the corresponding tile from the main dashboard. You should see a single node available - the Netmaker server itself. Click on the `Egress` button to enable egress functionality for the server, as shown below:

    ![Netmaker Egress Enable](assets/images/netmaker_enable_egress.png)

6. Please paste the following entries in the `Egress Gateway Ranges` text area of the dialog box:

    ```csv
    0.0.0.0/5,8.0.0.0/7,11.0.0.0/8,12.0.0.0/6,16.0.0.0/4,32.0.0.0/3,64.0.0.0/2,128.0.0.0/3,160.0.0.0/5,168.0.0.0/6,172.0.0.0/12,172.32.0.0/11,172.64.0.0/10,172.128.0.0/9,173.0.0.0/8,174.0.0.0/7,176.0.0.0/4,192.0.0.0/9,192.128.0.0/11,192.160.0.0/13,192.169.0.0/16,192.170.0.0/15,192.172.0.0/14,192.176.0.0/12,192.192.0.0/10,193.0.0.0/8,194.0.0.0/7,196.0.0.0/6,200.0.0.0/5,208.0.0.0/4
    ```

    Then, in the interface box, type `eth0` and click on the `Create` button. Below picture shows the details:

    ![Egress Configuration Dialog](assets/images/netmaker_egress_gw_configuration_dialog.png)
7. Now, you need to create an access key. Please navigate to the menu on the left, and click the `Access Keys` button:

    ![Netmaker Access Keys Menu](assets/images/netmaker_access_key_menu.png)

8. In the next dialog, give the access key a name and a number of uses (`10` or `100` is a good start). Then, click on the `Create` button:

    ![Create Access Keys](assets/images/netmaker_access_key_create_final.png)
9. A new window window will pop-up, giving you the access keys, as well as instructions on how to install the clients on various platforms. For now, just copy the `Access Token` value (second text box), and save it for later use:

    ![Access Token Window](assets/images/netmaker_access_keys_and_instructions.png)

At this point the Netmaker server side configuration is done. Next, you need to install `Netclients` on your `DOKS` cluster. Then, each `Netclient` will connect to the main Netmaker server via the access token created earlier, and become part of the private network defined in the previous steps.

### Configuring DOKS

`Netclient` (and `WireGuard` implicitly) is deployed as a `DaemonSet`, hence it runs on every node. This way all DOKS cluster nodes can connect and be part of your private network.

**Notes:**

- Currently, `Netclient` is not available as a `userspace` application for `DOKS`, hence the `WireGuard Controller` is needed for now, until `Gravitl` finds a better solution to solve some incompatibilities related to the Debian Linux OS used for the DOKS nodes.
- The access token is just a one-time token used by `Netclient` initially. Afterwards, it creates its own password internally to authenticate with the main Netmaker server.

The next part of this section assumes that you already have a `DOKS` cluster up and running, and that `kubectl` is already configured to offer access to the cluster.

Steps to deploy `Netclient` to your `DOKS` cluster:

1. Fetch the `Netclient` template for `DOKS` from the `Gravitl` Netmaker GitHub repository:

    ```shell
    curl https://raw.githubusercontent.com/gravitl/netmaker/master/kube/netclient-template-doks.yaml > netclient-template-doks.yaml
    ```

2. Next, please open and inspect the manifest file using a text editor of your choice (preferably with `YAML` lint support). For example, you can use [VS Code](https://code.visualstudio.com/download):

    ```shell
    code netclient-template-doks.yaml
    ```

3. Search for the `TOKEN` environment variable from the manifest `spec.containers` field. Sample snippet provided below:

    ```yaml
    ...
    spec:
      hostNetwork: true
      containers:
      - name: netclient-1
        image: gravitl/netclient:0.9.2-doks
        env:
        ...
        - name: TOKEN
          value: "<token>"
    ```

4. Now, replace the `<>` placeholders from the TOKEN environment variable value with the real one saved at `Step 9.` from [Configuring Netmaker Server](#configuring-netmaker-server).
5. Save the manifest file, and run `kubectl apply` (first a dedicated `namespace` is created as well):

    ```shell
    kubectl create ns netmaker

    kubectl apply -f netclient-template-doks.yaml -n netmaker
    ```

After completing all the above steps, a new `DaemonSet` is created in your DOKS cluster running required Netclients (and WireGuard) on each node. After a few moments everything should be up and running. Please note that the Netclient containers can restart a few times until the `WireGuard Controller` is ready - this is normal.

Now, please go ahead and inspect the new Kubernetes resources created in the `netmaker` namespace, as well as their state:

```shell
kubectl get all -n netmaker
```

The output looks similar to (`netclient` and the `wireguard-controller` pods should be up and running):

```text
NAME                             READY   STATUS    RESTARTS   AGE
pod/netclient-1-6w74k            1/1     Running   0          114s
pod/netclient-1-pdm8p            1/1     Running   0          114s
pod/wireguard-controller-49mrj   1/1     Running   0          114s
pod/wireguard-controller-hr89h   1/1     Running   0          114s

NAME                                  DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
daemonset.apps/netclient-1            2         2         2       2            2           <none>          114s
daemonset.apps/wireguard-controller   2         2         2       2            2           <none>          114s
```

Next, check that `Netclient` pods run on each node from your cluster:

```shell
kubectl get pods -n netmaker -o wide
```

The output looks similar to (notice that each is running on a separate node, as seen in the `NODE` column):

```text
NAME                         READY   STATUS    RESTARTS   AGE   IP           NODE            NOMINATED NODE   READINESS GATES
netclient-1-6w74k            1/1     Running   0          26m   10.106.0.4   basicnp-uan1g   <none>           <none>
netclient-1-pdm8p            1/1     Running   0          26m   10.106.0.2   basicnp-uan1e   <none>           <none>
wireguard-controller-49mrj   1/1     Running   0          26m   10.106.0.2   basicnp-uan1e   <none>           <none>
wireguard-controller-hr89h   1/1     Running   0          26m   10.106.0.4   basicnp-uan1g   <none>           <none>
```

If the output looks similar to the one from above, you configured `Netclients` successfully. For troubleshooting possible issues, you can always inspect each pod logs, or take a look at the events to find useful information.

Finally, open the Netmaker server dashboard and navigate to the `Nodes` page. You should see your DOKS cluster nodes joined your private network, and the `Healthy` status:

![DOKS Egress Setup](assets/images/doks_egress_network.png)

Looking at the above, you can also notice that the main Netmaker server is part of your private network, and that it's acting as an Egress Gateway (denoted by the green pass mark in the egress column).

**Hint:**

It may happen for some  `Netclients` to not succeed in joining your private network. What you can do in this case is to hit the `Sync` button on the top right corner:

![Healthy](assets/images/doks_network_nodes_sync.png)

If the above still doesn't solve this issue, you can ultimately kill the respective pods. The DaemonSet will spawn fresh ones, and the join process should start again (nodes communicate with master node, meaning the Netmaker server, via GRPC calls).

Next, you will test the egress setup by deploying the `curl-test` pod in your cluster. Then, you will make a request from the `curl-test` pod to [ifconfig.me](https://ifconfig.me), to see if it's the `Egress Gateway IP` that your DOKS cluster is using to connect to the outside world.

### Testing the DOKS Egress Setup

To test your egress setup, you need to check if all the `requests` originating from your `DOKS` cluster travel via a single node - the `Egress Gateway`. The simplest way to test, is by making a `curl` request to [ifconfig.me/ip](https://ifconfig.me/ip), and see if the response contains your `Egress Gateway public IP`.

First, you need to create the `curl-test` pod in your `DOKS` cluster (the `default` namespace is used):

```shell
kubectl apply -f https://raw.githubusercontent.com/digitalocean/container-blueprints/main/netmaker-egress-gateway/assets/manifests/curl-test.yaml
```

Verify that the pod is up and running (in the `default` namespace):

```shell
kubectl get pods
```

The output looks similar to (`curl-test` pod `Status` should be `Running`):

```text
NAME       READY   STATUS    RESTARTS   AGE
curl-test   1/1     Running   0          7s
```

Then, perform a `HTTP` request to [ifconfig.me/ip](https://ifconfig.me/ip), from the `curl-test` pod:

```shell
kubectl exec -it curl-test -- curl https://ifconfig.me/ip
```

The output looks similar to:

```text
209.97.179.143
```

You can compare the above with the Netmaker Egress Gateway Droplet public IP, as shown below:

```shell
doctl compute droplet list --format Name,PublicIPv4
```

The output looks similar to (notice the `netmaker-ubuntu-s-1vcpu-1gb-lon1-01` droplet having the same public IP `209.97.179.143`):

```text
Name                                   Public IPv4
basicnp-uan1e                          167.172.62.197
basicnp-uan1g                          167.172.53.77
netmaker-ubuntu-s-1vcpu-1gb-lon1-01    209.97.179.143
```

If the results are the similar to the above, then you configured the `Egress Gateway` successfully.

## Summary

In this tutorial you learned how to use Netmaker to define and manage private networks from a central point. You also learned how to create and use an Egress Gateway for your DOKS cluster. This way, external services like databases for example, can see a single source IP in the packets coming from your DOKS cluster, thus making firewall rules management easier on the other end.

Other interesting and useful topics to read for Netmaker:

- [Multi-Cluster Networking with Kubernetes](https://itnext.io/multi-cluster-kubernetes-networking-with-netmaker-bfa4e22eb2fb).
- [Creating VPNs using Netmaker and Wireguard](https://dev.to/afeiszli/how-to-create-four-types-of-vpns-quickly-with-wireguardr-and-netmaker-1ibe).
