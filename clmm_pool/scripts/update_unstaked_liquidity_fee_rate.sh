source ./export.sh

export POOL=0xc9f0c60fb486c8ba0a2599b22cad60d3223a676c60ef6ed3e559274e544f0eec
export COIN_A=0xfae8dc6bf7b9d8713f31fcf723f57c251c42c067e7e5c4ef68c1de09652db3cf::SAIL::SAIL
export COIN_B=0x1018b0843a724fd966b37f018bbc489918b6594144451cf4b481d392c9a0a463::token_a::TOKEN_A

sui client ptb \
--move-call $PACKAGE::pool::update_unstaked_liquidity_fee_rate "<$COIN_A,$COIN_B>" @$GLOBAL_CONFIG @$POOL 10000