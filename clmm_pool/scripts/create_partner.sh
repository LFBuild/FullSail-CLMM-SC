source ./export.sh

export NAME='"Barons"'
export WHO=0x87c9e076815e78ee63b7dc225704c428b8c51072ccead4304ae07f6c68fe1b92

sui client ptb \
--move-call $PACKAGE::partner::create_partner @$GLOBAL_CONFIG @$PARTNERS $NAME 1000 1760137030 1765317453 @$WHO @$CLOCK