source ./export.sh

# original fullsail has fee tiers 2-100, 10-500, 60-2500, 20-10000
export TICK_SPACING=2
export FEE_RATE=100 # decimals 6
export TEST=0x17cf25e15441ec17c73131b53d21737071f38eedbdf346e41d32553fffb67b63

sui client ptb \
--move-call $PACKAGE::config::update_test_struct @$TEST