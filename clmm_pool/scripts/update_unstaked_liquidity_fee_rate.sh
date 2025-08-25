source ./export.sh

export POOL=0xe986dda6a6cecf3e132c9e31f6faf98aa1902eed7dfebc71c88112ccaaf37d93
export COIN_A=0xe69a16dd83717f6f224314157af7b75283a297a61a1e5f20f373ecb9f8904a63::token_c::TOKEN_C
export COIN_B=0xda1f9eaf3d10cd6fa609d3061ac48d640c0aeb36fb031125a263736a0ae0be29::token_b::TOKEN_B

sui client ptb \
--move-call $PACKAGE::pool::update_unstaked_liquidity_fee_rate "<$COIN_A,$COIN_B>" @$GLOBAL_CONFIG @$POOL 10000