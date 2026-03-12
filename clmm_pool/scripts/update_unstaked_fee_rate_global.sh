source ./export.sh

sui client ptb \
--move-call $PACKAGE::config::update_unstaked_liquidity_fee_rate @$GLOBAL_CONFIG 10000