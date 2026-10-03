# 500_request_pit_restore_parameters.sh

# Ask for NetBackup Point-In-Time Restore.
# One point in time is used for all filesystems.
# This causes the bprecover to use the input date or date/time to be used as the endtime -e option
# see the usr/share/rear/restore/NBU/default/400_restore_with_nbu.sh script.

NBU_ENDTIME=()

local answer="" valid_date_and_time_input="" nbu_endtime_date="" nbu_endtime_time=""
local nbu_catalog_output="" nbu_catalog_rc=0 nbu_catalog_line=""
local nbu_catalog_header_line="" nbu_catalog_index=0 nbu_catalog_number="" nbu_catalog_tir_flag=""
local nbu_tir_status=""
local nbu_bpclimagelist=/usr/openv/netbackup/bin/bpclimagelist
local nbu_tir_enabled="yes"
local nbu_catalog_lines=() nbu_catalog_dates=() nbu_catalog_times=() nbu_catalog_header=()

# Show what NetBackup actually has in its catalog for the restore source
# client, so the operator can pick a backup instead of typing a date/time
# from memory. 'bpclimagelist' has no policy-type filter matching 'bprestore's
# hardcoded "-t 0" (Standard) restore type. Its own "-t" is the backup TYPE
# (FULL/INCR/CINC/...), not the policy type, so this deliberately lists all
# of the client's images rather than pass a filter that isn't equivalent.
# -Listseconds is required for enough precision to tell same-day backups
# apart, since that is exactly what "bprestore -e" needs to disambiguate them.
# -T lists only backups with True Image Restore info, so the
# picker only offers backups that can be correctly Point-In-Time restored.
#
# Resolve NBU_TRUE_IMAGE_RESTORE's tri-state (is_true/is_false: unset/empty
# is neither) to one definite yes/no once, used below both for this -T flag
# and for the closing summary message. Testing the same variable twice
# with opposite-polarity helpers let the flag and the message disagree
# whenever the variable was unset (ships set to "true" in conf/default.conf,
# so this was latent, not visible in practice).
is_false "$NBU_TRUE_IMAGE_RESTORE" && nbu_tir_enabled="no"
test "$nbu_tir_enabled" = "yes" && nbu_catalog_tir_flag="-T"
LogPrint ""
while true ; do
    LogPrint "Querying the NetBackup catalog for $NBU_CLIENT_SOURCE's backups..."
    nbu_catalog_output=$( "$nbu_bpclimagelist" -Listseconds -client "$NBU_CLIENT_SOURCE" $nbu_catalog_tir_flag 2>&1 )
    nbu_catalog_rc=$?
    test $nbu_catalog_rc -eq 135 || break
    # EXIT STATUS 135: the source client is not yet authorized as an altname
    # of the destination on the Primary server. Give the operator a chance
    # to fix that and retry, instead of failing the whole restore outright.
    LogPrint ""
    LogPrintError "'bpclimagelist' failed: $NBU_CLIENT_SOURCE is not authorized as an altname"
    LogPrintError "of $NBU_CLIENT_NAME on the Primary server $NBU_SERVER."
    LogPrint ""
    LogPrint "Retry after changing the altname configuration on the Primary server."
    read -t $WAIT_SECS -r -p "Press ENTER to retry, or enter EXIT to abort [$WAIT_SECS secs]: " 0<&6 1>&7 2>&8
    if [[ "${REPLY^^}" == "EXIT" ]] ; then
        LogPrint ""
        Error "User aborted NetBackup restore to configure the altname authorization on the Primary server, update bp.conf or pick a different client name above."
    fi
done

