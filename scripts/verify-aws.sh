#!/bin/bash
# Reads the live Amazon Web Services (AWS) side and prints a pass/fail table.
# Inputs: AWS command-line interface (CLI) credentials. The region is us-east-1.
# Output: numbered PASS or FAIL lines. Exit 0 when all pass, exit 1 otherwise.
# Side effects: none. This script does not create or delete resources.
# It does not print public addresses, account ids, or passwords.
#
# The replication appliance is allowed to be absent. Quota L-1216C47A is
# often 8, and the source plus that appliance need 10. A running appliance
# passes only when it is c5.2xlarge and its cache disk is 620 GiB.

set -u
set -o pipefail

region="us-east-1"
vpc_name="vpc-migrate-zeon"
vpc_cidr="10.0.0.0/16"
subnet_name="snet-migrate-zeon"
subnet_cidr="10.0.1.0/24"
availability_zone="us-east-1a"
gateway_name="igw-migrate-zeon"
source_group="migrate-src-sg-zeon"
key_name="key-migrate-zeon"
source_name="ec2-migrate-src-zeon"
source_type="t3.medium"
replication_name="ec2-migrate-repl-zeon"
replication_type="c5.2xlarge"
cache_name="vol-migrate-repl-zeon"
cache_size="620"

failed=0
pass() { printf '%s  %s: PASS\n' "$1" "$2"; }
fail() { printf '%s  %s: FAIL\n' "$1" "$2"; failed=1; }

vpc_cidr_live="$(aws ec2 describe-vpcs --region "$region" \
  --filters "Name=tag:Name,Values=${vpc_name}" \
  --query 'Vpcs[0].CidrBlock' --output text 2>/dev/null || true)"
if [[ "$vpc_cidr_live" == "$vpc_cidr" ]]; then
  pass 1 "VPC ${vpc_name} is ${vpc_cidr}"
else
  fail 1 "VPC ${vpc_name} is ${vpc_cidr}"
fi

subnet_live="$(aws ec2 describe-subnets --region "$region" \
  --filters "Name=tag:Name,Values=${subnet_name}" \
  --query 'Subnets[0].[CidrBlock,AvailabilityZone]' --output text 2>/dev/null || true)"
if [[ "$subnet_live" == "${subnet_cidr}	${availability_zone}" ]]; then
  pass 2 "Subnet ${subnet_name} is ${subnet_cidr} in ${availability_zone}"
else
  fail 2 "Subnet ${subnet_name} is ${subnet_cidr} in ${availability_zone}"
fi

gateway_state="$(aws ec2 describe-internet-gateways --region "$region" \
  --filters "Name=tag:Name,Values=${gateway_name}" \
  --query 'InternetGateways[0].Attachments[0].State' --output text 2>/dev/null || true)"
if [[ "$gateway_state" == "available" ]]; then
  pass 3 "Internet gateway ${gateway_name} is attached"
else
  fail 3 "Internet gateway ${gateway_name} is attached"
fi

source_live="$(aws ec2 describe-instances --region "$region" \
  --filters "Name=tag:Name,Values=${source_name}" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceType' --output text 2>/dev/null || true)"
if [[ "$source_live" == "$source_type" ]]; then
  pass 4 "Source ${source_name} is running as ${source_type}"
else
  fail 4 "Source ${source_name} is running as ${source_type}"
fi

source_address="$(aws ec2 describe-instances --region "$region" \
  --filters "Name=tag:Name,Values=${source_name}" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text 2>/dev/null || true)"
if [[ -n "$source_address" && "$source_address" != "None" ]]; then
  pass 5 "Source ${source_name} has a public address"
else
  fail 5 "Source ${source_name} has a public address"
fi

group_json="$(aws ec2 describe-security-groups --region "$region" \
  --filters "Name=group-name,Values=${source_group}" \
  --output json 2>/dev/null || echo '{"SecurityGroups":[]}')"

rdp_ok="$(printf '%s' "$group_json" | python3 -c '
import json, sys
groups = json.load(sys.stdin).get("SecurityGroups", [])
cidrs = []
if groups:
    for perm in groups[0].get("IpPermissions", []):
        if perm.get("IpProtocol") == "tcp" and perm.get("FromPort") == 3389 and perm.get("ToPort") == 3389:
            cidrs.extend(item.get("CidrIp", "") for item in perm.get("IpRanges", []))
