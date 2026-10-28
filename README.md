# Migrate a Windows Server from AWS to Azure

## Watch the walkthrough

The walkthrough isn't recorded yet.

**Author:** Zeon Stewart, [LinkedIn](LINKEDIN_LINK_HERE)

## At a glance

- **What it is:** a Windows Server on Amazon Web Services (AWS) that Azure Migrate will discover, replicate, and cut over into an Azure virtual network.
- **What's automated:** Terraform declares the AWS network, the source server, the replication appliance, the Azure network, and the discovery virtual machine. The replication appliance stays out of the first apply while the Standard virtual CPU quota is below 10. The Migrate project, the appliance installer, and the cutover are still portal steps.
- **Why it's secure:** Remote Desktop is limited to the operator's current public address. Discovery uses a local Windows account over Windows Remote Management (WinRM). No AWS access key is stored for discovery.
- **Result:** the AWS source and the Azure discovery virtual machine were created, then destroyed the same night. The replication appliance wasn't created. The portal installer hasn't been run. A migration hasn't been run.

Part of [Cloud Projects](https://github.com/zsociety47/cloud-projects). Technical details are in [Technical findings](#technical-findings) at the bottom.

The design picture below is the reference. The [Architecture](#architecture) diagram is the live map. If a name disagrees, the Terraform files win.

![Design picture of the AWS source, the replication appliance, and the Azure target network](docs/architecture/architecture.png)

*Reference picture. On that picture, a solid box is built with Terraform, a dashed box is made in the portal or at cutover, and a dotted box is declared and not created yet.*

---

## Project Steps

These steps follow the files in the order each one needs the one before it. This repository has two Terraform roots, `aws/` and `azure/`. Have Terraform 1.15, the AWS command-line interface (CLI), and the Azure CLI installed. Sign in to both before the first plan.

The AWS provider sets the region to `us-east-1`. The Azure location is East US, set in `azure/variables.tf`.

Set the subscription for the terminal session without writing it into a file:

```bash
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
```

`ARM` is the prefix the Azure Resource Manager provider uses for its environment variables. Read each plan before you type `yes`.

The discovery password has no default. Put it in `aws/terraform.tfvars`. That file is gitignored.

```hcl
discovery_password = "<your-password>"
```

Use at least 12 characters, with an uppercase letter, a lowercase letter, a number, and a symbol. Leave out double quotes, dollar signs, backticks, and the username `migrateadmin`.

Check the Running On-Demand Standard virtual CPU (vCPU) quota before you create the replication appliance. In `us-east-1` the quota code is `L-1216C47A`. A new account often has an applied value of 8. The source server is a `t3.medium`, which is 2 vCPUs. The replication appliance is a `c5.2xlarge`, which is 8 vCPUs, because Azure Migrate requires 8 cores, 16 GB of memory, and a cache disk of at least 600 GB on a machine in the same virtual private cloud (VPC) as the source. Both have to be running at the same time, so the applied quota has to be at least 10. A stopped instance doesn't count, and replication needs both of them up.

Request **10**. A bigger jump is more likely to sit waiting for a person to approve it. If a higher request is already open, leave it. Don't file a second one. Other On-Demand families are often 0, so a different instance family doesn't avoid this quota. The discovery virtual machine uses 8 Azure virtual CPUs on its own, so check the Azure regional quota before adding a second appliance beside it.

```bash
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-1216C47A \
  --region us-east-1 \
  --query 'Quota.Value'
```

File the increase only when the value is below 10 and no request is already open:

```bash
aws service-quotas request-service-quota-increase \
  --service-code ec2 \
  --quota-code L-1216C47A \
  --desired-value 10 \
  --region us-east-1
```

`replication_instance_enabled` stays false until that applied value is at least 10. An apply then creates the network and the source only. Discovery uses the source and the Azure appliance. It doesn't use the replication appliance, and moving that appliance into Azure doesn't remove the requirement.

### Step 1: Keep secrets off GitHub

*Declared in `.gitignore`, before `terraform init` or `terraform apply`.*

`terraform init` downloads the providers into `.terraform/`. `terraform apply` writes `terraform.tfstate`. State holds resource identifiers and the discovery password. The state files, `*.tfvars`, and the `keys/` folder are ignored. `.terraform.lock.hcl` isn't ignored.

<!-- ![.gitignore excluding state, variable files, and keys](docs/images/step-01-gitignore.png) -->

### Step 2: Pin the AWS providers

*Declared in `aws/versions.tf` and `aws/provider.tf`. Read by `terraform init` in `aws/`.*

The Terraform block requires version 1.15.x, the AWS provider `6.69.1`, and the HTTP provider `3.6.3`. The provider block sets `us-east-1`. Credentials stay in the AWS CLI configuration, outside this repository.

```bash
cd aws
terraform init
```

The last line should be `Terraform has been successfully initialized!`

<!-- ![terraform init finished in the aws folder](docs/images/step-02-aws-init.png) -->

### Step 3: Name the AWS resources

*Declared in `aws/variables.tf`. Read by every AWS resource file.*

| Name | Value |
|---|---|
| Virtual private cloud (VPC) | `vpc-migrate-zeon`, `10.0.0.0/16` |
| Subnet | `snet-migrate-zeon`, `10.0.1.0/24`, zone `us-east-1a` |
| Internet gateway | `igw-migrate-zeon` |
| Route table | `rt-migrate-zeon` |
| Source firewall | `migrate-src-sg-zeon` |
| Replication firewall | `migrate-repl-sg-zeon` |
| Key pair | `key-migrate-zeon` |
| Source instance | `ec2-migrate-src-zeon`, computer `src-zeon`, `t3.medium`, 30 GiB |
| Replication instance | `ec2-migrate-repl-zeon`, computer `repl-zeon`, `c5.2xlarge`, 80 GiB |
| Cache disk | `vol-migrate-repl-zeon`, 620 GiB |

AWS names can't start with `sg-`, so the firewall names start with `migrate-`.

<!-- ![variables.tf with the VPC and instance names](docs/images/step-03-aws-names.png) -->

### Step 4: Build the AWS network

*Declared in `aws/vpc.tf`, `aws/internet_gateway.tf`, `aws/subnet.tf`, `aws/route_table.tf`, `aws/route_table_association.tf`, and `aws/operator_ip.tf`.*

The subnet launches public addresses. The route table sends `0.0.0.0/0` through the internet gateway. `operator_ip.tf` reads this machine's public Internet Protocol version 4 (IPv4) address from `https://api.ipify.org` at plan time and keeps it as a `/32`. The address isn't written in the file.

<!-- ![plan output listing the VPC, subnet, gateway, and route table](docs/images/step-04-aws-network.png) -->

### Step 5: Open only the ports the migration needs

*Declared in `aws/source_security_group.tf` and `aws/replication_security_group.tf`.*

A security group is stateful. The reply to an allowed inbound connection doesn't need a second rule.

On the source server:

| Port | From | Why |
|---|---|---|
| Transmission Control Protocol (TCP) 3389 | operator `/32` | Remote Desktop |
| TCP 445, 135, and 5985 | `10.0.1.0/24` | the replication appliance installs the Mobility service |
| all outbound | `0.0.0.0/0` | the server starts its own connections, including replication |

Set `discovery_winrm_cidr` in `aws/terraform.tfvars` to the public address of `pip-appl-zeon` with a `/32` prefix after that address exists. That adds TCP 5985 from the discovery appliance only. Leave the variable empty until then. The address isn't written in the repository.

On the replication appliance:

| Port | From | Why |
|---|---|---|
| TCP 3389 | operator `/32` | Remote Desktop |
| TCP 443 and 9443 | `10.0.1.0/24` | replication control and disk data from the source |
| TCP 443 outbound | `0.0.0.0/0` | Hypertext Transfer Protocol Secure (HTTPS) to Azure |
| User Datagram Protocol (UDP) 123 outbound | `0.0.0.0/0` | time sync, which registration requires |

<!-- ![source firewall rules for Remote Desktop and the Mobility ports](docs/images/step-05-aws-firewalls.png) -->

### Step 6: Create the two Windows instances

*Declared in `aws/key_pair.tf`, `aws/guest/source-setup.ps1`, `aws/guest/replication-setup.ps1`, `aws/source_instance.tf`, and `aws/replication_instance.tf`.*

The key must be an RSA private key in PEM form. Create it once, outside the repository's committed files:

```bash
mkdir -p keys
ssh-keygen -t rsa -b 2048 -m PEM -N "" -f keys/id_rsa
```

`key_pair.tf` uploads `keys/id_rsa.pub`. The private key stays in `keys/`, which is gitignored. Terraform uses it to read the built-in Administrator password. `get_password_data = true` makes apply wait until AWS has that encrypted password. Don't add an output that prints it.

Both instances use the current Windows Server 2022 English full Amazon Machine Image (AMI) owned by Amazon. Disks are unencrypted general purpose SSD (gp3) volumes, because Elastic Block Store (EBS) encryption by default was off on this account when it was checked.

The source guest script enables WinRM on TCP 5985, allows unencrypted Basic authentication, opens the Windows firewall for WinRM and for the Mobility service, sets `LocalAccountTokenFilterPolicy`, creates the local administrator `migrateadmin`, and renames the computer to `src-zeon`. The replication guest script only renames the computer to `repl-zeon`.

The cache disk is its own `aws_ebs_volume` attached at `/dev/sdf`. It's left unformatted. The portal installer uses it later. `DRInstaller.ps1` isn't in the guest script.

`replication_instance_enabled` defaults to false. Leave it false until the applied value of quota `L-1216C47A` is at least 10. Request 10 if the applied value is still 8. A plan then creates the network and `ec2-migrate-src-zeon` only. Setting the variable to true adds `ec2-migrate-repl-zeon` and the 620 GiB cache disk. Discovery doesn't need that appliance.

```bash
cd aws
terraform plan
```

Stop there while the vCPU quota is below 10. A plan of the earlier files, before the Mobility ports, reported `12 to add, 0 to change, 0 to destroy`. Plan again before any apply. The source `user_data` shows as `(sensitive value)` because it contains the discovery password.

<!-- ![plan summary of the AWS instances, still not applied](docs/images/step-06-aws-plan.png) -->

### Step 7: Pin the Azure providers

*Declared in `azure/versions.tf` and `azure/provider.tf`. Read by `terraform init` in `azure/`.*

The Terraform block requires version 1.15.x, the AzureRM provider `5.11.0`, and the HTTP provider `3.6.3`. There is no `subscription_id` line. `resource_provider_registrations = "none"`, and the file asks to register `Microsoft.Network` and `Microsoft.Compute` if they are missing. A plan can register those two.

```bash
cd azure
terraform init
```

<!-- ![terraform init finished in the azure folder](docs/images/step-07-azure-init.png) -->

### Step 8: Name the Azure resources and tag the groups

*Declared in `azure/variables.tf` and `azure/tags.tf`.*

| Name | Value |
|---|---|
| Staging resource group | `rg-migrate-src-zeon01` |
| Target resource group | `rg-migrate-tgt-zeon01` |
| Region | East US |
| Virtual network | `vnet-migrate-zeon`, `10.6.0.0/16` |
| Subnet | `snet-migrate`, `10.6.1.0/24` |
| Network Security Group (NSG) | `nsg-migrate-tgt-zeon` |
| Discovery virtual machine | `vm-appl-zeon`, computer `appl-zeon`, `Standard_D8as_v4`, portal name `migapplzeon01` |
| Discovery public address | `pip-appl-zeon`, Standard, static, in the staging group |
| Discovery network interface | `nic-appl-zeon`, on `snet-migrate` |

`10.6.0.0/16` stays clear of the AWS network `10.0.0.0/16`. The portal name is letters and numbers, 13 characters, under the 14-character limit.

Both groups get `lifetime=1d`, `owner=zeon`, `project=06-aws-to-azure-migrate-poc`, and a `created` timestamp. `created` changes on every plan, so each tagged resource ignores later changes to that one key. The nightly sweep deletes Azure groups tagged `lifetime=1d`. The AWS files don't set `lifetime`.

<!-- ![tags.tf with lifetime 1d on the Azure groups](docs/images/step-08-azure-tags.png) -->

### Step 9: Create the Azure groups and the target network

*Declared in `azure/staging_resource_group.tf`, `azure/target_resource_group.tf`, `azure/virtual_network.tf`, `azure/subnet.tf`, `azure/network_security_group.tf`, and `azure/nsg_association.tf`.*

The virtual network lives in the target group. The staging group holds the Migrate project and the discovery appliance. `discovery_virtual_machine.tf` creates `vm-appl-zeon` on `nic-appl-zeon`, so the virtual machine uses the subnet in the target group.

The NSG allows inbound TCP 3389 from the operator `/32` only. Outbound TCP 443 is one rule to the `Internet` service tag and a second rule to `AzureCloud`. Outbound TCP 5985 is allowed to `Internet`. Azure refuses both tags in a single rule. `nsg_association.tf` attaches that NSG to the subnet. `public_ip.tf` creates `pip-appl-zeon` in the staging group. That address is the outbound path. `network_interface.tf` joins it to `snet-migrate`.

The appliance administrator password has no default. Put it in `azure/terraform.tfvars`. That file is gitignored.

```hcl
discovery_admin_password = "<your-password>"
```

Use 12 to 123 characters, with an uppercase letter, a lowercase letter, a number, and a symbol. Leave out double quotes, dollar signs, backticks, and the username `migrateadmin`. The installer script is still a portal download. It isn't in the virtual machine file.

The Recovery Services vault and the cache storage account aren't in these files. The portal creates them when replication is enabled.

```bash
cd azure
terraform plan
```

<!-- ![plan summary of the two groups, the virtual network, and the NSG](docs/images/step-09-azure-plan.png) -->

### Step 10: Clean up when you're done

There's no teardown script yet. Tear both sides down the same day you apply them, as soon as the portal work is finished. The appliance is 8 vCPU with a 620 GiB cache disk, so it's not something to leave running overnight. After cutover, `terraform destroy` in `azure/` will miss the virtual machine, the vault, and the cache storage, because the portal creates those. The planned cleanup is `az group delete` on `rg-migrate-src-zeon01` and `rg-migrate-tgt-zeon01`, after the group name is typed. In `aws/`, `terraform destroy` removes the network and the instances. The nightly sweep leaves AWS virtual networks in place, and these AWS resources aren't tagged `lifetime=1d`.

<!-- ![both resource groups gone after teardown](docs/images/step-10-teardown.png) -->

---

## Automated setup

### Run this as yourself

The names in this repository are the ones I used for my own proof of concept, so don't edit the two `variables.tf` files. Make your own copies and swap my short name (`zeon`) for yours. The names follow the [naming standard](https://github.com/zsociety47/cloud-projects/blob/main/standards/NAMING-STANDARD.md): type, project or role, then your short name (`rg-migrate-src-zeon01` becomes `rg-migrate-src-ada01`). The Azure Migrate appliance name has to be unique worldwide, so `migapplzeon01` can't stay.

This repository has two Terraform roots. Copy an example in each folder.

| Open this | Do this |
|---|---|
| [`aws/terraform.tfvars.example`](aws/terraform.tfvars.example) | Copy to `aws/terraform.tfvars` (gitignored). Replace every `yourname` with your short name, including `tags.owner`. Don't reuse my key pair name, `key-migrate-zeon`. |
| [`aws/variables.tf`](aws/variables.tf) | Leave this one alone. Its defaults are the names from my own proof. |
| [`azure/terraform.tfvars.example`](azure/terraform.tfvars.example) | Copy to `azure/terraform.tfvars` (gitignored). Replace every `yourname` with your short name, including `tags.owner` and `discovery_appliance_name`. |
| [`azure/variables.tf`](azure/variables.tf) | Leave this one alone. Its defaults are the names from my own proof. |

```bash
cp aws/terraform.tfvars.example aws/terraform.tfvars
cp azure/terraform.tfvars.example azure/terraform.tfvars
```

Run the AWS root and the Azure root separately. Each one keeps its own local state file.

### Sign in

Sign in with the AWS CLI and with `az login`. The AWS provider reads the CLI credentials. The Azure provider reads the CLI login and `ARM_SUBSCRIPTION_ID`.

```bash
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
```

You should see a subscription id in the terminal and nowhere in a file.

### Create the Windows key

```bash
mkdir -p keys
ssh-keygen -t rsa -b 2048 -m PEM -N "" -f keys/id_rsa
```

The file `keys/id_rsa` begins with `-----BEGIN RSA PRIVATE KEY-----`. Leave it uncommitted.

### Set the discovery password

Create `aws/terraform.tfvars` with `discovery_password = "<your-password>"`. Confirm the file is ignored:

```bash
git check-ignore -v aws/terraform.tfvars
```

The line should name `.gitignore`.

Create `azure/terraform.tfvars` with `discovery_admin_password = "<your-password>"`. The same ignore rule covers it. This password is for `vm-appl-zeon`. It can differ from the source password.

### Initialize and plan AWS

```bash
cd aws
terraform init
terraform plan
```

`init` ends with `Terraform has been successfully initialized!`. With the default switch, `plan` lists the network and the source server, and it doesn't print the discovery password. The replication appliance and the cache disk appear after `replication_instance_enabled` is set to true.

### Initialize and plan Azure

```bash
cd azure
terraform init
terraform plan
```

`plan` lists the two groups, the virtual network, the subnet, the firewall, `pip-appl-zeon`, `nic-appl-zeon`, and `vm-appl-zeon`. It doesn't print the administrator password. It may register `Microsoft.Network` and `Microsoft.Compute`. East US has 10 total regional virtual CPUs, and this virtual machine uses 8 of them.

### Apply

Don't apply yet. An AWS apply with the default switch creates the network and the source, which fits the quota of 8. It doesn't create the replication appliance. Azure apply creates the discovery virtual machine, which bills by the hour. Those groups are tagged `lifetime=1d`, so the nightly sweep can delete them.

### Verify the AWS side

```bash
./scripts/verify-aws.sh
```

The script reads the live virtual private cloud, the source server, and the source firewall. It prints a pass or fail line for each check and doesn't print public addresses. The replication appliance is allowed to be off. A running appliance passes only when it is `c5.2xlarge` with a 620 GiB cache disk. The checks in [Success criteria](#success-criteria) still cover discovery, replication, and cutover, which this script doesn't.

### Teardown

No teardown script exists. See [Step 10](#step-10-clean-up-when-youre-done).

---

## Architecture

![Design picture of the AWS source, the replication appliance, and the Azure target network](docs/architecture/architecture.png)

*Reference picture. On that picture, a solid box is built with Terraform, a dashed box is made in the portal or at cutover, and a dotted box is declared and not created yet.*

```mermaid
flowchart LR
    operator["Your Mac<br/>Terraform and Remote Desktop"]

    subgraph awsnet["AWS · us-east-1 · vpc-migrate-zeon"]
        source["ec2-migrate-src-zeon<br/>source server"]
        repl["ec2-migrate-repl-zeon<br/>declared, switched off"]
    end

    subgraph azure["Azure · East US"]
        subgraph staging["rg-migrate-src-zeon01 · lifetime=1d"]
            discovery["vm-appl-zeon<br/>discovery appliance"]
            cache["Cache and vault<br/>made by the portal"]
            migrate["Azure Migrate project<br/>portal"]
        end
        subgraph tgt["rg-migrate-tgt-zeon01 · lifetime=1d"]
            vnet["vnet-migrate-zeon<br/>10.6.0.0/16"]
            nsg["Firewall (NSG)<br/>Remote Desktop from your IP only"]
            landed["Migrated Windows VM<br/>cutover, not in Terraform"]
        end
    end

    operator -- "Terraform apply" --> source
    operator -- "Terraform apply" --> vnet
    discovery -- "WinRM TCP 5985" --> source
    discovery -- "inventory" --> migrate
    source -. "TCP 443 and 9443" .-> repl
    repl -. "HTTPS 443" .-> cache
    cache --> migrate
    nsg -- "attached to the subnet" --> vnet
    migrate -. "cutover" .-> landed

    classDef azure fill:#0078d4,stroke:#005a9e,color:#fff
    classDef external fill:#6e7681,stroke:#484f58,color:#fff

    class discovery,cache,migrate,vnet,nsg,landed azure
    class operator,source,repl,awsnet external
```

*Live map. A solid arrow is in the files today. A dashed arrow is portal or cutover, or it waits on the replication appliance. Gray is AWS. Blue is Azure.*

### How to read this diagram

- The operator reaches Windows machines only on TCP 3389, and only from the address collected at plan time.
- The source and the appliance share `10.0.1.0/24`. The appliance, when it exists, installs the Mobility service on the source over TCP 445, 135, and 5985.
- `vm-appl-zeon` was created in the staging group, on `snet-migrate`, and destroyed the same night. The next apply brings it back. The source firewall allows TCP 5985 from that appliance's address once `discovery_winrm_cidr` is set. The installer is a portal step.
- The replication appliance is declared and switched off until the virtual CPU quota reaches 10.
- The migrated server, the vault, and the cache storage account are created by Azure Migrate. Terraform doesn't declare them.

---

## Variant B: appliance in Azure

Variant A keeps the replication appliance on AWS, in the same virtual private cloud as the source. Variant B is a separate Terraform folder, `variant-b-appliance-in-azure`, with its own state. The AWS source stays in `aws/`. Only the replication appliance moves. It is a `Standard_D8as_v4` (8 virtual central processing units, 32 GB) in `rg-migrate-repl-zeon01`, on `10.7.0.0/16`.

Do not run it beside `vm-appl-zeon`. Each machine is 8 virtual central processing units, and East US allows 10. Deallocate one before you start the other. The password is `TF_VAR_replication_admin_password` in the environment. It is not stored in a tfvars file.

| | Variant A | Variant B |
|---|---|---|
| AWS capacity needed | 10 virtual central processing units: source 2 plus appliance 8. Quota `L-1216C47A` is 8 until the open request for 16 is approved. | 2 virtual central processing units: the source only. |
| Internet exposure | Replication ports stay inside `10.0.1.0/24`. Remote Desktop is the operator address only. | Remote Desktop is the operator address only. TCP 443 and 9443 are allowed in, and TCP 5985, 445, and 135 out, only after the source address is set as a `/32`. Azure's default outbound allow remains, as it does on the discovery firewall. |
| Ports | Source: 3389 from the operator; 445, 135, and 5985 from the subnet. Appliance: 3389 from the operator; 443 and 9443 from the subnet. | Appliance: 3389 from the operator. The source-address rules above are off until `source_replication_cidr` is set. The AWS source firewall is not changed. |
| Cost per hour | About $0.84 on AWS while copying: source $0.06, `c5.2xlarge` $0.708, and 620 GiB gp3 at $0.08 per GB-month (about $0.07). Add $0.752 if the discovery machine stays on. Prices checked 2026-10-27. | About $0.92: source $0.06, the Azure virtual machine $0.752, and the cache disk at the 1024 GB Standard SSD tier ($76.80 per month, about $0.11). Discovery stays off. |
| Closeness to Microsoft's AWS guidance | Matches it. The appliance sits in the source virtual private cloud, with a cache disk of at least 600 GB. | The comparison path. Whether replication works from Azure, and which way the agent push goes, are unverified. See `variant-b-appliance-in-azure/FINDINGS.md`. |

---

## Hypothesis

A Windows server on AWS can be moved into Azure as a physical server: Azure discovers it over WinRM, an appliance in the same VPC replicates the disks, and cutover lands the server in a network Terraform already prepared.

## Success criteria

| # | Criterion | How it is checked | Result |
|---|-----------|-------------------|--------|
| 1 | The AWS plan lists the network and the source while the appliance switch is off, and lists the appliance and the 620 GiB cache disk when the switch is on | `terraform plan` in `aws/` | Not checked |
| 2 | Remote Desktop on both clouds accepts only the operator `/32` | security group and NSG rules, then a connection from that address | Not checked |
| 3 | Discovery finds `src-zeon` over WinRM with `migrateadmin` | Azure Migrate inventory, with no AWS access key in the repo | Not checked |
| 4 | Replication copies disk changes through `ec2-migrate-repl-zeon` | Azure Migrate replication health | Not checked |
| 5 | A test migration boots in `vnet-migrate-zeon` | the test virtual machine on `snet-migrate` | Not checked |
| 6 | Cutover leaves the server in `rg-migrate-tgt-zeon01` | the resource group after cutover | Not checked |
| 7 | Teardown removes the AWS instances and both Azure groups | `terraform destroy` in `aws/`, then `az group delete` on both groups | Not checked |

## What's in this repository

```text
aws/
  versions.tf                     pins Terraform 1.15, AWS provider 6.69.1, HTTP provider 3.6.3
  provider.tf                     signs in with the AWS CLI and sets us-east-1
  variables.tf                    names, sizes, and tags for the AWS side
  vpc.tf                          VPC vpc-migrate-zeon
  internet_gateway.tf             internet gateway
  subnet.tf                       public subnet in us-east-1a
  route_table.tf                  default route through the gateway
  route_table_association.tf      attaches the route table to the subnet
  operator_ip.tf                  reads the operator public address at plan time
  source_security_group.tf        Remote Desktop and Mobility ports on the source
  replication_security_group.tf   Remote Desktop, 443, and 9443 on the appliance
  key_pair.tf                     uploads the public half of the RSA key
  guest/source-setup.ps1          WinRM, Mobility firewall, migrateadmin, rename
  guest/replication-setup.ps1     renames the appliance
  source_instance.tf              Windows source server
  replication_instance.tf         appliance and the separate 620 GiB cache disk
scripts/
  verify-aws.sh                   live AWS checks; does not apply or print addresses
azure/
  versions.tf                     pins Terraform 1.15, AzureRM 5.11.0, HTTP provider 3.6.3
  provider.tf                     signs in with the Azure CLI
  variables.tf                    names and the base tags
  tags.tf                         adds lifetime=1d and created
  staging_resource_group.tf       group for the Migrate project
  target_resource_group.tf        group the server lands in
  virtual_network.tf              vnet-migrate-zeon in the target group
  subnet.tf                       snet-migrate
  network_security_group.tf       Remote Desktop from the operator
  nsg_association.tf              attaches the NSG to the subnet
  public_ip.tf                    Standard static address pip-appl-zeon
  network_interface.tf            joins pip-appl-zeon to snet-migrate
  discovery_virtual_machine.tf    Windows Server 2022 appliance, Standard_D8as_v4
variant-b-appliance-in-azure/
  FINDINGS.md                     quota block, and the two unverified replication questions
  versions.tf                     same Azure pins as azure/, separate state
  replication_virtual_machine.tf  Windows Server 2022, Standard_D8as_v4
  cache_disk.tf                   620 GB cache disk
  network_security_group.tf       Remote Desktop from the operator
docs/architecture/
  architecture.png                reference picture
  architecture.pdf                same picture, for print
```

`aws/terraform.tfvars` and `keys/` exist only on the machine that applies. They are gitignored.

## Security choices

- **Remote Desktop is a /32.** The address is looked up at plan time. It's stored in state and isn't written in the repository.
- **Discovery uses a local account.** `migrateadmin` is created on first boot. The password lives in `aws/terraform.tfvars`. The built-in Administrator password is decrypted with the RSA key and isn't given an output.
- **No second AWS user.** The discovery appliance doesn't get an Identity and Access Management (IAM) access key. It reaches the source over WinRM.
- **Replication ports stay inside the subnet.** TCP 443 and 9443 on the appliance, and TCP 445, 135, and 5985 on the source, allow `10.0.1.0/24` only.
- **Disks are unencrypted on purpose.** EBS encryption by default was off. Turning it on would change the volume AWS presents to Azure Migrate, so both the source disk and the cache disk set `encrypted = false`.
- **Outbound is two ports, on one address.** The subnet firewall allows TCP 443 to Azure and the public internet, and TCP 5985 to the public internet. `pip-appl-zeon` is the Standard static address that carries it. `nic-appl-zeon` joins that address to `snet-migrate`, and `vm-appl-zeon` attaches that interface.
- **Azure groups are short-lived.** `lifetime=1d` lets the nightly sweep delete them. The state file stays local.

## Cost

Plan on about 10 to 15 US dollars if both clouds are destroyed the same day. The costly pieces are the `c5.2xlarge` appliance, its 620 GiB cache disk, and the Windows licenses on the two AWS instances. The discovery appliance adds `Standard_D8as_v4`, an 8-virtual-CPU, 32 GiB Azure virtual machine. Leave none of those running overnight. The Azure groups are tagged for the nightly sweep. The AWS network still needs `terraform destroy`.

## Going further

- The appliance's Login button signs you in with a device code, which is a code you paste into a browser. Security defaults block that sign-in and the page shows error 530035. A directory without a paid Microsoft Entra ID license can't make an exception for just that one sign-in, so turn security defaults off before you click Login: Microsoft Entra ID, Properties, Security defaults, Disabled, then Save. Leave them off until the replication appliance signs in the same way. Stick with the Login button. A separate app and certificate would skip those screens, but it can't register the replication appliance.
- Run `AzureMigrateInstaller.ps1` from the portal on `vm-appl-zeon`. The discovery address is already in `discovery_winrm_cidr`.
- Request quota `L-1216C47A` at 10 if it is still 8, then set `replication_instance_enabled` to true, install `DRInstaller.ps1` from the portal onto `ec2-migrate-repl-zeon`, and enable replication. Leave a higher request alone if one is already open.
- Confirm on the first replication whether TCP 443 and 9443 need to be allowed in both directions inside the subnet.
- Add `lifetime`, `owner`, `project`, and `created` to the AWS resources so the sweep can see the instances.
- Write the teardown script that deletes both Azure groups after the portal has created the vault and the migrated server.
- Redraw the design picture once those pieces exist, so the dotted boxes are gone before any video.

---

## Technical findings

*For engineers: what actually happened while building this, including the errors.*

- **The Windows password needs an RSA key.** An ED25519 key can't decrypt the Administrator password AWS returns. `ssh-keygen -t rsa -b 2048 -m PEM` writes the PEM header `-----BEGIN RSA PRIVATE KEY-----`, which `aws_instance` can use. `get_password_data = true` waits during apply until that password exists.
- **A security group name can't start with `sg-`.** AWS rejected that prefix. The firewalls are `migrate-src-sg-zeon` and `migrate-repl-sg-zeon`.
- **EBS encryption by default was false.** The source disk and the cache disk set `encrypted = false` so the volume matches the account default that was checked.
- **The Standard vCPU quota blocks the replication appliance.** Quota `L-1216C47A`, Running On-Demand Standard (A, C, D, H, I, M, R, T, Z), had an applied value of 8 in `us-east-1`. The source is 2 vCPUs and the appliance is 8, and replication needs both running, so the applied value has to be at least 10. Request 10. A larger number is more likely to be reviewed by a person. This account already had a higher request open, and that request was left as filed. The source was applied with `replication_instance_enabled` false and later destroyed. The replication instance wasn't created.
- **The replication appliance stays in the source VPC.** Azure Migrate runs a configuration server and a process server on that machine. The process server receives disk blocks from the Mobility service on the source over TCP 9443, compresses and encrypts them, holds them on the cache disk, and uploads them to Azure over HTTPS 443. Microsoft requires 8 cores, 16 GB of memory, a separate cache disk of at least 600 GB, and a machine in the same VPC as the source. A smaller size fails that check. Putting the appliance in Azure leaves it on the wrong side of the copy, and this proof doesn't do that.
- **The earlier plan is stale.** That plan reported `12 to add, 0 to change, 0 to destroy` before the Mobility ingress rules. Plan again before apply. The plan file was deleted because it contained the operator public address.
- **PowerShell dollars in `templatefile`.** Terraform interpolates `${name}`. A PowerShell `$` in the guest script has to be written `$$`, or avoided. The scripts pass the computer name, the username, and the password in as Terraform variables.
- **The cache disk is a separate resource.** Putting it in `ebs_block_device` would replace the instance when the disk changes. `aws_ebs_volume` plus `aws_volume_attachment` keeps the instance stable.
- **The NSG attaches in its own file.** This provider has no `network_security_group_id` argument on the subnet. `azurerm_subnet_network_security_group_association` is the attachment.
- **`created` would change every plan.** `timestamp()` is a new value each run. `lifecycle { ignore_changes = [tags["created"]] }` keeps the first value.
- **The configuration server is retired.** Microsoft retired the classic configuration server on 2026-09-30. This build uses the simplified replication appliance, still installed later with `DRInstaller.ps1`.
- **Security defaults block the appliance Login.** Error 530035 means the sign-in was blocked by security defaults. The Login button uses a device code against Microsoft Azure PowerShell. This directory has no premium license, so conditional access can't allow that one flow. A preconfigured application and certificate would also skip Login. That path isn't used here. Anyone following along wouldn't see the same screens, and Microsoft doesn't support it for the replication appliance.
