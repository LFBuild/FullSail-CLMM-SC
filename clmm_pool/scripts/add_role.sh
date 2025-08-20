source ./export.sh

# Параметры для добавления роли
export MEMBER_ADDRESS=0xe28ed0b47bc4561cf70b0a2b058c530320f6ed109eebe0e8b59196990751961c
export ROLE_ID=0 # роль POOL_MANAGER (0-127)

sui client ptb \
--move-call $PACKAGE::config::add_role @$ADMIN_CAP @$GLOBAL_CONFIG @$MEMBER_ADDRESS $ROLE_ID 