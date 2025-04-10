# this is a test token with unlimited mint
export AMOUNT=5000000000

export PACKAGE=0xe69a16dd83717f6f224314157af7b75283a297a61a1e5f20f373ecb9f8904a63
export ADDR=$(sui client active-address)
export TREASURY_CAP=0x0561c2f87ac3d8e71dd3c48eba441ec7aaa03e8e19b2e84753325d970ec7282d
export COIN_METADATA=0xb127663d768e5aa8ca9cd53489e53b506b9c3d58f3f97b16c4738126c6106b7f

sui client ptb \
--move-call sui::coin::mint "<$PACKAGE::token_c::TOKEN_C>" @$TREASURY_CAP $AMOUNT \
--assign coins \
--transfer-objects '[coins]' @$ADDR