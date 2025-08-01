source ./export.sh

# Параметры для добавления роли
export MEMBER_ADDRESS=0xd5553230a381cb6e1447c94751017a0235f997003cfbbd379fa8382408dbe434
export ROLE_ID=0 # роль POOL_MANAGER (0-127)

sui client ptb \
--move-call $PACKAGE::config::add_role @$ADMIN_CAP @$GLOBAL_CONFIG @$MEMBER_ADDRESS $ROLE_ID 