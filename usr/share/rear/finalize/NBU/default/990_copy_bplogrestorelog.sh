# 990_copy_bplogrestorelog.sh

# copy the logfile to the recovered system, at least the part that has been written till now.

mkdir -p $TARGET_FS_ROOT/$ROOT_HOME_DIR
LogPrintIfError "Failed to create $TARGET_FS_ROOT/$ROOT_HOME_DIR."
cp -f $TMP_DIR/bplog.restore* $TARGET_FS_ROOT/$ROOT_HOME_DIR/
LogPrintIfError "Failed to copy $TMP_DIR/bplog.restore* to $TARGET_FS_ROOT/$ROOT_HOME_DIR."
