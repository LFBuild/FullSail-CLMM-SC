#!/bin/bash

source ./export.sh
source ./pools/pool_wbtc_usdc.sh

sui client ptb \
--move-call $PACKAGE::pool::unpause "<$COIN_A,$COIN_B>" @$GLOBAL_CONFIG @$POOL