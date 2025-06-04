source ./export.sh

sui client ptb \
--move-call $PACKAGE::config::update_protocol_fee_rate @$GLOBAL_CONFIG 500