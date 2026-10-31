# Migrate a Windows Server from AWS to Azure

## Watch the walkthrough

The walkthrough isn't recorded yet.

**Author:** Zeon Stewart, [LinkedIn](LINKEDIN_LINK_HERE)

## At a glance

- **What it is:** a Windows Server on Amazon Web Services (AWS) that Azure Migrate will discover, replicate, and cut over into an Azure virtual network.
- **What's automated:** Terraform declares the AWS network, the source server, the replication appliance, the Azure network, and the discovery virtual machine. The replication appliance stays out of the first apply while the Standard virtual CPU quota is below 10. The Migrate project, the appliance installer, and the cutover are still portal steps.
- **Why it's secure:** Remote Desktop is limited to the operator's current public address. Discovery uses a local Windows account over Windows Remote Management (WinRM). No AWS access key is stored for discovery.
- **Result so far:** discovery completed again (WinRM validate, inventory shows `src-zeon`). Replication and cutover are not run yet. The AWS On-Demand Standard vCPU quota is still 8 (request for 16 open), so [Variant A](#variant-a-appliance-on-aws) stays blocked. This proof continues on [Variant B](#variant-b-appliance-in-azure) when you choose to replicate.

Part of [Cloud Projects](https://github.com/zsociety47/cloud-projects). Technical details are in [Technical findings](#technical-findings) at the bottom.

The design picture below is the reference. The [Architecture](#architecture) diagram is the live map. If a name disagrees, the Terraform files win.

![Design picture of the AWS source, the replication appliance, and the Azure target network](docs/architecture/architecture.png)

*Reference picture. On that picture, a solid box is built with Terraform, a dashed box is made in the portal or at cutover, and a dotted box is declared and not created yet.*

---

## Project Steps

These steps follow the files in the order each one needs the one before it, then the portal work Terraform cannot do. Steps 1 through 12 are local Terraform and a small tfvars edit. Steps 13 through 16 discover the AWS source (portal plus Remote Desktop on the discovery virtual machine). Step 17 checks the AWS virtual CPU quota and chooses Variant A or Variant B. Steps 18 through 22 stand up the replication appliance, open the copy path, enable replication, run a test migration, and cut over into the target network. Step 23 tears everything down the same day. Do not skip from discovery straight to teardown: discovery only finds the server; replication and cutover are what land a Windows virtual machine in Azure. This repository has three Terraform roots when you use Variant B: `aws/`, `azure/`, and `variant-b-appliance-in-azure/`. Have Terraform 1.15, the AWS command-line interface (CLI), and the Azure CLI installed. Sign in to both before the first plan.

The AWS provider sets the region to `us-east-1`. The Azure location is East US, set in `azure/variables.tf`.

Set the subscription for the terminal session without writing it into a file:

```bash
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
```

`ARM` is the prefix the Azure Resource Manager provider uses for its environment variables. Read each plan before you type `yes`.

The discovery password has no default. It lives in `aws/terraform.tfvars`, which is gitignored and does not exist until you copy the example (see **Run this as yourself** below). Replace `REPLACE_ME` with your password. Use at least 12 characters, with an uppercase letter, a lowercase letter, a number, and a symbol. Leave out double quotes, dollar signs, backticks, and the username `migrateadmin`.

Check the Running On-Demand Standard virtual CPU (vCPU) quota before you create the replication appliance. In `us-east-1` the quota code is `L-1216C47A`. A new account often has an applied value of 8. The source server is a `t3.medium`, which is 2 vCPUs. The replication appliance is a `c5.2xlarge`, which is 8 vCPUs, because Azure Migrate requires 8 cores, 16 GB of memory, and a cache disk of at least 600 GB on a machine in the same virtual private cloud (VPC) as the source. Both have to be running at the same time, so the applied quota has to be at least 10. A stopped instance doesn't count, and replication needs both of them up.

Request **10**. A bigger jump is more likely to sit waiting for a person to approve it. If a higher request is already open, leave it. Don't file a second one. Other On-Demand families are often 0, so a different instance family doesn't avoid this quota. The discovery virtual machine uses 8 Azure virtual CPUs on its own, so check both the Azure regional quota and the Standard DASv4 family quota (still 10) before adding a second appliance beside it.

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

![.gitignore excluding state, variable files, and keys](docs/images/step-01-gitignore.png)

### Step 2: Pin the AWS providers

*Declared in `aws/versions.tf` and `aws/provider.tf`. Read by `terraform init` in `aws/`.*

The Terraform block requires version 1.15.x, the AWS provider `6.69.1`, and the HTTP provider `3.6.3`. The provider block sets `us-east-1`. Credentials stay in the AWS CLI configuration, outside this repository.

```bash
cd aws
terraform init
```

The last line should be `Terraform has been successfully initialized!`

![terraform init finished in the aws folder](docs/images/step-02-aws-init.png)

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

![variables.tf with the VPC and instance names](docs/images/step-03-aws-names.png)

### Step 4: Build the AWS network

*Declared in `aws/vpc.tf`, `aws/internet_gateway.tf`, `aws/subnet.tf`, `aws/route_table.tf`, `aws/route_table_association.tf`, and `aws/operator_ip.tf`.*

The subnet launches public addresses. The route table sends `0.0.0.0/0` through the internet gateway. `operator_ip.tf` reads this machine's public Internet Protocol version 4 (IPv4) address from `https://api.ipify.org` at plan time and keeps it as a `/32`. The address isn't written in the file.

![plan output listing the VPC, subnet, gateway, and route table](docs/images/step-04-aws-network.png)

### Step 5: Open only the ports the migration needs

*Declared in `aws/source_security_group.tf` and `aws/replication_security_group.tf`.*

A security group is stateful. The reply to an allowed inbound connection doesn't need a second rule.

On the source server:

| Port | From | Why |
|---|---|---|
| Transmission Control Protocol (TCP) 3389 | operator `/32` | Remote Desktop |
| TCP 445, 135, and 5985 | `10.0.1.0/24` | the replication appliance installs the Mobility service |
| all outbound | `0.0.0.0/0` | the server starts its own connections, including replication |

After Azure apply creates `pip-appl-zeon`, edit the same `aws/terraform.tfvars` you copied earlier and set `discovery_winrm_cidr` to that public address with a `/32` prefix. That adds TCP 5985 from the discovery appliance only. Leave the variable empty until then. The address isn't written in the repository.

On the replication appliance:

| Port | From | Why |
|---|---|---|
| TCP 3389 | operator `/32` | Remote Desktop |
| TCP 443 and 9443 | `10.0.1.0/24` | replication control and disk data from the source |
| TCP 443 outbound | `0.0.0.0/0` | Hypertext Transfer Protocol Secure (HTTPS) to Azure |
| User Datagram Protocol (UDP) 123 outbound | `0.0.0.0/0` | time sync, which registration requires |

![source firewall rules for Remote Desktop and the Mobility ports](docs/images/step-05-aws-firewalls.png)

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

![plan summary of the AWS instances, still not applied](docs/images/step-06-aws-plan.png)

### Step 7: Pin the Azure providers

*Declared in `azure/versions.tf` and `azure/provider.tf`. Read by `terraform init` in `azure/`.*

The Terraform block requires version 1.15.x, the AzureRM provider `5.11.0`, and the HTTP provider `3.6.3`. There is no `subscription_id` line. `resource_provider_registrations = "none"`, and the file asks to register `Microsoft.Network` and `Microsoft.Compute` if they are missing. A plan can register those two.

```bash
cd azure
terraform init
```

![terraform init finished in the azure folder](docs/images/step-07-azure-init.png)

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

![tags.tf with lifetime 1d on the Azure groups](docs/images/step-08-azure-tags.png)

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

![plan summary of the two groups, the virtual network, and the NSG](docs/images/step-09-azure-plan.png)

### Step 10: Apply the AWS side

*Portal and Remote Desktop come later. This step only creates what Terraform already planned.*

Leave `replication_instance_enabled` false while quota `L-1216C47A` is below 10.

```bash
cd aws
terraform apply
```

Expect `Apply complete! Resources: 9 added` (or the count your plan showed). Confirm `ec2-migrate-src-zeon` is running as `t3.medium` and that no `ec2-migrate-repl-zeon` exists.

![AWS source instance running as t3.medium with no replication instance](docs/images/step-10-aws-source-running.png)

### Step 11: Apply the Azure side

```bash
cd ../azure
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
terraform apply
```

Expect `Apply complete! Resources: 9 added`. Confirm `vm-appl-zeon` is running as `Standard_D8as_v4` in `rg-migrate-src-zeon01`. Crop any public address and subscription id from screenshots.

![Azure discovery virtual machine running as Standard_D8as_v4](docs/images/step-11-azure-discovery-running.png)

### Step 12: Allow WinRM from the discovery appliance

*Not automated in a script. You edit the gitignored tfvars, then re-apply the source security group.*

1. Read the public address of `pip-appl-zeon` in the Azure portal or with the Azure CLI. Do not commit that address.
2. In `aws/terraform.tfvars`, set `discovery_winrm_cidr` to that address with a `/32` prefix.
3. Apply only the source firewall:

```bash
cd ../aws
terraform apply -target=aws_security_group.source
```

Confirm the source security group allows TCP 5985 from the discovery appliance (description names discovery) as well as from the subnet.

![source firewall allows TCP 5985 from the discovery appliance](docs/images/step-12-winrm-rule.png)

### Step 13: Create the Azure Migrate project

*Portal only. Terraform does not create the Migrate project.*

1. In the Azure portal, open **Azure Migrate**.
2. Choose **Create project** (or **Create** on Get started).
3. Subscription: your pay-as-you-go subscription.
4. Resource group: `rg-migrate-src-zeon01` (the staging group from step 11).
5. Project name: any unique name in the subscription (this proof used the same string as the resource group).
6. Geography: **United States** (the project metadata often shows **Central US**; the virtual machines stay in East US).
7. Create the project and wait until it appears under **All projects**.

![Azure Migrate project listed under All projects](docs/images/step-13-migrate-project.png)

### Step 14: Name the discovery appliance

*Portal only. The worldwide appliance name must be unique. This proof uses `migapplzeon01` (13 characters). Replace the `zeon01` slot with your short name and number.*

1. Open the Migrate project from step 13.
2. Under **Servers, databases and web apps** (or **Discover**), start discovery for **physical or other** servers (the AWS source is treated as a physical server for WinRM discovery).
3. Generate the appliance registration / installer package for a Windows appliance.
4. Set the appliance name to `migapplzeon01` (or your replacement) before you download the installer. Capture that name on screen.

![discovery appliance named migapplzeon01 before the installer runs](docs/images/step-14-appliance-name.png)

### Step 15: Install the appliance and sign in

*Portal download plus Remote Desktop to `vm-appl-zeon`. Not in Terraform.*

1. Copy the installer (for example `AzureMigrateInstaller.ps1` and the accompanying zip) onto `vm-appl-zeon` over Remote Desktop. Sign in with the local administrator from `azure/terraform.tfvars`.
2. Run the installer on that virtual machine and complete the appliance configuration wizard.
3. When the appliance shows **Login**, use the Login button (device code in a browser). If the page shows error **530035**, Microsoft Entra ID security defaults are blocking the device code. Turn security defaults **off** for this session: **Microsoft Entra ID** → **Properties** → **Security defaults** → **Disabled** → **Save**. Then retry Login. Leave them off until this proof is torn down.
4. Register the appliance against the Migrate project from step 13. Wait until the portal shows the appliance as connected / healthy enough to start discovery.

![appliance connected after installer and Login](docs/images/step-15-appliance-connected.png)

### Step 16: Discover the AWS source over WinRM

*Portal only. No AWS access key.*

1. In the Migrate project, add a discovery for the source using Windows Remote Management.
2. Use computer name or address for `src-zeon` / the source public address, account `migrateadmin`, and the password from `aws/terraform.tfvars`.
3. Validate the connection, then start discovery.
4. Wait until the inventory shows one Windows server. Crop any address from the screenshot.

![Azure Migrate inventory showing the one discovered server](docs/images/step-16-discovered-server.png)

### Step 17: Check the replication quota and choose a path

Replication needs a separate appliance beside the source. Before you create it, read the AWS On-Demand Standard virtual CPU quota (`L-1216C47A` in `us-east-1`). The source is 2 vCPUs and the preferred appliance is 8; both must run, so the applied value has to be at least **10**.

```bash
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-1216C47A \
  --region us-east-1 \
  --query 'Quota.Value' \
  --output text
```

This proof rechecked on 2026-10-30: the applied value was still **8.0**. A request for **16** was already `CASE_OPENED`. Do not file a second increase. Capture the command output (or the Service Quotas page) before you pick a path.

Then choose one path:

| Applied value | Path | Where to go |
|---|---|---|
| **10 or more** | **Variant A** (preferred): replication appliance on AWS next to the source | [Variant A: appliance on AWS](#variant-a-appliance-on-aws) |
| **Below 10** (this proof: 8) | **Variant B** (comparison): leave the AWS appliance off; put a replication appliance in Azure after discovery is deallocated | [Variant B: appliance in Azure](#variant-b-appliance-in-azure) |

![Standard on-demand vCPU quota still below 10](docs/images/step-17-replication-quota.png)

If the applied value is **10 or more**, follow [Variant A: appliance on AWS](#variant-a-appliance-on-aws) for steps 18 through 22 (same goals: appliance, enable replication, test migration, cutover), then step 23. If the value is **below 10**, stay on this page and continue with steps 18 through 23 for Variant B (this proof).

### Step 18: Stand up the Variant B replication appliance

*Only when step 17 chose Variant B. Variant A uses the EC2 appliance instead; see that section.*

Discovery (`vm-appl-zeon`) starts as `Standard_D8as_v4` (8 virtual CPUs). `vm-repl` was created the same size, then resized to `Standard_D8ds_v4` after the core check failed. East US Standard DASv4 Family is still 10, so two `D8as_v4` machines cannot be allocated at once. Finish steps 13 through 16 first.

1. Apply `variant-b-appliance-in-azure/` as written under [Variant B: appliance in Azure](#variant-b-appliance-in-azure). On create, `deallocate_discovery.tf` deallocates discovery and, if family usage stays high, deletes **only** the discovery virtual machine. The Migrate project resource group stays.
2. Confirm `vm-repl` is running in `rg-migrate-repl-zeon01`. Keep the admin password from `TF_VAR_replication_admin_password` for Remote Desktop.

![variant B replication appliance running after discovery was freed](docs/images/step-17-variant-b-appliance.png)

### Step 19: Open the copy path between the source and `vm-repl`

*Terraform on both clouds. Without these rules, the Mobility service cannot install or send disks.*

1. Read the public address of `pip-repl` (Variant B) and the public address of `ec2-migrate-src-zeon`. Do not commit either address.
2. In `variant-b-appliance-in-azure/`, set `TF_VAR_source_replication_cidr` to the **source** public address with a `/32` prefix, then `terraform plan` and `terraform apply`. That allows TCP 443 and 9443 in from the source, and TCP 5985, 445, and 135 out to the source.
3. In `aws/terraform.tfvars`, set `variant_b_mobility_cidr` to the **`pip-repl`** public address with a `/32` prefix (empty until then). Apply the source security group so TCP 445, 135, and 5985 also allow that Azure appliance (the subnet rules alone only cover Variant A inside `10.0.1.0/24`).

```bash
# Variant B NSG (from variant-b-appliance-in-azure/)
export TF_VAR_source_replication_cidr="<source-public-ip>/32"
terraform plan
terraform apply

# AWS source SG (from aws/, after editing terraform.tfvars)
terraform apply -target=aws_security_group.source
```

![NSG and source SG rules for Variant B copy path](docs/images/step-19-copy-path-rules.png)

### Step 20: Install the replication appliance and enable replication

*Portal download plus Remote Desktop to `vm-repl`. Not in Terraform.*

The current Azure Migrate hub does **not** use the old left-nav label “Windows, Linux and SQL servers.” Use **Execute → Migrations** instead (same project you already opened for discovery).

1. In the Migrate project left menu: **Execute** → **Migrations** → **Start execution**.
2. On **Specify intent**: migrate **Servers or virtual machines (VMs)** → destination **Azure VM**.
3. Under how you select workloads / other sources, choose **From replication appliance (Physical or Others)**. Open the setup link on that page (this is where the portal creates Site Recovery resources and gives you the installer / project key). Confirm the target region matches this proof (`eastus` unless you chose another) and select **Create resources** when prompted.
4. Generate a key (appliance name unique, for example `replapplzeon01` — discovery already used `migapplzeon01`). Copy the key; do not commit it.
5. Download the **replication** package onto `vm-repl` (Edge, not Internet Explorer). The current installer is `DRAppliance.zip` / `DRInstaller.ps1`. Microsoft's short link is `https://aka.ms/V2ARcmApplianceCreationPowershellZip`. Do not reuse the discovery OVA or `AzureMigrateInstaller.zip`.
6. Before you run the script: initialize the attached 620 GB cache disk (`disk-repl-cache`). On Azure Windows, **D:** is the small temporary disk. `DRInstaller.ps1` counts formatted free space only. If you skip this, it prints `Aborting the installation, as atleast 600 GB free space is required to proceed` while C: is about 107 GB free and D: is about 59 GB. In an elevated PowerShell session:

```powershell
Get-Disk | Where-Object PartitionStyle -eq 'Raw' | Initialize-Disk -PartitionStyle GPT -PassThru |
  New-Partition -AssignDriveLetter -UseMaximumSize |
  Format-Volume -FileSystem NTFS -NewFileSystemLabel 'repl-cache' -Confirm:$false
Get-PSDrive -PSProvider FileSystem
```

You should see a new letter with about 620 GB free. Then:

```powershell
cd $env:USERPROFILE\Downloads\DRAppliance\DRAppliance
Set-ExecutionPolicy -Scope Process Bypass -Force
.\DRInstaller.ps1
```

![DRInstaller aborting until the 620 GB cache disk is formatted](docs/images/step-20-cache-space-check.png)

![DRInstaller installation completed on vm-repl](docs/images/step-20-installer-complete.png)

Register with the project key (device-code Login; turn Entra security defaults off again if error **530035** appears). If the configuration manager says the server has only 4 CPU cores on `Standard_D8as_v4`, resize to `Standard_D8ds_v4` (Intel, keeps the temporary disk) and Retry. Do not treat installer success as replication health.

![Azure Site Recovery counting 4 cores on Standard_D8as_v4](docs/images/step-20-core-check-failed.png)

7. Back in **Start execution**, select the discovered machine `src-zeon`. Target the existing network: resource group `rg-migrate-tgt-zeon01`, virtual network `vnet-migrate-zeon`, subnet `snet-migrate`. Start replication.
8. Wait until Azure Migrate shows replication health that you can honestly call healthy (or record the exact failure in `variant-b-appliance-in-azure/FINDINGS.md`). Do not invent a green page.

<!-- ![replication appliance registered and replication enabled for src-zeon](docs/images/step-20-replication-enabled.png) -->

### Step 21: Test migration

*Portal only. Creates a temporary test virtual machine in the target network.*

1. In Azure Migrate, start a **Test migration** for `src-zeon` into `vnet-migrate-zeon` / `snet-migrate`.
2. Wait until the test virtual machine is running. Confirm you can reach it the way the portal describes (often Remote Desktop on the test NIC). Crop addresses from screenshots.
3. Clean up the test migration when you are done with the check so you are not billed for two copies.

<!-- ![test migration virtual machine running in vnet-migrate-zeon](docs/images/step-21-test-migration.png) -->

### Step 22: Cut over into the target group

*Portal only. This is the step that creates the real migrated server.*

1. In Azure Migrate, run **Migrate** / cutover for `src-zeon` into `rg-migrate-tgt-zeon01` and `vnet-migrate-zeon`.
2. Wait until a Windows virtual machine exists in that resource group and shows as running.
3. Confirm it is the cutover result (name from the portal), not only the test migration leftover. Crop subscription ids and addresses.

<!-- ![cutover virtual machine in rg-migrate-tgt-zeon01](docs/images/step-22-cutover.png) -->

### Step 23: Clean up when you're done

Tear every side down after the portal work, remaining screenshots, and the walkthrough video are finished. The discovery and replication appliances bill by the hour. If you have to pause overnight, set `lifetime=keep` on the Azure groups (and in `azure/tags.tf` plus `variant-b-appliance-in-azure/tags.tf`) so the nightly sweep does not delete them. Set those tags back to `1d` in the same change as destroy.

1. In the portal, remove Migrate discoveries / replications / appliances you created if the portal still lists them, and delete any cutover or test virtual machines you no longer need.
2. If you used Variant B: `terraform destroy` in `variant-b-appliance-in-azure/`.
3. `terraform destroy` in `azure/`. Expect a refresh warning if `vm-appl-zeon` was already deleted outside that state. Then delete any portal leftovers the destroy missed: `az group delete --name rg-migrate-src-zeon01` and `az group delete --name rg-migrate-tgt-zeon01` (and `rg-migrate-repl-zeon01` if it still exists), after you type each name. Soft-deleted Key Vault names from appliance runs may need a separate purge.
4. `terraform destroy` in `aws/`.
5. Turn Microsoft Entra ID security defaults back **on** if you disabled them for appliance Login.

There's no teardown script yet. The nightly sweep deletes Azure groups tagged `lifetime=1d`, but it does not remove Entra app registrations, and it does not destroy the AWS network.

<!-- ![both resource groups gone after teardown](docs/images/step-23-teardown.png) -->

---

## Automated setup

### Run this as yourself

The names in this repository are the ones I used for my own proof of concept, so don't edit the two `variables.tf` files. Make your own copies and swap my short name (`zeon`) for yours. The names follow the [naming standard](https://github.com/zsociety47/cloud-projects/blob/main/standards/NAMING-STANDARD.md): type, project or role, then your short name (`rg-migrate-src-zeon01` becomes `rg-migrate-src-ada01`). The Azure Migrate appliance name has to be unique worldwide, so `migapplzeon01` can't stay.

This repository has two Terraform roots. `terraform.tfvars` is gitignored in both, so it never appears from a clone. You create each file by copying the committed example, then you edit that copy.

| Open this | Do this |
|---|---|
| [`aws/terraform.tfvars.example`](aws/terraform.tfvars.example) | Copy to `aws/terraform.tfvars` (gitignored). Replace every `yourname` with your short name, including `tags.owner`. Set `discovery_password`. Leave `discovery_winrm_cidr` as `""` until the Azure discovery public address exists. Leave `variant_b_mobility_cidr` as `""` until Variant B's `pip-repl` exists (step 19). Don't reuse my key pair name, `key-migrate-zeon`. |
| [`aws/variables.tf`](aws/variables.tf) | Leave this one alone. Its defaults are the names from my own proof. |
| [`azure/terraform.tfvars.example`](azure/terraform.tfvars.example) | Copy to `azure/terraform.tfvars` (gitignored). Replace every `yourname` with your short name, including `tags.owner` and `discovery_appliance_name`. Set `discovery_admin_password`. |
| [`azure/variables.tf`](azure/variables.tf) | Leave this one alone. Its defaults are the names from my own proof. |

```bash
cp aws/terraform.tfvars.example aws/terraform.tfvars
cp azure/terraform.tfvars.example azure/terraform.tfvars
```

After the copy, open each `terraform.tfvars` and replace `REPLACE_ME` with a real password. Generate one that already matches the rules (12+ characters, upper, lower, number, symbol; no `"`, `$`, or backtick; and not containing `migrateadmin`):

```bash
./scripts/gen-password.sh --length 16 --username migrateadmin
```

That script matches [`cloud-projects/standards/scripts/gen-password.sh`](https://github.com/zsociety47/cloud-projects/blob/main/standards/scripts/gen-password.sh). Paste the printed value into the gitignored file (or export it for variant B). Do not commit it. Confirm both tfvars files are ignored:

```bash
git check-ignore -v aws/terraform.tfvars azure/terraform.tfvars
```

Each line should name `.gitignore`. Run the AWS root and the Azure root separately. Each one keeps its own local state file.

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

### Fill the passwords in the tfvars you already copied

If you skipped **Run this as yourself**, go back and run the two `cp` commands. The password lines are already in those files as `REPLACE_ME`.

In `aws/terraform.tfvars`, set `discovery_password` (local account `migrateadmin` on the AWS source). Leave `discovery_winrm_cidr` empty until after Azure apply.

In `azure/terraform.tfvars`, set `discovery_admin_password` (administrator on `vm-appl-zeon`). It can differ from the source password.

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

`plan` lists the two groups, the virtual network, the subnet, the firewall, `pip-appl-zeon`, `nic-appl-zeon`, and `vm-appl-zeon`. It doesn't print the administrator password. It may register `Microsoft.Network` and `Microsoft.Compute`. East US total regional virtual CPUs were raised to 20, but the Standard DASv4 family limit is still 10, and this virtual machine uses 8 of those 10.

### Apply

Don't apply yet. An AWS apply with the default switch creates the network and the source, which fits the quota of 8. It doesn't create the replication appliance. Azure apply creates the discovery virtual machine, which bills by the hour. Those groups are tagged `lifetime=1d`, so the nightly sweep can delete them.

### Verify the AWS side

```bash
./scripts/verify-aws.sh
```

The script reads the live virtual private cloud, the source server, and the source firewall. It prints a pass or fail line for each check and doesn't print public addresses. The replication appliance is allowed to be off. A running appliance passes only when it is `c5.2xlarge` with a 620 GiB cache disk. The checks in [Success criteria](#success-criteria) still cover discovery, replication, and cutover, which this script doesn't.

### Teardown

No teardown script exists. See [Step 18](#step-18-clean-up-when-youre-done).

---

## Architecture

![Design picture of the AWS source, the replication appliance, and the Azure target network](docs/architecture/architecture.png)

*Reference picture. On that picture, a solid box is built with Terraform, a dashed box is made in the portal or at cutover, and a dotted box is declared and not created yet.*

```mermaid
flowchart LR
    operator["Your Mac<br/>Terraform and Remote Desktop"]

    subgraph awsnet["AWS · us-east-1 · vpc-migrate-zeon"]
        source["ec2-migrate-src-zeon<br/>source server · running"]
        repl["ec2-migrate-repl-zeon<br/>declared, switched off"]
    end

    subgraph azcloud["Azure · East US"]
        subgraph staging["rg-migrate-src-zeon01 · lifetime=1d"]
            discovery["vm-appl-zeon<br/>discovery appliance · deleted after discovery"]
            migrate["Azure Migrate project<br/>made by hand in the portal"]
        end
        subgraph tgt["rg-migrate-tgt-zeon01 · lifetime=1d"]
            vnet["vnet-migrate-zeon · 10.6.0.0/16<br/>firewall nsg-migrate-tgt-zeon"]
            landed["Target for the migrated server<br/>not created · no cutover"]
        end
        subgraph replrg["rg-migrate-repl-zeon01 · variant B"]
            vmrepl["vm-repl<br/>replication appliance in Azure · running"]
        end
    end

    operator -- "terraform apply" --> source
    operator -- "terraform apply" --> vnet
    operator -- "terraform apply" --> vmrepl
    discovery -- "WinRM 5985" --> source
    discovery -. "inventory · portal" .-> migrate
    source -. "ports 443 + 9443 · variant A, not built" .-> repl
    source -. "disk copy · unverified" .-> vmrepl
    migrate -. "cutover · not run" .-> landed
    vnet -. "lands in · not yet" .-> landed

    classDef azure fill:#0078d4,stroke:#005a9e,color:#fff
    classDef external fill:#6e7681,stroke:#484f58,color:#fff
    classDef portal fill:#fff,stroke:#0078d4,color:#1f2328,stroke-dasharray:9 6
    classDef plannedaws fill:#fff,stroke:#6e7681,color:#1f2328,stroke-dasharray:3 4
    classDef plannedaz fill:#fff,stroke:#0078d4,color:#1f2328,stroke-dasharray:3 4

    class discovery,vnet,vmrepl azure
    class operator,source external
    class migrate portal
    class repl plannedaws
    class landed plannedaz
```

*Live map, Oct 30. A solid arrow is in the files today. A dotted arrow is portal work, planned, unverified, or not run yet, and its label says which. Gray is AWS and your Mac. Blue is Azure. The design picture above shows the same resources.*

### How to read this diagram

- The operator reaches Windows machines only on TCP 3389, and only from the address collected at plan time.
- The source and the appliance share `10.0.1.0/24`. The appliance, when it exists, installs the Mobility service on the source over TCP 445, 135, and 5985.
- `vm-appl-zeon` was created in the staging group, on `snet-migrate`, read the source over WinRM, and was then deleted (only that machine, the Migrate project stays) to free the Standard DASv4 family count for `vm-repl`. The source firewall allows TCP 5985 from that appliance's address once `discovery_winrm_cidr` is set. The installer is a portal step.
- The replication appliance is declared and switched off until the virtual CPU quota reaches 10.
- The migrated server, the vault, and the cache storage account are created by Azure Migrate. Terraform doesn't declare them, and none of them exists yet.
- Variant B is a separate Terraform folder with its own state. `vm-repl` runs in `rg-migrate-repl-zeon01`. Whether it can copy from AWS is unverified, so that arrow stays dotted.

---

## Variant A: appliance on AWS

This is the preferred path when step 17’s applied quota is **10 or more**. The replication appliance stays in the same virtual private cloud (VPC) as the source, which matches Microsoft’s AWS guidance. If the applied value is still below 10, skip this section and use [Variant B: appliance in Azure](#variant-b-appliance-in-azure) instead.

1. In `aws/terraform.tfvars`, set `replication_instance_enabled` to `true`.
2. In `aws/`, run `terraform plan`, read it, then `terraform apply`. Expect `ec2-migrate-repl-zeon` (`c5.2xlarge`) and the 620 GiB cache disk.
3. In the Azure Migrate project, download the replication appliance installer (`DRInstaller.ps1` / the portal package for the configuration and process server).
4. Remote Desktop to `ec2-migrate-repl-zeon` (operator `/32` only). Run the installer, register it to the same Migrate project, and enable replication for the discovered `src-zeon` machine.
5. Wait for replication health in the portal. Do not invent a green health page you have not seen. Teardown is still step 18 (destroy AWS last among the Terraform roots that created the appliance).

Discovery (`vm-appl-zeon`) can stay up for inventory; variant A does not need the East US DASv4 family free for a second Azure appliance.

---

## Variant B: appliance in Azure

Variant A keeps the replication appliance on AWS, in the same virtual private cloud as the source. That matches Microsoft's AWS guidance. Variant B is for when the AWS On-Demand Standard vCPU quota cannot hold source plus appliance at once (step 17 still below 10). Checking that quota, filing an increase, and choosing a documented path is ordinary cloud work. A production subscription often has more headroom. A small account may not. This folder is the comparison path for that case, not a claim that Azure is the better place for the appliance. Prefer [Variant A: appliance on AWS](#variant-a-appliance-on-aws) when the AWS quota clears.

Variant B is a separate Terraform folder, `variant-b-appliance-in-azure`, with its own state. The AWS source stays in `aws/`. Only the replication appliance moves. It is a `Standard_D8ds_v4` (8 virtual central processing units, 32 GB, with a temporary disk) in `rg-migrate-repl-zeon01`, on `10.7.0.0/16`. Do not use `Standard_D8as_v4` here: Azure still counts 8 virtual CPUs, but the guest reports 4 cores and the replication installer fails. East US had no capacity for `Standard_D8s_v3`. `Standard_D8s_v4` cannot replace a size that already has a temporary disk.

### Variant B steps

The numbered **Project Steps** above are the source of truth for operators: **18** (stand up `vm-repl`), **19** (open the copy path), **20** (install and enable replication), **21** (test migration), **22** (cutover), **23** (teardown). This section is the short reference for the Terraform folder and the comparison table.

Finish discovery shots (steps 13–16) and the quota shot (step 17) first. Leave `replication_instance_enabled` false.

```bash
cd variant-b-appliance-in-azure
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
export TF_VAR_replication_admin_password="$(../scripts/gen-password.sh --length 16 --username migrateadmin)"
# Keep that value somewhere you can use for Remote Desktop. It is not in a tfvars file.
terraform init
terraform plan
terraform apply
```

`apply` runs `deallocate_discovery.tf` first, then creates `rg-migrate-repl-zeon01`, the network, `vm-repl`, and the 620 GB cache disk. See `FINDINGS.md` for what stays unverified until step 20 shows a real health page.

| | Variant A | Variant B |
|---|---|---|
| AWS capacity needed | 10 virtual central processing units: source 2 plus appliance 8. Quota `L-1216C47A` is still 8 (open request for 16). | 2 virtual central processing units: the source only. |
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
| 3 | Discovery finds `src-zeon` over WinRM with `migrateadmin` | Azure Migrate inventory, with no AWS access key in the repo | Passed 2026-10-30: inventory shows `src-zeon` (step 16) |
| 4 | Replication copies disk changes through the replication appliance (Variant A: `ec2-migrate-repl-zeon`; Variant B: `vm-repl`) | Azure Migrate replication health | Not checked |
| 5 | A test migration boots in `vnet-migrate-zeon` | the test virtual machine on `snet-migrate` | Not checked |
| 6 | Cutover leaves the server in `rg-migrate-tgt-zeon01` | the resource group after cutover | Not checked |
| 7 | Teardown removes the AWS instances and the Azure groups (including `rg-migrate-repl-zeon01` when Variant B was used) | `terraform destroy` in each root that was applied, then `az group delete` for leftovers | Not checked |

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
  gen-password.sh                 local password for tfvars / TF_VAR_ (same as cloud-projects/standards)
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
  deallocate_discovery.tf         az vm deallocate on vm-appl-zeon before vm-repl
  replication_virtual_machine.tf  Windows Server 2022, Standard_D8ds_v4
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
- **Azure groups are short-lived except during an overnight hold.** Default is `lifetime=1d` so the nightly sweep can delete them. This pass is tagged `keep` until the remaining portal work and the video are done, then tags go back to `1d` in the same change as destroy. The state file stays local.

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
- **The Standard vCPU quota blocks variant A.** Quota `L-1216C47A`, Running On-Demand Standard (A, C, D, H, I, M, R, T, Z), still has an applied value of 8 in `us-east-1` (rechecked 2026-10-30; see step 17). The source is 2 vCPUs and the appliance is 8, and replication needs both running, so the applied value has to be at least 10. Request 10 if nothing is open. A larger number is more likely to be reviewed by a person. This account already had a request for 16 open (`CASE_OPENED`); that request was left as filed. Do not file a second one. With the switch false, this rebuild kept the source and skipped the AWS replication instance. Prefer [Variant A](#variant-a-appliance-on-aws) when the applied value reaches 10; use [Variant B](#variant-b-appliance-in-azure) while it stays at 8.
- **The preferred replication appliance stays in the source VPC.** Azure Migrate runs a configuration server and a process server on that machine. The process server receives disk blocks from the Mobility service on the source over TCP 9443, compresses and encrypts them, holds them on the cache disk, and uploads them to Azure over HTTPS 443. Microsoft requires 8 cores, 16 GB of memory, a separate cache disk of at least 600 GB, and a machine in the same VPC as the source. A smaller size fails that check. Variant B puts the appliance in Azure only as a comparison when AWS capacity is short. Whether that copy works is unverified until a green health page says so.
- **East US DASv4 family still forces one Azure appliance at a time while both are that size.** Total Regional vCPUs were raised to 20. Standard DASv4 Family stays at 10. Discovery started as `Standard_D8as_v4`. `vm-repl` was created the same size, then resized to `Standard_D8ds_v4` after Azure Site Recovery counted 4 guest cores. Deallocate or delete discovery before creating the first `D8as_v4` appliance.
- **`DRInstaller.ps1` needs 600 GB of formatted free space.** Exact stop: `Aborting the installation, as atleast 600 GB free space is required to proceed`. C: was about 107 GB free and D: (Azure temporary disk) about 59 GB. The 620 GB cache disk did not count until it was initialized. See `docs/images/step-20-cache-space-check.png`.
- **AMD `Standard_D8as_v4` fails the appliance core check.** Exact stop: `The server has only 4 CPU cores`. Azure still showed 8 virtual CPUs. `Standard_D8s_v3` returned `SkuNotAvailable` in East US. `Standard_D8s_v4` was refused because a resize cannot drop the temporary disk. `Standard_D8ds_v4` kept the disk. See `docs/images/step-20-core-check-failed.png`.
- **The earlier plan is stale.** That plan reported `12 to add, 0 to change, 0 to destroy` before the Mobility ingress rules. Plan again before apply. The plan file was deleted because it contained the operator public address.
- **PowerShell dollars in `templatefile`.** Terraform interpolates `${name}`. A PowerShell `$` in the guest script has to be written `$$`, or avoided. The scripts pass the computer name, the username, and the password in as Terraform variables.
- **The cache disk is a separate resource.** Putting it in `ebs_block_device` would replace the instance when the disk changes. `aws_ebs_volume` plus `aws_volume_attachment` keeps the instance stable.
- **The NSG attaches in its own file.** This provider has no `network_security_group_id` argument on the subnet. `azurerm_subnet_network_security_group_association` is the attachment.
- **`created` would change every plan.** `timestamp()` is a new value each run. `lifecycle { ignore_changes = [tags["created"]] }` keeps the first value.
- **The configuration server is retired.** Microsoft retired the classic configuration server on 2026-09-30. This build uses the simplified replication appliance, still installed later with `DRInstaller.ps1`.
- **Security defaults block the appliance Login.** Error 530035 means the sign-in was blocked by security defaults. The Login button uses a device code against Microsoft Azure PowerShell. This directory has no premium license, so conditional access can't allow that one flow. A preconfigured application and certificate would also skip Login. That path isn't used here. Anyone following along wouldn't see the same screens, and Microsoft doesn't support it for the replication appliance.
