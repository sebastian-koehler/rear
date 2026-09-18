# 370_start_netbackup.sh
# Start PBX/NetBackup client daemons (systemd, then SysV, then xinetd
# fallback for pre-PBX clients), then enroll/reissue this rescue system's
# host certificate with the primary via nbcertcmd. Since NetBackup will not
# include the original cert in the backup Rear will also not carry it onto
# the ISO, so a fresh token-based enrollment is used instead.
#
# Runs after 360_check_nbu_client_name.sh: bp.conf's CLIENT_NAME must be
# confirmed/renamed before the client daemon starts and reads it.

# check the unit file on disk, not list-unit-files' exit code (always 0 on systemd 219/RHEL7)
if has_binary systemctl \
	&& { test -e /etc/systemd/system/vxpbx_exchanged.service || test -e /usr/lib/systemd/system/vxpbx_exchanged.service ; } ; then
	systemctl daemon-reload
	systemctl start vxpbx_exchanged.service || Error "Unable to start vxpbx_exchanged via systemd"
	if test -e /etc/systemd/system/netbackup.service -o -e /usr/lib/systemd/system/netbackup.service ; then
		systemctl start netbackup.service || Error "Unable to start the NetBackup client via systemd"
	fi
elif test -x /etc/init.d/vxpbx_exchanged ; then
	/etc/init.d/vxpbx_exchanged start || Error "Unable to start vxpbx_exchanged via /etc/init.d/vxpbx_exchanged"
	if test -x /etc/init.d/netbackup ; then
		/etc/init.d/netbackup start || Error "Unable to start the NetBackup client via /etc/init.d/netbackup"
	fi
elif test -r /etc/xinetd.d/vnetd -o -r /etc/xinetd.d/bpcd -o -r /etc/xinetd.d/vopied ; then
	xinetd || Error "Unable to start xinetd"
	test -f /etc/xinetd.d/vnetd || /usr/openv/netbackup/bin/vnetd -standalone
	test -f /etc/xinetd.d/bpcd || /usr/openv/netbackup/bin/bpcd -standalone
else
	LogPrint "WARNING: no NetBackup startup mechanism (systemd/SysV/xinetd) found in the rescue system"
fi

LogPrint "NetBackup services started."

local nbu_primary current_hostname token cert_output rc

nbu_primary=$( grep -i '^[[:space:]]*SERVER' /usr/openv/netbackup/bp.conf | head -1 | sed -e 's/^[^=]*=[[:space:]]*//' -e 's/[[:space:]]*$//' ) || true
test -n "$nbu_primary" || Error "Could not determine the NetBackup primary server from bp.conf (SERVER=)"

LogPrint ""
LogPrint "Fetching the NetBackup CA certificate from $nbu_primary ..."
LogPrint "You will be asked to confirm the CA certificate's fingerprint of the NetBackup Primary server."
/usr/openv/netbackup/bin/nbcertcmd -getCAcertificate -server "$nbu_primary" 0<&6 1>&7 2>&8 || Error "Unable to fetch the NetBackup CA certificate from $nbu_primary"

current_hostname=$( hostname -f 2>/dev/null || hostname ) || Error "Failed to determine current hostname"

LogPrint ""
if is_true "$NBU_CLIENT_RENAMED" ; then
	LogPrint "The system name of this client was changed prior running rear recover to $current_hostname."
else
	LogPrint "This client is being restored under its original system name, $current_hostname."
fi
LogPrint "A host certificate may or may not exist on Primary server $nbu_primary."
LogPrint "Provide an authorization or reissue token for this client. The token can be created using the"
LogPrint "NetBackup WebUI or nbcertcmd -createtoken command on the Primary server."
LogPrint ""

# no timeout: getting a token from the WebUI can take a while. loop until a valid
# token or 'exit' (the escape hatch).
while true ; do
	token=$( UserInput -I NBU_CERT_TOKEN -r -t 0 -p "Enter NetBackup enrollment token:" ) || true
	if test "$( echo "$token" | tr '[:upper:]' '[:lower:]' )" = "exit" ; then
		Error "NetBackup certificate enrollment cancelled by user."
	fi
	if test -z "$token" ; then
		LogPrintError "A token is required - cannot restore without a trusted host certificate. Enter a token, or 'exit' to cancel."
		continue
	fi
	cert_output=$( /usr/openv/netbackup/bin/nbcertcmd -getCertificate -server "$nbu_primary" -token "$token" -force 2>&1 )
	rc=$?
	LogPrint "$cert_output"
	test $rc -eq 0 && break
	if echo "$cert_output" | grep -qi "Reissue token is mandatory" ; then
		LogPrintError ""
		LogPrintError "A certificate already exists for this client on $nbu_primary. Provide a reissue"
		LogPrintError "token for this client using the NetBackup WebUI, or 'exit' to cancel."
	else
		LogPrintError "Certificate enrollment failed (see output above) - check the token and try again, or 'exit' to cancel."
	fi
done

LogPrint "NetBackup host certificate enrolled successfully."
