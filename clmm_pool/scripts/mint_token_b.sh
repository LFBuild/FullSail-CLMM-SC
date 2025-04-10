# this is a test token with unlimited mint
export AMOUNT=5000000000

export PACKAGE=0xda1f9eaf3d10cd6fa609d3061ac48d640c0aeb36fb031125a263736a0ae0be29
export ADDR=$(sui client active-address)
export TREASURY_CAP=0x385215d51c2c692e960b3fdd0ccc66cc1600d7758547251898906889753effd7
export COIN_METADATA=0x9b79c68532cb6839fb683376efc2abda1715d1b04d6d60ca73444998a1405d33

sui client ptb \
--move-call sui::coin::mint "<$PACKAGE::token_b::TOKEN_B>" @$TREASURY_CAP $AMOUNT \
--assign coins \
--transfer-objects '[coins]' @$ADDR