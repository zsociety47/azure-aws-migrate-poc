# Findings: replication appliance in Azure

Public. No passwords, keys, subscription ids, tenant ids, or addresses.

Reading quotas and choosing a path is part of the work. A larger subscription might clear these limits without a workaround. This proof documents what to do when they do not clear, because the same checks show up on any job that sizes appliances against account capacity.

## 1. The quota blocks variant A

Running On-Demand Standard quota `L-1216C47A` in `us-east-1` has an applied value of 8. Rechecked 2026-10-30. The source is a `t3.medium` (2 virtual central processing units). The replication appliance in variant A is a `c5.2xlarge` (8). Both have to run, so variant A needs 10. A request for 16 is open, case `179296523000916`, status `CASE_OPENED`. Do not file a second request and do not lower that one.

Variant B keeps the source and moves the replication appliance to Azure, so the AWS side stays at 2 virtual central processing units. That is the path this folder supports while the AWS request waits.

## 2. East US family quota still forces one Azure appliance at a time

East US Total Regional vCPUs (`cores`) was raised to 20. Standard DASv4 Family vCPUs is still limit 10 (rechecked 2026-10-29). Discovery (`vm-appl-zeon`, `Standard_D8as_v4`) is 8. This appliance is also `Standard_D8as_v4`, so it is also 8. Regional cores can cover both, but the family limit cannot. Allocate one of them. Deallocate discovery before starting this appliance. Shutting down without deallocating keeps the cores. `deallocate_discovery.tf` runs on apply (not `terraform destroy` of the azure/ root). Rechecked 2026-10-30: after `az vm deallocate`, family usage still read 8 and `vm-repl` create returned 409. Deleting only the discovery virtual machine dropped usage to 0 and the apply succeeded. The script now waits, then deletes the VM if usage stays high. The Migrate project resource group stays.

## 3. `DRInstaller.ps1` needs 600 GB of formatted free space

Exact stop on 2026-10-30 on `vm-repl` ([shot](../docs/images/step-20-cache-space-check.png)):

```
Aborting the installation, as atleast 600 GB free space is required to proceed...
```

C: showed about 107 GB free (127 GB operating-system disk). D: showed about 59 GB free (Azure temporary disk). The 620 GB cache disk `disk-repl-cache` was already attached at LUN 0 and left raw on purpose. The installer does not count an uninitialized disk. Format that disk (NTFS, new drive letter; do not format D:), then rerun `DRInstaller.ps1`. README step 20 has the commands.

## 4. AMD `Standard_D8as_v4` fails the appliance core check

Exact stop on 2026-10-30 in `https://localhost:44368` ([shot](../docs/images/step-20-core-check-failed.png)):

```
Memory and CPU validation failed.
The server has only 4 CPU cores. We recommend 8 cores for best performance.
```

The virtual machine was `Standard_D8as_v4` (8 virtual CPUs, 32 GB). Azure reports that size. The guest still reports 4 cores because this AMD size exposes simultaneous multithreading that way. The configuration manager counts cores, not Azure virtual CPUs. Retry does not clear it. `Standard_D8s_v3` returned `SkuNotAvailable` in East US. `Standard_D8s_v4` was refused: you cannot drop a temporary disk on resize. Resized 2026-10-30 to Intel `Standard_D8ds_v4` (temporary disk kept; Standard DDSv4 family limit 10, usage was 0). Regional cores stay 8 of 20. Deallocate first, then resize. After start, open `https://localhost:44368` and select Retry.

## 5. UNVERIFIED until the first replication attempt

(a) Replication works with this appliance in Azure for an AWS source. Microsoft's AWS guidance puts the replication appliance in the source virtual private cloud. This folder does the other placement so it can be compared. Do not state that the copy succeeds.

(b) Which direction the Windows Remote Management (WinRM) agent push goes with this layout. The firewall can allow TCP 443 and 9443 in from the source address, and TCP 5985, 445, and 135 out to that same address. Those rules are added only after `source_replication_cidr` is set. They are not proof of which way the push travels. The AWS source firewall is unchanged: it still allows TCP 445, 135, and 5985 only from `10.0.1.0/24`.
