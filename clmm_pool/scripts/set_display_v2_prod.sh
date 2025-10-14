source ./export.sh

sui client ptb \
--move-call $PACKAGE::position::set_display_v2 @$GLOBAL_CONFIG \
@$POSITION_PUBLISHER \
'"{description}"' \
'"https://app.fullsail.finance/liquidity/{pool}/positions/{id}"' \
'"https://app.fullsail.finance/static_files/position.png"' \
'"https://fullsail.finance"' \
'"FULLSAIL"'