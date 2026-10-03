# 450_check_nbu_client_configured.sh

# this script has a simple goal: check if this client system has been properly
# defined on the NetBackup Primary Server and that a backup specification has been
# made for this client, no more no less

# Check whether this client is actually a NetBackup Primary or Media server
# (CLIENT_NAME matches a SERVER or MEDIA_SERVER entry in its own bp.conf).
# Restoring such a server via rear can't work in a real DR since NetBackup
# services must already be running to run 'bprestore'. Flag this at backup
# time so the operator finds out long before a disaster, not during one.
local nbu_bpconf=/usr/openv/netbackup/bp.conf
test -r "$nbu_bpconf" || Error "Cannot read $nbu_bpconf."
local nbu_client_name nbu_server_media_list nbu_server_client_msg
nbu_client_name=$( grep -i '^[[:space:]]*CLIENT_NAME[[:space:]]*=' "$nbu_bpconf" | head -1 | sed -e 's/^[^=]*=[[:space:]]*//' -e 's/[[:space:]]*$//' )
nbu_server_media_list=$( grep -iE '^[[:space:]]*(SERVER|MEDIA_SERVER)[[:space:]]*=' "$nbu_bpconf" | sed -e 's/^[^=]*=[[:space:]]*//' -e 's/[[:space:]]*$//' )
if test -n "$nbu_client_name" && echo "$nbu_server_media_list" | tr '[:upper:]' '[:lower:]' | grep -qFx "$( echo "$nbu_client_name" | tr '[:upper:]' '[:lower:]' )" ; then
	nbu_server_client_msg="This client is a NetBackup Primary/Media server. A SERVER or
MEDIA_SERVER entry in bp.conf matches CLIENT_NAME ($nbu_client_name).

Restoring may not work since NetBackup services must be up and running to
run 'bprestore'. During restore time, when running 'rear recover' you will
need to point to another Primary server holding a replicated (or duplicated)
copy of this client's image. If you understand these implications set
NBU_ALLOW_SERVER_AS_CLIENT=true in local.conf/site.conf to continue."
	if is_true "$NBU_ALLOW_SERVER_AS_CLIENT" ; then
		LogPrintError "WARNING: $nbu_server_client_msg"
	else
		Error "$nbu_server_client_msg"
	fi
fi

local nbu_bplist=/usr/openv/netbackup/bin/bplist
test -x "$nbu_bplist" || Error "Cannot execute $nbu_bplist."

local rc nbu_bplist_since nbu_bplist_tir_flag=""
nbu_bplist_since=$( date -d "-1 month" "+%m/%d/%Y" )

# "bplist -T" lists only backups with True Image Restore info. It exits 227
# if the catalog has none in the queried window. -T is just a filter on
# the same underlying query as a plain reachability/backup-exists check,
# so fold it into one 'bplist' call instead of two (same conditional -T flag
# idiom as restore/NBU/default/400_restore_with_nbu.sh and
# verify/NBU/default/500_request_pit_restore_parameters.sh).
# Without TIR, a Point-In-Time restore of a full+incremental chain has no
# record of per-backup deletions, so files removed after the full but
# before the picked incremental get incorrectly restored ('bprestore' just
# unions every file in the window).
is_false "$NBU_TRUE_IMAGE_RESTORE" || nbu_bplist_tir_flag="-T"

Log "Running: $nbu_bplist $nbu_bplist_tir_flag -s $nbu_bplist_since /"
"$nbu_bplist" $nbu_bplist_tir_flag -s "$nbu_bplist_since" / >/dev/null 2>&1
rc=$?
if [ -n "$nbu_bplist_tir_flag" ] && [ $rc -eq 227 ] ; then
	if is_true "$NBU_TRUE_IMAGE_RESTORE" ; then
		Error "No backups with TIR information in the NetBackup catalog for this client.
Files deleted after a full backup but before a later incremental would be
incorrectly restored during a Point-In-Time restore. Enable 'Collect true
image restore information' (with move detection) in the Attributes tab of
the policy that backs up this client, or set NBU_TRUE_IMAGE_RESTORE=false
in local.conf/site.conf to back up anyway."
	else
		LogPrint "WARNING: No backups with TIR information in the NetBackup catalog for this client.
(NBU_TRUE_IMAGE_RESTORE=false, continuing anyway). Files deleted after a
full backup but before a later incremental will be incorrectly restored
during a Point-In-Time restore."
	fi
elif [ $rc -gt 0 ] ; then
	Error "Netbackup 'bplist' check failed with error code ${rc}.
This client must be able to communicate with the NetBackup Primary server
and have at least one valid backup in the catalog within the last month.
See $RUNTIME_LOGFILE for more details."
else
	Log "Found backups in the NetBackup catalog for this client."
fi
