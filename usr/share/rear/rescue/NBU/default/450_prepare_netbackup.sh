# 450_prepare_netbackup.sh
# Make sure whichever NetBackup client network-daemon startup files exist
# on the source system get included in the rescue image, so they can be
# started in the rescue system, see verify/NBU/default/370_start_netbackup.sh:
# the PBX (vxpbx_exchanged) + NetBackup client systemd units or SysV
# /etc/init.d scripts, or the legacy pre-PBX xinetd config.
#
# Whether a given client ships a systemd unit, a SysV script, or the
# xinetd config depends on OS + NBU version together, not NBU version
# alone, so just copy whichever exists rather than gating on a version
# threshold - which one to prefer at start time is decided later, in
# verify/NBU/.

for f in /etc/systemd/system/vxpbx_exchanged.service /usr/lib/systemd/system/vxpbx_exchanged.service; do
	test -r "$f" && COPY_AS_IS+=( "$f" )
done
test -r "/etc/init.d/vxpbx_exchanged" && COPY_AS_IS+=( /etc/init.d/vxpbx_exchanged )

for f in /etc/systemd/system/netbackup.service /usr/lib/systemd/system/netbackup.service; do
	test -r "$f" && COPY_AS_IS+=( "$f" )
done
test -r "/etc/init.d/netbackup" && COPY_AS_IS+=( /etc/init.d/netbackup )

if test -r /etc/xinetd.d/vnetd -o -r /etc/xinetd.d/bpcd -o -r /etc/xinetd.d/vopied ; then
	PROGS+=( xinetd )
	COPY_AS_IS+=( /etc/xinetd.conf /etc/xinetd.d/bpcd /etc/xinetd.d/vnetd /etc/xinetd.d/vopied )
fi

# Correct permissions for the empty /usr/openv/var/... skeleton (skel/NBU ships everything
# at git's default 755 - it doesn't track directory modes):
chmod 0700 "$ROOTFS_DIR/usr/openv/var/credcache/0"
chmod 0700 "$ROOTFS_DIR/usr/openv/var/vnetd"
chmod 0700 "$ROOTFS_DIR/usr/openv/var/telemetry"
chmod 0710 "$ROOTFS_DIR/usr/openv/var/retry_resiliency"
chmod -R 0700 "$ROOTFS_DIR/usr/openv/var/vxss/at"
chmod 0700 "$ROOTFS_DIR/usr/openv/var/vxss/credentials/keystore"
