source ./export.sh

# Address to receive the CreateCap
export RECIPIENT_ADDRESS=0x30e1e70f7915da589052e2b56d005825c1a12ae6dae61abf67c9be3daa4a7671

sui client ptb \
--move-call $PACKAGE::gauge_cap::grant_create_cap @$PUBLISHER @$RECIPIENT_ADDRESS

