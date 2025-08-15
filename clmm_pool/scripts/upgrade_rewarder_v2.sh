source ./export.sh

export POOL=0xefff9a1c34bdd08197e8e8a3d60d636650fa6fc4b8a39fde4cd639c7fac39e71
export COIN_A=0xda1f9eaf3d10cd6fa609d3061ac48d640c0aeb36fb031125a263736a0ae0be29::token_b::TOKEN_B
export COIN_B=0x1018b0843a724fd966b37f018bbc489918b6594144451cf4b481d392c9a0a463::token_a::TOKEN_A

sui client ptb \
--move-call $PACKAGE::pool::upgrade_rewarder_v2 "<$COIN_A, $COIN_B>" @$POOL