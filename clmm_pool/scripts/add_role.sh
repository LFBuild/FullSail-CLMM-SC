source ./export.sh

# Параметры для добавления роли
export ADMIN_CAP=0xee6bcf7435539be1c24496badb7b37f485282b2b49fad1f4f2a540dc4ffa6901
export CONFIG_OBJECT=0x217cb181bd844317f9bb8746ceed9e8c49852a5aaf0bdfd2ba3fa94344eaa483
export MEMBER_ADDRESS=0xe28ed0b47bc4561cf70b0a2b058c530320f6ed109eebe0e8b59196990751961c
export ROLE_ID=0 # роль POOL_MANAGER (0-127)

sui client ptb \
--move-call $PACKAGE::config::add_role @$ADMIN_CAP @$CONFIG_OBJECT @$MEMBER_ADDRESS $ROLE_ID 