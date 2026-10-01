# 400_restore_with_nbu.sh

# restore files with NBU

# Populate files bprestore will use. No need to handle mount points individually.
echo "change / to $TARGET_FS_ROOT" > $TMP_DIR/nbu_change_file || Error "Cannot write $TMP_DIR/nbu_change_file."
echo "/" > $TMP_DIR/restore_fs_list || Error "Cannot write $TMP_DIR/restore_fs_list."

local edate sdate bprestore_args rc
local nbu_chain_line nbu_chain_date nbu_chain_time nbu_chain_epoch nbu_target_epoch
local nbu_tir_flag=""
local nbu_tir_status=""
local nbu_bpclimagelist=/usr/openv/netbackup/bin/bpclimagelist
local nbu_bprestore=/usr/openv/netbackup/bin/bprestore

# bpclimagelist -T lists only backups with True Image
# Restore info, and bprestore -T actually restores using that TIR info
# (correctly excluding files/folders deleted or renamed between backups).
# bprestore ignores -s when -T is also given (bprestore(1)).
# Same is_false polarity as verify/NBU/default/500_request_pit_restore_parameters.sh's
# nbu_catalog_tir_flag decision (kept deliberately independent, not shared,
# since this runs in a later rear stage). If that script's TIR polarity
# handling is ever changed, re-check this one stays in sync with it.
is_false "$NBU_TRUE_IMAGE_RESTORE" || nbu_tir_flag="-T"

# Do not use ARGS here because that is readonly in the rear main script.
# NBU_ENDTIME is only unset if the catalog was unavailable when asked
# (verify/NBU/default/430_...). There is nothing legitimate to restore
# from in that case, so stop here rather than making up a date.
test ${#NBU_ENDTIME[@]} -gt 0 || Error "No NetBackup catalog entry available to restore from, cannot do NetBackup Point-In-Time Restore."
edate="${NBU_ENDTIME[@]}"

# bprestore with only -e defaults -s to 01/01/1970 (bprestore(1)), which
# would replay every backup image ever taken up to $edate instead of just
# the chain needed to reconstruct that point in time. Walk the catalog
# newest-first (bounded by -e) and stop at the nearest full backup.
# That's both the correct -s and the restore chain to show the user.
nbu_target_epoch=$( date -d "$edate" '+%s' ) || Error "Cannot parse selected restore point in time '$edate'."
# A bare "mm/dd/yyyy" with no time is NOT midnight to bpclimagelist/bprestore
# (it behaves like end-of-day) even though `date -d` treats it as midnight.
# Normalize edate to always carry an explicit HH:MM:SS from here on, so a
# midnight-timed pick (NBU_ENDTIME drops the time when it's "00:00:00") can
# never silently widen the restore window to include a later same-day image.
edate=$( date -d "@$nbu_target_epoch" '+%m/%d/%Y %H:%M:%S' )
sdate=""
# $edate is deliberately left unquoted below (and again in bprestore_args
# further down): it carries "MM/DD/YYYY HH:MM:SS" as one string, and
# bpclimagelist/bprestore's -e wants that as two separate arguments (date,
# then time). Word-splitting it is what makes that happen. Quoting
# "$edate" would collapse it back into one argument and break both calls.
while read -r nbu_chain_line ; do
    [[ "$nbu_chain_line" =~ ^([0-9]{2}/[0-9]{2}/[0-9]{4})[[:space:]]+([0-9]{2}:[0-9]{2}:[0-9]{2}) ]] || continue
    nbu_chain_date="${BASH_REMATCH[1]}"
    nbu_chain_time="${BASH_REMATCH[2]}"
    nbu_chain_epoch=$( date -d "$nbu_chain_date $nbu_chain_time" '+%s' ) || continue
    test "$nbu_chain_epoch" -le "$nbu_target_epoch" || continue
    if [[ "$nbu_chain_line" == *"Full Backup"* ]] ; then
        sdate="$nbu_chain_date $nbu_chain_time"
        break
    fi
done < <( "$nbu_bpclimagelist" -Listseconds -client "${NBU_CLIENT_SOURCE}" -t NOT_ARCHIVE -e ${edate} $nbu_tir_flag 2>/dev/null )
test -n "$sdate" || Error "No full NetBackup backup found at or before '$edate' for client ${NBU_CLIENT_SOURCE}, cannot do Point-In-Time Restore."

bprestore_args="-B -H -L $TMP_DIR/bplog.restore -R $TMP_DIR/nbu_change_file -t 0 -w 0 -s ${sdate} -e ${edate} -C ${NBU_CLIENT_SOURCE} -D ${NBU_CLIENT_NAME} -f $TMP_DIR/restore_fs_list $nbu_tir_flag"

nbu_tir_status="disabled"
test "$nbu_tir_flag" = "-T" && nbu_tir_status="enabled"

UserOutput ""
UserOutput "NetBackup restore of $NBU_CLIENT_SOURCE filesystem into $TARGET_FS_ROOT with True Image Restore (TIR) $nbu_tir_status:"
LogPrint "$nbu_bprestore $bprestore_args"
"$nbu_bprestore" $bprestore_args
rc=$?
# According to issue #3560 return codes up to 5 are restores with issues,
# but not complete failures.
case $rc in
    (0)
        LogPrint "bprestore completed successfully (return code = 0)."
        ;;
    (1|2|3|4|5)
        LogPrintError "bprestore completed with issues (return code = $rc), see $TMP_DIR/bplog.restore."
        LogPrintError "Carefully verify the restored system before relying on it to be fully operational."
        ;;
    (*)
        Error "bprestore failed (return code = $rc), the restored system likely lacks the data needed to become operational."
        ;;
esac

