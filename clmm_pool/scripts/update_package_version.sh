source ./export.sh

sui client ptb \
--sender @0xfed1c619fc8dd98367a0422ca9ef53c9825e2893d78dda822106d12687888fb3 --gas-coin @0xcc7c6b958f68357cfb10ca6c74d0fcec14da7dfc9b68a191c5eccc3a08454c91 --gas-budget 100000000 --serialize-unsigned-transaction \
--move-call $PACKAGE::config::update_package_version @$ADMIN_CAP @$GLOBAL_CONFIG 3