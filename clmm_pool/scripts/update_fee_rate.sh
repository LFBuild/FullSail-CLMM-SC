source ./export.sh
source ./pools/pool_usdz_usdc_2.sh

export FEE_RATE=500 # denom is 1000000

sui client ptb \
--move-call $PACKAGE::pool::update_fee_rate "<$COIN_A,$COIN_B>" @$GLOBAL_CONFIG @$POOL $FEE_RATE