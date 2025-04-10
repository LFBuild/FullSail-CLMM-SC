# this is a test token with unlimited mint

# decimals 9
export AMOUNT=10000000000

export PACKAGE=0x1018b0843a724fd966b37f018bbc489918b6594144451cf4b481d392c9a0a463
export ADDR=$(sui client active-address)
export TREASURY_CAP=0x95bc0925f1e4c2469f4448b81bc191f3cd38ab1f3b14463c82a816a2edd02923
export COIN_METADATA=0x57ec0b6c22c3dc2c5cbbabb8a8e8baa647726128df41f816c62f22af6bc785bb

sui client ptb \
--move-call sui::coin::mint "<$PACKAGE::token_a::TOKEN_A>" @$TREASURY_CAP $AMOUNT \
--assign coins \
--transfer-objects '[coins]' @$ADDR