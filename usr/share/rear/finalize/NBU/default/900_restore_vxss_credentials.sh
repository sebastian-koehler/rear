# 900_restore_vxss_credentials.sh

# Purpose:
# /usr/openv/var/vxss (host certificate/keystore) and /usr/openv/var/webtruststore
# (primary's CA certificate) are excluded from backup (see COPY_AS_IS_EXCLUDE_NBU
# in conf/default.conf). NetBackup's own backup engine also implicitly skips
# them. Neither is ever present on the restored disk. Without
# webtruststore/cacert.pem specifically, the recovered client can't even
# initialize an outbound SSL context to the primary ("bpclntcmd -check_vxss"
# fails with "the vnetd proxy encountered an error", 'vnetd'/'bpclntcmd' logs
# show "load_trust_store" / "Path to trust store is not accessible", errno 2)
# regardless of the host cert being fine.
# verify/NBU/default/350_start_netbackup.sh already fetched the primary's CA
# certificate and enrolled a fresh host certificate into THIS rescue
# environment's own /usr/openv/var/vxss and /usr/openv/var/webtruststore.
# Copy both onto the recovered system now so the NetBackup client remains
# operational after reboot, without requiring another manual token
# enrollment. Mirrors finalize/DP/default/500_restore_ssc.sh's approach for
# the DP backend.
#
# Also copy /usr/openv/var/credcache the same way. It's excluded from
# backup too for the same reason: it only ever holds a live unix socket and
# short-lived JWTs, /usr/openv/var/credcache/0/cred_cache0), and NetBackup
# only lazily creates its numbered subdirectory at runtime, not the
# top-level directory itself, so a restore that never had this top-level
# directory to begin with leaves vnetd unable to create it (mkdir fails
# with ENOENT), which also surfaces as "bpclntcmd -check_vxss" failing
# (vnetd log: "create_credcache_userdir: Directory creation failed with
# errno 2"). The socket special file itself doesn't carry over as a live
# listener, but 'cp -a' recreates it as a socket node fine, and vnetd
# unlinks/rebinds it on the next start anyway.
#
# Runs for the 'bprestore'-driven restore. It already went through client
# identity/cert enrollment in the verify stage and needs a working
# certificate afterwards.
#
# Skipped on a true cross restore (NBU_CLIENT_SOURCE != NBU_CLIENT_NAME,
# same check as verify/NBU/default/450_request_client_source.sh): the
# cert enrolled in the verify stage is for THIS system's own identity
# (NBU_CLIENT_NAME), not the source client whose data was just restored,
# so it would be useless (and misleading) on the recovered disk.

if test -n "$NBU_CLIENT_SOURCE" \
	&& test "$( echo "$NBU_CLIENT_SOURCE" | tr '[:upper:]' '[:lower:]' )" != "$( echo "$NBU_CLIENT_NAME" | tr '[:upper:]' '[:lower:]' )" ; then
	LogPrint "This was a cross restore ($NBU_CLIENT_SOURCE's backup onto $NBU_CLIENT_NAME)."
	LogPrint "Skipping vxss/webtruststore/credcache copy. The material enrolled belongs to $NBU_CLIENT_NAME, not $NBU_CLIENT_SOURCE."
        LogPrint "The NetBackup client on the recovered system may need to be re-enrolled manually."
	return
fi

# Directory pairs to mirror from this rescue system onto the recovered disk,
# plus the one file inside each whose presence proves the copy is actually
# useful (not just an empty/partial directory):
local nbu_security_dirs=( /usr/openv/var/vxss /usr/openv/var/webtruststore /usr/openv/var/credcache )
local nbu_security_dirs_proof=( credentials cacert.pem 0 )

local i nbu_dir nbu_target_dir proof cp_rc
for (( i = 0; i < ${#nbu_security_dirs[@]}; i++ )) ; do
    nbu_dir="${nbu_security_dirs[$i]}"
    proof="${nbu_security_dirs_proof[$i]}"
    nbu_target_dir="$TARGET_FS_ROOT$nbu_dir"

    if ! test -d "$nbu_dir" ; then
        LogPrint "No $nbu_dir on this rescue system. Nothing to restore."
        continue
    fi

    LogPrint "Restoring NetBackup client credentials from $nbu_dir into $nbu_target_dir ..."

    # Make sure the target directory exists without wiping any content
    # a prior restore stage may already have placed there:
    mkdir -p "$nbu_target_dir"

    # Copy directory contents (trailing '/.', not a glob, so no quoting
    # pitfalls, and no risk of nesting $nbu_dir's basename inside an
    # already-existing $nbu_target_dir) into the existing target
    # directory, merging rather than replacing it, same idiom as
    # finalize/default/110_bind_mount_proc_sys_dev_run.sh uses for /dev.
    # '-a' preserves mode/ownership/timestamps.
    # Do not error out at this late state of "rear recover" but inform the user:
    cp -a $v "$nbu_dir"/. "$nbu_target_dir"/
    cp_rc=$?
    test $cp_rc -eq 0 || LogPrintError "Failed to copy $nbu_dir content to $nbu_target_dir (cp exit code $cp_rc)."

    # Verify both that the target directory's content (pre-existing plus
    # newly copied) is intact, and specifically that the actual credential
    # material landed, the thing NetBackup actually needs on next start:
    if test $cp_rc -eq 0 \
        && test -n "$( ls -A "$nbu_target_dir" 2>/dev/null )" \
        && test -n "$( ls -A "$nbu_target_dir/$proof" 2>/dev/null )" ; then
        LogPrint "NetBackup client credentials restored from $nbu_dir."
    else
        LogPrintError "NetBackup client credentials from $nbu_dir were not restored."
        LogPrintError "The NetBackup client on the recovered system may need to be re-enrolled manually."
    fi
done
