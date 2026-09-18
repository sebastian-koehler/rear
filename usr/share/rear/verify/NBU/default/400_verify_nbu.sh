# 400_verify_nbu.sh

# check that NetBackup Primary Server is actually available (ping)
[ "${NBU_SERVER}" ] || Error "NetBackup Primary Server not set in bp.conf (TCPSERVERADDRESS) !"

if test "$PING" ; then
	if ping -c 1 "${NBU_SERVER}" >/dev/null 2>&1; then
		Log "NetBackup Primary Server ${NBU_SERVER} seems to be up and running."
	else
		Error "Sorry, but cannot reach NetBackup Primary Server ${NBU_SERVER}"
	fi
else
	Log "Skipping ping test"
fi
