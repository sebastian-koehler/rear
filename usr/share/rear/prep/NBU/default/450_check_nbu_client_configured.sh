# this script has a simple goal: check if this client system has been properly
# defined on the NetBackup Primary Server and that a backup specification has been
# made for this client - no more no less

Log "Running: /usr/openv/netbackup/bin/bplist command"
local rc
LANG=C /usr/openv/netbackup/bin/bplist -l -s `date -d "-1 month" "+%m/%d/%Y"` / >/dev/null
rc=$?
[ $rc -gt 0 ] && LogPrint "WARNING: Netbackup bplist check failed with error code ${rc}.
See $RUNTIME_LOGFILE for more details."
