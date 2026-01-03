source ./export.sh
source ./pools/pool_stsui_usdc.sh

export FEE_RATE=1750 # denom is 1000000

sui client ptb \
--move-call $PACKAGE::pool::update_fee_rate "<$COIN_A,$COIN_B>" @$GLOBAL_CONFIG @$POOL $FEE_RATE