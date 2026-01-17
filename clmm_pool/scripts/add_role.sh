source ./export.sh

# Параметры для добавления роли
export MEMBER_ADDRESS=0x5629bc7f393bf242a5407c59f530a1150f6c863849a288bba801a88379fb966c
export ROLE_ID=0 # роль POOL_MANAGER (0-127)

sui client ptb \
--sender @0xfed1c619fc8dd98367a0422ca9ef53c9825e2893d78dda822106d12687888fb3 --gas-coin @0xe6600100e23ccefd343837558242768b59dacca73b28132482e1b0ec6370c81b --gas-budget 100000000 --serialize-unsigned-transaction \
--move-call $PACKAGE::config::add_role @$ADMIN_CAP @$GLOBAL_CONFIG @$MEMBER_ADDRESS $ROLE_ID 