if [ $nbu_catalog_rc -eq 0 ] ; then
    # Match only actual data rows (leading "mm/dd/yyyy HH:MM:SS"), which skips
    # the header and dashed separator line regardless of later column widths.
    # Keep whatever precedes the first data row (the column header and its
    # dashed underline) so the trailing columns (Files/KB/Policy/...) remain
    # readable once each data row gets a "N) " selection number prefixed:
    while read -r nbu_catalog_line ; do
        if [[ "$nbu_catalog_line" =~ ^([0-9]{2}/[0-9]{2}/[0-9]{4})[[:space:]]+([0-9]{2}:[0-9]{2}:[0-9]{2}) ]] ; then
            nbu_catalog_lines+=( "$nbu_catalog_line" )
            nbu_catalog_dates+=( "${BASH_REMATCH[1]}" )
            nbu_catalog_times+=( "${BASH_REMATCH[2]}" )
        elif test ${#nbu_catalog_lines[@]} -eq 0 ; then
            nbu_catalog_header+=( "$nbu_catalog_line" )
        fi
    done <<< "$nbu_catalog_output"
fi

if [ ${#nbu_catalog_lines[@]} -gt 0 ] ; then
    UserOutput ""
    UserOutput "Available backups for $NBU_CLIENT_SOURCE in the NetBackup catalog (newest first):"
    UserOutput ""
    # Indented to roughly line up under the "N) " prefix of the data rows below:
    for nbu_catalog_header_line in "${nbu_catalog_header[@]}" ; do
        UserOutput "     ${nbu_catalog_header_line}"
    done
    for (( nbu_catalog_index = 0 ; nbu_catalog_index < ${#nbu_catalog_lines[@]} ; nbu_catalog_index++ )) ; do
        nbu_catalog_number=$( printf '%3d' $(( nbu_catalog_index + 1 )) )
        UserOutput "${nbu_catalog_number}) ${nbu_catalog_lines[nbu_catalog_index]}"
    done
    UserOutput ""
    UserOutput "NetBackup restores by default the latest backup data."
    UserOutput "Press only ENTER to restore the most recent available backup"
    UserOutput "or enter a number above to restore that Point-In-Time backup."
else
    if [ $nbu_catalog_rc -ne 0 ] ; then
        Error "Could not query the NetBackup catalog for $NBU_CLIENT_SOURCE ('bpclimagelist' rc=$nbu_catalog_rc)."
    fi
    LogPrintError "The NetBackup catalog query for $NBU_CLIENT_SOURCE returned no matching backups ('bpclimagelist' rc=0)."
    UserOutput ""
    UserOutput "NetBackup restores by default the latest backup data."
    UserOutput "Press only ENTER to restore the most recent available backup."
    UserOutput "Falling back to manual date/time entry."
    UserOutput "Alternatively specify a date and time for Point-In-Time Restore."
fi

# Let the user enter a catalog number or a date and time again and again
# until the input is valid, or the user pressed only ENTER to restore the
# most recent available backup:
while true ; do
    answer=$( UserInput -I NBU_RESTORE_PIT -r -p "Enter a catalog number or date and time (mm/dd/yyyy HH:MM:SS), or press ENTER" )
    # When the user pressed only ENTER, default to the newest backup
    # (catalog entry 1, newest first), unless there is no catalog to pick
    # from at all, in which case leave this script to restore the most
    # recent available backup:
    if test -z "$answer" ; then
        if [ ${#nbu_catalog_lines[@]} -eq 0 ] ; then
            UserOutput "Restore most recent backup."
            return
        fi
        answer="1"
    fi
    # A number picks straight from the catalog list shown above, already valid, no need to re-validate:
    if [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -ge 1 ] && [ "$answer" -le ${#nbu_catalog_lines[@]} ] ; then
        nbu_endtime_date="${nbu_catalog_dates[$(( answer - 1 ))]}"
        nbu_endtime_time="${nbu_catalog_times[$(( answer - 1 ))]}"
        break
    fi
    # Otherwise only accept the exact documented format. Reject anything else
    # (e.g. "yesterday", "next monday", or a bare date with no time) that
    # `date -d` would otherwise loosely accept:
    if [[ ! "$answer" =~ ^[0-9]{2}/[0-9]{2}/[0-9]{4}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] ; then
        LogPrintError "Invalid catalog number or date/time '$answer' specified."
        continue
    fi
    # Try to do NetBackup Point-In-Time Restore provided the user input is a valid calendar date and time:
    valid_date_and_time_input="yes"
    # Validate date:
    nbu_endtime_date=$( date -d "$answer" +%m/%d/%Y ) || valid_date_and_time_input="no"
    # Validate time:
    nbu_endtime_time=$( date -d "$answer" +%T ) || valid_date_and_time_input="no"
    # Exit the while loop when the user input is valid date and time:
    is_true "$valid_date_and_time_input" && break
    # Show the user that his input is invalid and do the the while loop again:
    LogPrintError "Invalid catalog number or date/time '$answer' specified."
done

# Do NetBackup Point-In-Time Restore:
NBU_ENDTIME=( "$nbu_endtime_date" )
# When also an actual time was specified (i.e. when it is not "00:00:00") add it:
test "$nbu_endtime_time" != "00:00:00" && NBU_ENDTIME+=( "$nbu_endtime_time" )

nbu_tir_status="disabled"
test "$nbu_tir_enabled" = "yes" && nbu_tir_status="enabled"

UserOutput ""
UserOutput "Perform NetBackup filesystem restore of all backups at or before ${NBU_ENDTIME[@]} with True Image Restore (TIR) $nbu_tir_status."
UserOutput ""
