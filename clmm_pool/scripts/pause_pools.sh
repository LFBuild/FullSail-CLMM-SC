#!/bin/bash

source ./export.sh
source ./pools/pool_wbtc_usdc.sh

export PACKAGE=0xf7ca99f9fd82da76083a52ab56d88aff15d039b76499b85db8b8bc4d4804584a
export GLOBAL_CONFIG=0xe93baa80cb570b3a494cbf0621b2ba96bc993926d34dc92508c9446f9a05d615

sui client ptb \
--move-call $PACKAGE::pool::pause "<$COIN_A,$COIN_B>" @$GLOBAL_CONFIG @$POOL