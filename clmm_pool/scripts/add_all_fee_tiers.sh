source ./export.sh

# original fullsail has fee tiers 2-100, 10-500, 60-2500, 20-10000

sui client ptb \
--move-call $PACKAGE::config::add_fee_tier @$GLOBAL_CONFIG 2 100 \
--move-call $PACKAGE::config::add_fee_tier @$GLOBAL_CONFIG 10 500 \
--move-call $PACKAGE::config::add_fee_tier @$GLOBAL_CONFIG 60 2500 \
--move-call $PACKAGE::config::add_fee_tier @$GLOBAL_CONFIG 20 10000