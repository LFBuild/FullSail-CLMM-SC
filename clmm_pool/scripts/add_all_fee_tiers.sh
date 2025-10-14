source ./export.sh

# original fullsail has fee tiers 1-100, 10-500, 40-2000, 20-10000

sui client ptb \
--move-call $PACKAGE::config::add_fee_tier @$GLOBAL_CONFIG 50 3000 