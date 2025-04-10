source ./export.sh

# original fullsail has fee tiers 2-100, 10-500, 60-2500, 20-10000
export TICK_SPACING=2
export FEE_RATE=100 # decimals 6

sui client ptb \
--move-call $PACKAGE::config::add_fee_tier @$GLOBAL_CONFIG $TICK_SPACING $FEE_RATE