source ./export.sh

sui client ptb \
--move-call $PACKAGE::price_provider::new