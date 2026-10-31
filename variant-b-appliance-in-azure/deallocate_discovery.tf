# Free East US Standard DASv4 family capacity before vm-repl starts.
# Discovery (vm-appl-zeon) and this appliance are both Standard_D8as_v4
# (8 virtual CPUs each). The family limit on this account is 10, so both
# cannot be allocated at once. A plain shutdown keeps the cores.
#
# Prefer az vm deallocate (disks and the Migrate project stay). On this
# subscription, family usage sometimes still shows 8 after deallocate.
# If usage stays too high for another 8-core machine, this step deletes
# only the discovery virtual machine (not the resource group). Finish
# discovery screenshots before apply. The azure/ state will then show
# the VM as gone until you destroy or import; that is expected for
# variant B on a stuck family quota.
#
# Requires the Azure CLI, signed in, with ARM_SUBSCRIPTION_ID set the
# same way as the azure/ root. Destroy of this folder does not recreate
# discovery.

resource "terraform_data" "deallocate_discovery" {
  input = {
    resource_group = var.discovery_resource_group_name
    vm_name        = var.discovery_virtual_machine_name
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      rg='${var.discovery_resource_group_name}'
      name='${var.discovery_virtual_machine_name}'
      location='eastus'
      family_query="[?name.localizedValue=='Standard DASv4 Family vCPUs'].currentValue"

      family_usage() {
        az vm list-usage -l "$location" --query "$family_query" -o tsv
      }

      if ! az vm show --resource-group "$rg" --name "$name" --query name -o tsv >/dev/null 2>&1; then
        echo "discovery VM already absent: $rg/$name (usage=$(family_usage))"
        exit 0
      fi

      power="$(az vm get-instance-view \
        --resource-group "$rg" \
        --name "$name" \
        --query "instanceView.statuses[?starts_with(code, 'PowerState/')].code" \
        -o tsv)"
      if [[ "$power" != "PowerState/deallocated" ]]; then
        echo "deallocating discovery (not destroy): $rg/$name (was $power)"
        az vm deallocate --resource-group "$rg" --name "$name"
      else
        echo "discovery already deallocated: $rg/$name"
      fi

      # Wait for family usage to drop. Deallocate should free cores; if it
      # does not, delete only the VM so vm-repl can allocate.
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        usage="$(family_usage)"
        echo "Standard DASv4 Family currentValue=$usage"
        if [[ "$${usage:-8}" -le 2 ]]; then
          exit 0
        fi
        sleep 15
      done

      echo "family usage still high after deallocate; deleting discovery VM only (RG kept)"
      az vm delete --resource-group "$rg" --name "$name" --yes
      usage="$(family_usage)"
      echo "after delete: Standard DASv4 Family currentValue=$usage"
    EOT
  }
}
