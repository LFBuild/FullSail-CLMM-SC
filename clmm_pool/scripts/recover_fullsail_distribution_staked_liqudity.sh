source ./export.sh
source ./pools/pool_wbtc_usdc.sh

sui client ptb \
--move-call $PACKAGE::pool::restore_fullsail_distribution_staked_liquidity "<$COIN_A,$COIN_B>" @$POOL @$GLOBAL_CONFIG --dry-run