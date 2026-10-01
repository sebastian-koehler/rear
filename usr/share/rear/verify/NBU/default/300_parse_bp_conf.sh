# 300_parse_bp_conf.sh

# Parse /usr/openv/netbackup/bp.conf into NBU_* variables (NBU_SERVER,
# NBU_CLIENT_NAME, and any other bp.conf key as NBU_KEY). Runs
# unconditionally, regardless of the GUI/scripted restore choice, since both
# 350_start_netbackup.sh and 400_verify_nbu.sh need NBU_SERVER.
#
# Runs after 250_check_nbu_client_name.sh's pause, so this picks up whatever
# the operator last saved, not whatever was on the ISO at build time. Runs
# before 350_start_netbackup.sh so that script can reuse NBU_SERVER instead
# of re-deriving it from bp.conf itself.

local nbu_bpconf=/usr/openv/netbackup/bp.conf
test -r "$nbu_bpconf" || Error "Cannot read $nbu_bpconf."

local line key value

# Split on the first '=', not on whitespace: bp.conf accepts "KEY = value",
# "KEY=value", and mixed spacing, but a plain 'read KEY VALUE' only splits
# on whitespace, so a no-space "SERVER=host" line lands entirely in $key
# and is never recognized as a SERVER line at all.
while IFS= read -r line ; do
    echo "$line" | grep -q '^[[:space:]]*#' && continue
    test -z "$( echo "$line" | tr -d '[:space:]' )" && continue
    # Skip a directive with no '=' at all: both sed patterns below no-op
    # when there's no '=' to split on, which would otherwise set
    # NBU_<KEY> to its own key name as the value instead of being skipped.
    case "$line" in
        *=*) ;;
        *) continue ;;
    esac
    key=$( echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*=.*//' | tr '[:lower:]' '[:upper:]' )
    value=$( echo "$line" | sed -e 's/^[^=]*=[[:space:]]*//' -e 's/[[:space:]]*$//' )
    test -z "$key" && continue
    # bp.conf may have more than one SERVER entry (the Primary server
    # followed by Media servers also trusted via SERVER=) and per
    # NetBackup's own convention the FIRST SERVER line is always the actual
    # Primary server. Keep it instead of letting a later SERVER line
    # silently overwrite NBU_SERVER with a media server. Every other key
    # (e.g. MEDIA_SERVER) stays last-line-wins: nothing downstream reads
    # NBU_MEDIA_SERVER today, so that's a non-issue for now.
    test "$key" = "SERVER" -a -n "$NBU_SERVER" && continue
    export NBU_$key="$value"
done <"$nbu_bpconf"
