#!/bin/bash

# Check if pool address is provided as an argument
if [ -z "$1" ]; then
    echo "Error: Pool address must be specified"
    echo "Usage: $0 <pool_address>"
    exit 1
fi

export PACKAGE=0x0000000000000000000000000000000000000000000000000000000000000000
export GLOBAL_CONFIG=0x0000000000000000000000000000000000000000000000000000000000000000
export POOL=$1

sui client ptb \
--move-call $PACKAGE::pool::pause @$GLOBAL_CONFIG $POOL