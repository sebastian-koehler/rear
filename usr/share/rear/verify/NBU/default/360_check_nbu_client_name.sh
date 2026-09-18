# 360_check_nbu_client_name.sh
# Detect whether the rescue system's live hostname differs from the
# original backed-up client's CLIENT_NAME in bp.conf. The user renamed
# the rescue system before running 'rear recover', to restore under a
# temporary hostname/IP instead of the original one.
# If a rename is detected, update CLIENT_NAME in bp.conf to match, while
# keeping NBU_CLIENT_SOURCE as the ORIGINAL name (needed to select the
# right backup images in verify/NBU/default/380_request_client_destination.sh
# and restore/NBU/default/400_restore_with_nbu.sh).
#
# Runs BEFORE 370_start_netbackup.sh deliberately: the NetBackup client
# daemon reads CLIENT_NAME from bp.conf at startup, so the name must be
# confirmed/corrected here first. Starting it before this check could
# start it under the wrong (original) hostname.

local nbu_bpconf=/usr/openv/netbackup/bp.conf

local bp_conf_client_name current_hostname
bp_conf_client_name=$( grep -i '^[[:space:]]*CLIENT_NAME' "$nbu_bpconf" | head -1 | sed -e 's/^[^=]*=[[:space:]]*//' -e 's/[[:space:]]*$//' ) || true
current_hostname=$( hostname -f 2>/dev/null || hostname ) || Error "Failed to determine current hostname"

# Remember the ORIGINAL client name before any patching below:
NBU_CLIENT_SOURCE="$bp_conf_client_name"

LogPrint ""
LogPrint "Original client name in bp.conf:"
LogPrint "${bp_conf_client_name:-<unknown>}"
LogPrint ""
LogPrint "Current hostname:"
LogPrint "$current_hostname"
LogPrint ""

if test -n "$bp_conf_client_name" \
	&& test "$( echo "$bp_conf_client_name" | tr '[:upper:]' '[:lower:]' )" != "$( echo "$current_hostname" | tr '[:upper:]' '[:lower:]' )" ; then
	LogPrint "Detected: hostname differs from the original client name in bp.conf - restoring to a renamed/temporary client."
	sed -i "s/^\([[:space:]]*CLIENT_NAME[[:space:]]*=\).*/\1 $current_hostname/" "$nbu_bpconf" || Error "Unable to update CLIENT_NAME in $nbu_bpconf"
	LogPrint "Updated CLIENT_NAME in $nbu_bpconf to $current_hostname."
	NBU_CLIENT_RENAMED="yes"
else
	LogPrint "Detected: hostname matches the original client name in bp.conf."
	NBU_CLIENT_RENAMED="no"
fi
