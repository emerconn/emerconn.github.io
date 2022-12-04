---
layout: single
classes: wide
toc: true
title:  "Create & manage RouterOS network infrastructure using IaaS with Terraform"
date:   2022-11-27 00:00:00 -0600
categories: mikrotik routeros terraform
---

This post covers how to create & manage networking infrastructure in RouterOS using IaaS with Terraform.

P.S. Welcome to my first blog post -- feedback is appreciated!

## Prerequisites

### Enable RouterOS' REST API

Before Terraform can access RouterOS, we need to open up its REST API.
This involves a couple steps -- creating two self-signed certificates & enabling the `www-ssl` service.
If necessary, refer to [RouterOS' REST API docs](https://help.mikrotik.com/docs/display/ROS/REST+API).

[Here's](https://www.medo64.com/2016/11/enabling-https-on-mikrotik/) another good write-up on this process.

**Note:** the REST API requires RouterOS v7.1beta4 or newer.
{: .notice--warning}

#### Certificates

Two certificates are required to enable the `www-ssl` service -- root & HTTPS.
If necessary, refer to [RouterOS' certificate docs](https://help.mikrotik.com/docs/display/ROS/Certificates).

SSH into your router. Open the certificates menu with `/certificate`.

```bash
> /certificate
/certificate> 
```

Now let's create the certificate templates.

```bash
/certificate> add name=root-cert common-name=root-cert key-usage=key-cert-sign,crl-sign
/certificate> add name=https-cert common-name=https-cert
```

Before signing, let's check our work with `print detail`.

```bash
/certificate> print detail
Flags: K - private-key, L - crl, C - smart-card-key, A - authority, I - issued, R - revoked, E - expired, T - trusted
 0         name="root-cert" key-type=rsa common-name="root-cert" key-size=2048 subject-alt-name="" days-valid=365
           key-usage=key-cert-sign,crl-sign
           fingerprint="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" akid="" skid=""

 1         name="https-cert" key-type=rsa common-name="https-cert" key-size=2048 subject-alt-name="" days-valid=365
           key-usage=digital-signature,key-encipherment,data-encipherment,key-cert-sign,crl-sign,tls-server,tls-client
           akid="" skid=""
```

Notice the default `days-valid` is 365.
If you want a longer or shorter expiration date, this number can be modified.

```bash
/certificate> remove root-cert
/certificate> remove https-cert
/certificate> add name=root-cert common-name=root-cert key-usage=key-cert-sign,crl-sign days-valid=420
/certificate> add name=https-cert common-name=https-cert days-valid=420
```

Next step is signing our new certificates. Each signing will take a few seconds.

```bash
/certificate> sign root-cert
  progress: done

/certificate> sign https-cert
  progress: done

/certificate>
```

[RouterOS documentation](https://help.mikrotik.com/docs/display/ROS/Certificates)

#### `www-ssl`

Now we can enable the `www-ssl` service and configure it with a cert.

Open the `/ip service` menu and configure away.

```bash
certificate> /ip service
/ip service> set www-ssl certificate=https-cert disabled=no
```

Optionally (but recommended), disable `www`, which is the HTTP service.

```bash
/ip service> set www disabled=yes
```

## Terraform Setup

If you haven't already installed Terraform, follow [these steps](https://developer.hashicorp.com/terraform/downloads).

### Provider documentation

The provider documentation can be found here [here](https://registry.terraform.io/providers/GNewbury1/routeros/latest/docs).

### Environment setup

Create a directory to host your Terraform environment.
All related Terraform files will be created and saved here.

Create a new empty file called `main.tf`.
This will be our primary Terraform template.

#### Using the Provider

To use the RouterOS provider and configure access to your router, add the following to `main.tf`

```terraform
terraform {
  required_providers {
    routeros = {
      source = "GNewbury1/routeros"
    }
  }
}

provider "routeros" {
  hosturl  = "https://127.0.0.1"
  username = "admin"
  password = "password"
  insecure = true
}
```

Replace `hosturl` with your router's IP address, and `username` & `password` with your credentials.
Configuring `insecure = true` is required because our RouterOS certificate is self-signed.

**WARNING:** Saving credentials in plaintext is insecure and dangerous.
This example is simplified as managing Terraform secrets is out of the scope of this post.
Further reading can be found [here](https://blog.gruntwork.io/a-comprehensive-guide-to-managing-secrets-in-your-terraform-code-1d586955ace1).
{: .notice--danger}

#### Initialization

Now we are ready to initialize, which creates all the necessary Terraform configuration files inside of our working directory, by using `terraform init`.

```
$ terraform init

Initializing the backend...

Initializing provider plugins...
- Finding latest version of gnewbury1/routeros...
- Installing gnewbury1/routeros v0.4.0...
- Installed gnewbury1/routeros v0.4.0 (self-signed, key ID D0765F6A8904899E)

(...)

Terraform has been successfully initialized!

(...)
```

Notice the newly create directory and files.
These are automatically created upon initialization.

##### Explore `.terraform.lock.hcl`

Terraform uses the lock file to know which provider versions to use.
Instead of automatically using the newest version, Terraform will use what is specified in the lock file.
This ensures everyone using your Terraform configuration is using the same provider versions.

```terraform
# This file is maintained automatically by "terraform init".
# Manual edits may be lost in future updates.

provider "registry.terraform.io/gnewbury1/routeros" {
  version = "0.4.0"
  hashes = [
    "h1:84cTGw2TIyU1Fk7kaaBUSdYWZxHOKA1tZU1AvstU5ag=",
    (...)
    "zh:f476496991d3729c2a1ca01e803fb9080a606e9a737e6f098e66356995b07675",
  ]
}
```

More reading can be found [here](https://developer.hashicorp.com/terraform/tutorials/cli/init#explore-lock-file).

##### Explore the `.terraform` directory

Terraform uses the `.terraform` directory to store teh project's providers & modules.

More reading can be found [here](https://developer.hashicorp.com/terraform/tutorials/cli/init#explore-the-terraform-directory)

## Creating A New Network

With our working environment and provider ready to go, we can begin creating our new network.

**Note:** The full `main.tf` example file is found [here](https://raw.githubusercontent.com/emerconghaile/emerconghaile.github.io/main/assets/code-examples/2022-12-4-terraform-create-manage-routeros-network-infrastructure/main.tf).
{: .notice--info}

### Required resources

For this example, my subnet will be utilized by a VLAN interface.

We can optionally add a DHCP server to our subnet.

Finally, we need to configure a route so that our new traffic knows where to go.

#### VLAN interface

The first required resource is our VLAN interface.
An interface is used to signify where our traffic should be routed.

VLAN interfaces are special because they allow us to segment our traffic on switch ports (granted that your networking hardware supports Layer 3).
Restricting a switch port to only transport specific VLAN traffic provides an extra layer of security & management.

In this example I create a VLAN with an ID of 71, which I have designated for smart devices.
This VLAN will ride on top of a bridge interface, `bridge-lan`.

Append the following to `main.tf`.

```terraform
# VLAN interface
resource "routeros_interface_vlan" "vlan-vlan71-smartDevices" {
  interface = "bridge-lan"
  name      = "vlan71-smartDevices"
  vlan_id   = 71
}
```

#### Address / Subnet

Next we need to create the address resource.
This contains the subnet in CIDR notation, along with the gateway IP.
My example will use `10.0.71.0/24`.

We can reuse the interface name from above by calling `routeros_interface_vlan.vlan71-smartDevices.name`.
This allows our infrastructure to be dynamic, which is one of the amazing benefits to Terraform.

Append the following to `main.tf`.

```terraform
# Address / Subnet
resource "routeros_ip_address" "address-vlan71-smartDevices" {
  address   = "10.0.71.1/24"
  interface = routersos_interface_vlan.vlan-vlan71-smartDevices.name
  network   = "10.0.71.0"
}
```

#### Pool (optional)

The next three resources are for a DHCP scope.

Our first DHCP scope resource is the pool.
This tells our router what range of IP address it may allocate to our DHCP scope.

**Note:** This option is only necessary if you require a DHCP scope in this subnet.
{: .notice--info}

Append the following to `main.tf`.

```terraform
# Pool (optional)
resource "routeros_ip_pool" "pool-vlan71-smartDevices" {
  name   = routersos_interface_vlan.vlan-vlan71-smartDevices.name
  ranges = "10.0.71.100-10.0.71.200"
}
```

#### DHCP network (optional)

The second resource for the DHCP scope is the DHCP network.
When the router hands out DHCP records to a device, it will tell the device what to use for the gateway, subnet mask, dns server, and domain (which is optional).

**Note:** This option is only necessary if you require a DHCP scope in this subnet.
{: .notice--info}

Append the following to `main.tf`.

```terraform
# DHCP network (optional)
resource "routeros_ip_dhcp_server_network" "dhcpNetwork-vlan71-smartDevices" {
  address    = "10.71.0.0/24"
  gateway    = "10.71.0.1"
  dns_server = "10.71.0.1"
  domain     = "yoshi.lan"
}
```

#### DHCP server (optional)

The final resource for the DHCP scope is the DHCP server. This resource calls two resources we created earlier (interface & pool) to then combine and create the actual DHCP server that hands out DHCP records.

**Note:** This option is only necessary if you require a DHCP scope in this subnet.
{: .notice--info}

Append the following to `main.tf`.

```terraform
# DHCP server (optional)
resource "routeros_ip_dhcp_server" "dhcpServer-vlan71-smartDevices" {
  address_pool = routersos_interface_vlan.vlan-vlan71-smartDevices.name
  interface    = routersos_interface_vlan.vlan-vlan71-smartDevices.name
  name         = routersos_interface_vlan.vlan-vlan71-smartDevices.name
}
```

#### Route

Lastly, but definitely not least, the route resource.
When traffic addressed for our new subnet hits the router, the route tells the router where this traffic should end up.

Append the following to `main.tf`.

Notice we use a new Terraform function, called `format`.
This function can concatenate strings, among other things.

```terraform
# Route
resource "routeros_ip_route" "route-vlan71-smartDevices" {
  dst_address = "10.71.0.0/24"
  gateway     = format("%%%s", routersos_interface_vlan.vlan-vlan71-smartDevices.name)
}
```

In our example, `%s` is used as a variable placeholder that represents a string.
Don't let the two additional `%%` confuse you.
The first is an escape character, which means the second will be interpreted as a literal character.

The `format` function will process our final output as `%vlan71-smartDevices`.
This a special variable in RouterOS that will dynamically fetch our gateway IP.

More reading on Terraform's `format` function can be found [here](https://developer.hashicorp.com/terraform/language/functions/format).

### Creation

With our `main.tf` file crafted, we can now move on to creating our infrastructure.

The next step, as a best practice, is to to run `terraform plan`.
This command will show us what actions Terraform plans to take.
It's best to review these steps and double-check our configuration is correct.

```bash
$ terraform plan
```

The next command is the one that actually creates our new infrastructure.
We can append the flag `-auto-approve` to skip that the interactive prompts manual approval.

```bash
$ terraform apply -auto-approve
```

### Modifications

With our new infrastructure created, Terraform can recognize any changes made to existing infrastructure (given the infrastructure is part of our code).

Once modifications are made, the same commands above can be ran.
Terraform's output will tell you if there's any new resources, modified resources, or deleted resources.

### Destruction

If desired, we can delete all of our infrastructure in one fell swoop. This is done using the command `terraform destroy`.

```bash
$ terraform destroy
```

I wouldn't recommend adding the `-auto-approve` flag in here as this command can be dangerous, so a two-step process here is a good thing.