ok = len(cidrs) == 1 and cidrs[0].endswith("/32") and cidrs[0] != "0.0.0.0/0"
print("yes" if ok else "no")
')"
if [[ "$rdp_ok" == "yes" ]]; then
  pass 6 "Source Remote Desktop allows one /32 address"
else
  fail 6 "Source Remote Desktop allows one /32 address"
fi

mobility_ok="$(printf '%s' "$group_json" | python3 -c '
import json, sys
groups = json.load(sys.stdin).get("SecurityGroups", [])
perms = groups[0].get("IpPermissions", []) if groups else []

def cidrs(port):
    found = []
    for perm in perms:
        if perm.get("IpProtocol") == "tcp" and perm.get("FromPort") == port and perm.get("ToPort") == port:
            found.extend(item.get("CidrIp", "") for item in perm.get("IpRanges", []))
    return found

needed = all("10.0.1.0/24" in cidrs(port) for port in (445, 135, 5985))
wide = any("0.0.0.0/0" in cidrs(port) for port in (3389, 445, 135, 5985, 443, 9443))
print("yes" if needed and not wide else "no")
')"
if [[ "$mobility_ok" == "yes" ]]; then
  pass 7 "Source firewall allows TCP 445, 135, and 5985 from 10.0.1.0/24"
else
  fail 7 "Source firewall allows TCP 445, 135, and 5985 from 10.0.1.0/24"
fi

key_live="$(aws ec2 describe-key-pairs --region "$region" \
  --key-names "$key_name" \
  --query 'KeyPairs[0].KeyName' --output text 2>/dev/null || true)"
if [[ "$key_live" == "$key_name" ]]; then
  pass 8 "Key pair ${key_name} exists"
else
  fail 8 "Key pair ${key_name} exists"
fi

repl_type="$(aws ec2 describe-instances --region "$region" \
  --filters "Name=tag:Name,Values=${replication_name}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[0].Instances[0].InstanceType' --output text 2>/dev/null || true)"
cache_live="$(aws ec2 describe-volumes --region "$region" \
  --filters "Name=tag:Name,Values=${cache_name}" \
  --query 'Volumes[0].Size' --output text 2>/dev/null || true)"

if [[ -z "$repl_type" || "$repl_type" == "None" ]]; then
  if [[ -z "$cache_live" || "$cache_live" == "None" ]]; then
    pass 9 "Replication appliance is off"
  else
    fail 9 "Replication appliance is off, but cache disk ${cache_name} still exists"
  fi
elif [[ "$repl_type" == "$replication_type" && "$cache_live" == "$cache_size" ]]; then
  pass 9 "Replication appliance is running as ${replication_type} with a ${cache_size} GiB cache disk"
else
  fail 9 "Replication appliance is ${replication_type} with a ${cache_size} GiB cache disk"
fi

quota_value="$(aws service-quotas get-service-quota --region "$region" \
  --service-code ec2 --quota-code L-1216C47A \
  --query 'Quota.Value' --output text 2>/dev/null || true)"
if [[ -n "$quota_value" && "$quota_value" != "None" ]]; then
  pass 10 "Standard quota L-1216C47A applied value is ${quota_value} (replication needs 10)"
else
  fail 10 "Standard quota L-1216C47A can be read"
fi

winrm_ok="$(printf '%s' "$group_json" | python3 -c '
import json, sys
groups = json.load(sys.stdin).get("SecurityGroups", [])
perms = groups[0].get("IpPermissions", []) if groups else []
extra = []
for perm in perms:
    if perm.get("IpProtocol") == "tcp" and perm.get("FromPort") == 5985 and perm.get("ToPort") == 5985:
        extra.extend(item.get("CidrIp", "") for item in perm.get("IpRanges", []) if item.get("CidrIp") != "10.0.1.0/24")
ok = len(extra) == 1 and extra[0].endswith("/32") and extra[0] != "0.0.0.0/0"
print("yes" if ok else "no")
')"
if [[ "$winrm_ok" == "yes" ]]; then
  pass 11 "Discovery WinRM allows one /32 besides the subnet"
else
  fail 11 "Discovery WinRM allows one /32 besides the subnet"
fi

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
