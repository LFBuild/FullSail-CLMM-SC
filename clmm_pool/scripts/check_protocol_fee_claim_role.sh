source ./export.sh

export MEMBER_ADDRESS=0xfed1c619fc8dd98367a0422ca9ef53c9825e2893d78dda822106d12687888fb3

sui client ptb \
--move-call $PACKAGE::config::check_protocol_fee_claim_role @$GLOBAL_CONFIG @$MEMBER_ADDRESS --dry-run