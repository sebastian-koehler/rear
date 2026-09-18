# 400_verify_nbu.sh

# check that NetBackup Primary Server is actually available
[ "${NBU_SERVER}" ] || Error "NetBackup Primary Server not set in bp.conf (TCPSERVERADDRESS) !"

local nbu_bpclntcmd=/usr/openv/netbackup/bin/bpclntcmd
local bpcln_output rc last_line

LogPrint ""
LogPrint "Verifying NetBackup Primary Server ${NBU_SERVER} via bpclntcmd..."

# confirms reachability AND that the remote is really a Primary/Master - fatal if not
bpcln_output=$( "$nbu_bpclntcmd" -is_master_server "${NBU_SERVER}" 2>&1 )
rc=$?
Log "bpclntcmd -is_master_server ${NBU_SERVER} raw output (rc=$rc):"
Log "$bpcln_output"
test $rc -eq 0 || Error "Sorry, but ${NBU_SERVER} is unreachable or not confirmed as a NetBackup Primary/Master server (bpclntcmd -is_master_server failed, rc=$rc)."
LogPrint "NetBackup Primary Server ${NBU_SERVER} confirmed reachable and is a Primary/Master server."

# NetBackup version on the Primary - informational only, never fatal
bpcln_output=$( "$nbu_bpclntcmd" -sv 2>&1 )
rc=$?
Log "bpclntcmd -sv raw output (rc=$rc):"
Log "$bpcln_output"
if test $rc -eq 0 ; then
	last_line=$( echo "$bpcln_output" | grep -v '^[[:space:]]*$' | tail -n 1 )
	LogPrint "NetBackup version on Primary Server ${NBU_SERVER}: $last_line"
else
	LogPrintError "Could not determine the NetBackup version on Primary Server ${NBU_SERVER} (bpclntcmd -sv failed, rc=$rc, non-fatal)."
fi

# local NetBackup client's own version - informational only, never fatal
bpcln_output=$( "$nbu_bpclntcmd" -get_local_client_patch_version 2>&1 )
rc=$?
Log "bpclntcmd -get_local_client_patch_version raw output (rc=$rc):"
Log "$bpcln_output"
if test $rc -eq 0 ; then
	last_line=$( echo "$bpcln_output" | grep -v '^[[:space:]]*$' | tail -n 1 )
	LogPrint "Local NetBackup client version: $last_line"
else
	LogPrintError "Could not determine the local NetBackup client version (bpclntcmd -get_local_client_patch_version failed, rc=$rc, non-fatal)."
fi
