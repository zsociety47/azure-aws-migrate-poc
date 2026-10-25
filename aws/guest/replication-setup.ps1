# First boot for the replication appliance.
# The instance file renders this with templatefile before the machine
# is created. Placeholder: computer_name.
#
# This machine receives disk changes from the source server and sends
# them to Azure. It does not create a discovery account, and it does not
# open Windows Remote Management. The installer for the appliance is
# added later, from the portal, after the machine exists.
#
# The Windows computer name is set here because registration uses that
# name, and Windows keeps it after the restart.

Rename-Computer -NewName "${computer_name}" -Force -Restart
