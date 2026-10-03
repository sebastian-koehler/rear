# 450_request_client_source.sh

# Which NetBackup client's backup to restore FROM (source). There is no
# separate "destination" question here: the destination is always
# whatever CLIENT_NAME currently is in bp.conf, already fixed (either
# unchanged, or auto-renamed by 250_check_nbu_client_name.sh). The
# running NetBackup client daemon and its enrolled certificate only match
# that one identity, so there is no valid way to restore "as" a different
# destination client at this point.
#
# Whether this restore turns out to be a cross restore (source !=
# destination) is only known once this question has been asked. If the
# source client isn't authorized as an altname of the destination on the
# Primary server, 'bpclimagelist' fails with EXIT STATUS 135 in
# 500_request_pit_restore_parameters.sh, which pauses there to let the
# operator fix it and retry.

# Default: no implicit cross restore. Only an explicit answer below changes this.
NBU_CLIENT_SOURCE="$NBU_CLIENT_NAME"
test -n "$NBU_CLIENT_SOURCE" || Error "NBU_CLIENT_NAME is not set. Cannot determine a NetBackup source client to restore from. This likely means CLIENT_NAME was removed from bp.conf during the 250_check_nbu_client_name.sh pause."

LogPrint ""
if is_true "$NBU_CLIENT_RENAMED" ; then
	LogPrint "This client's hostname was changed from $NBU_CLIENT_ORIGINAL to $NBU_CLIENT_NAME prior to this restore."
fi
LogPrint "NetBackup source client for this restore: $NBU_CLIENT_SOURCE."
read -t $WAIT_SECS -r -p "Enter source client name to restore from or press ENTER [$WAIT_SECS secs]: " 0<&6 1>&7 2>&8
if test -n "${REPLY}" ; then
	NBU_CLIENT_SOURCE="${REPLY}"
	LogPrint ""
	LogPrint "Restoring from a DIFFERENT NetBackup client: $NBU_CLIENT_SOURCE (instead of $NBU_CLIENT_NAME)."
	LogPrint "Warning: 'bprestore' needs the source client authorized as an altname"
	LogPrint "of the destination on the Primary server, or it will fail."
fi
