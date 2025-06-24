source ./export.sh

# Параметры для добавления роли
export ADMIN_CAP=0xfcc7f81f3880caf167a7d4df16ee355676636443aa02b9e84ba11d95e2bffd7b
export CONFIG_OBJECT=0xe93baa80cb570b3a494cbf0621b2ba96bc993926d34dc92508c9446f9a05d615
export MEMBER_ADDRESS=0xc2c7a6d112b07a68e6ecf8c5e6275c007589d40a87debbba155efc134ba2b6e1
export ROLE_ID=0 # роль POOL_MANAGER (0-127)

sui client ptb \
--move-call $PACKAGE::config::add_role @$ADMIN_CAP @$CONFIG_OBJECT @$MEMBER_ADDRESS $ROLE_ID 