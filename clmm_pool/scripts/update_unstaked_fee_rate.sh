source ./export.sh
source ./pools/pool_wbtc_usdc.sh

sui client ptb \
--move-call $PACKAGE::pool::update_unstaked_liquidity_fee_rate "<$COIN_A,$COIN_B>" @$GLOBAL_CONFIG @$POOL 10000