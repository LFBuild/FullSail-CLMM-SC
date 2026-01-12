#!/bin/bash

source ./export.sh

# Gas parameters (same as in add_role.sh)
export GAS_COIN=0xe6600100e23ccefd343837558242768b59dacca73b28132482e1b0ec6370c81b
export GAS_BUDGET=200000000
export SENDER=0xfed1c619fc8dd98367a0422ca9ef53c9825e2893d78dda822106d12687888fb3
export RECEIVER=0xc1d8fbc5ee3426dc50eeafd25579212bfe8aa0169ebb5445d36abc68932339db

# Build the PTB command
PTB_CMD="sui client ptb --sender @$SENDER --gas-coin @$GAS_COIN --gas-budget $GAS_BUDGET --serialize-unsigned-transaction"

# Collect protocol fees from all pools
# collect_protocol_fee returns balances, which need to be converted to coins and transferred

# Helper function to collect fees from a pool
collect_fees_from_pool() {
    local pool_name=$1
    local result_var="result_${pool_name}"
    local coin_a_var="coin_a_${pool_name}"
    local coin_b_var="coin_b_${pool_name}"
    
    source ./pools/pool_${pool_name}.sh
    # Collect protocol fees (returns tuple of two balances)
    PTB_CMD="$PTB_CMD --move-call $PACKAGE::pool::collect_protocol_fee'<'$COIN_A,$COIN_B'>' @$GLOBAL_CONFIG @$POOL --assign ${result_var}"
    # Convert balance_a (result.0) to coin_a
    PTB_CMD="$PTB_CMD --move-call 0x2::coin::from_balance'<'$COIN_A'>' ${result_var}.0 --assign ${coin_a_var}"
    # Convert balance_b (result.1) to coin_b
    PTB_CMD="$PTB_CMD --move-call 0x2::coin::from_balance'<'$COIN_B'>' ${result_var}.1 --assign ${coin_b_var}"
    # Transfer coins to receiver
    PTB_CMD="$PTB_CMD --transfer-objects [${coin_a_var}] @$RECEIVER"
    PTB_CMD="$PTB_CMD --transfer-objects [${coin_b_var}] @$RECEIVER"
}

# Collect fees from all pools
collect_fees_from_pool "alkimi_sui"
collect_fees_from_pool "axol_sui"
collect_fees_from_pool "deep_sui"
collect_fees_from_pool "eth_usdc"
collect_fees_from_pool "ika_sui"
collect_fees_from_pool "l0wbtc_usdc"
collect_fees_from_pool "lofi_sui"
collect_fees_from_pool "manifest_usdc"
collect_fees_from_pool "mmt_usdc"
collect_fees_from_pool "mystic_sui"
collect_fees_from_pool "sail_usdc"
collect_fees_from_pool "stsui_deep"
collect_fees_from_pool "stsui_usdc"
collect_fees_from_pool "stsui_wal"
collect_fees_from_pool "sui_usdc"
collect_fees_from_pool "tato_sui"
collect_fees_from_pool "up_sui"
collect_fees_from_pool "usdb_sui"
collect_fees_from_pool "usdb_usdc"
collect_fees_from_pool "usdt_usdc"
collect_fees_from_pool "usdz_usdc"
collect_fees_from_pool "wal_sui"
collect_fees_from_pool "wbtc_usdc"

# Execute the command
eval $PTB_CMD

