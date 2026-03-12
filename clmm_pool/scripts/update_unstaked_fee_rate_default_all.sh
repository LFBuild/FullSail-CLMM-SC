source ./export.sh

# default_unstaked_fee_rate() = 72057594037927935 (sentinel value, falls through to global config rate)
RATE=2000

update_pool() {
    source ./pools/pool_$1.sh
    echo "--move-call $PACKAGE::pool::update_unstaked_liquidity_fee_rate <$COIN_A,$COIN_B> @$GLOBAL_CONFIG @$POOL $RATE"
}

sui client ptb \
$(update_pool "alkimi_sui") \
$(update_pool "axol_sui") \
$(update_pool "manifest_usdc") \
$(update_pool "mmt_usdc") \
$(update_pool "mystic_sui") \
$(update_pool "tato_sui") \
$(update_pool "up_sui") \
$(update_pool "xbtc_l0wbtc")
