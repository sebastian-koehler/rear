# 400_verify_nbu.sh

# check that NetBackup Primary Server is actually available
[ "${NBU_SERVER}" ] || Error "NetBackup Primary Server not set in bp.conf (TCPSERVERADDRESS) !"

local nbu_bpclntcmd=/usr/openv/netbackup/bin/bpclntcmd
local bpcln_output rc primary_version local_version

LogPrint ""
LogPrint "Verifying NetBackup Primary server ${NBU_SERVER} via bpclntcmd..."

# confirms reachability AND that the remote is really a Primary/Master - fatal if not
bpcln_output=$( "$nbu_bpclntcmd" -is_master_server "${NBU_SERVER}" 2>&1 )
rc=$?
Log "bpclntcmd -is_master_server ${NBU_SERVER} raw output (rc=$rc):"
Log "$bpcln_output"
test $rc -eq 0 || Error "Sorry, but ${NBU_SERVER} is unreachable or not confirmed as a NetBackup Primary/Master server (bpclntcmd -is_master_server failed, rc=$rc)."
LogPrint "Connectivity and server role confirmed."

# NetBackup version on the Primary - informational only, never fatal
bpcln_output=$( "$nbu_bpclntcmd" -sv 2>&1 )
rc=$?
Log "bpclntcmd -sv raw output (rc=$rc):"
Log "$bpcln_output"
if test $rc -eq 0 ; then
	primary_version=$( echo "$bpcln_output" | grep -v '^[[:space:]]*$' | tail -n 1 )
else
	primary_version="unknown"
	LogPrintError "Could not determine the NetBackup version on Primary Server ${NBU_SERVER} (bpclntcmd -sv failed, rc=$rc, non-fatal)."
fi

# local NetBackup client's own version - informational only, never fatal
bpcln_output=$( "$nbu_bpclntcmd" -get_local_client_patch_version 2>&1 )
rc=$?
Log "bpclntcmd -get_local_client_patch_version raw output (rc=$rc):"
Log "$bpcln_output"
if test $rc -eq 0 ; then
	local_version=$( echo "$bpcln_output" | grep -v '^[[:space:]]*$' | tail -n 1 )
else
	local_version="unknown"
	LogPrintError "Could not determine the local NetBackup client version (bpclntcmd -get_local_client_patch_version failed, rc=$rc, non-fatal)."
fi

LogPrint "Primary server is running NetBackup ${primary_version} and the local client is NetBackup ${local_version}."
