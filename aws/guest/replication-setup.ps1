# First boot for the replication appliance.
# The instance file renders this with templatefile before the machine
# is created. Placeholder: computer_name.
#
# This machine receives disk changes from the source server and sends
# them to Azure. It has to be the 8-virtual-CPU replication appliance in
# the source virtual private cloud. Microsoft requires 8 cores, 16 GB of
# memory, and a cache disk of at least 600 GB. The source uses 2 more
# virtual CPUs, so quota L-1216C47A in us-east-1 has to be at least 10
# before both are running. Request 10. Leave a higher request alone if
# one is already open. This script does not create a discovery account,
# and it does not open Windows Remote Management. The installer for the
# appliance is added later, from the portal, after the machine exists.
#
# The Windows computer name is set here because registration uses that
# name, and Windows keeps it after the restart.

Rename-Computer -NewName "${computer_name}" -Force -Restart
