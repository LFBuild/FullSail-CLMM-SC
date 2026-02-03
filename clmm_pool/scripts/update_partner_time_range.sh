source ./export.sh

export PARTNER=0x4b67f048fdcdb66e52dec723ad8a1aa9909bd2ad8ac71650c2c50467495f9344
export START_TIME=1760137030
export END_TIME=1785622434

sui client ptb \
--move-call $PACKAGE::partner::update_time_range @$GLOBAL_CONFIG @$PARTNER $START_TIME $END_TIME @$CLOCK
