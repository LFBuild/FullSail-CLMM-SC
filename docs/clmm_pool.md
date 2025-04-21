# CLMM Pool

## Overview

The CLMM Pool is a concentrated liquidity market maker for the FullSail protocol. It allows users to create and manage concentrated liquidity positions on the FullSail protocol.

Implementations is mainly based on the Uniswap V3 CLMM implementation. A lot of logic is just rewritten from Solidity to Move.

## Architecture overview

Main module is pool.move. It's an entry point for managing everything related to CLMM pool: managing configuration, positions, swapping.

Other modules are supporting pool module and containing math functions and necessary structures with methods for managing them.

## Main structures
### Logic-related objects
* GlobalConfig - configuration structure. contains list of `FeeTier` structures. shared after creation
* Pool - pool structure. shared after creation
* Factory - factory structure. shared after creation
* Position - position with provided liquidity structure. owner by position creator
* PositionInfo - position info structure. owned by `PositionManager`
* Tick - tick structure. owned by `TickManager`
* Partner - partner structure. storing account data for referral fees
* Rewarder - rewarder structure for storing reward details for specific coin . owned by `RewarderManager`
* Stats - stats structure. storing cumulative trading volume (not actively used yet)
### Permission objects
* AdminCap - admin capability structure
* ProtocolFeeClaimCap - protocol fee claim capability structure
* PartnerCap - partner capability structure
* RewarderCap - rewarder capability structure
* ACL - access control list structure
* Member - support structure for getting list of members with their roles
* PositionManager - position info owner (holding collection)
* RewarderManager - rewarders owner (holding collection)
* TickManager - ticks owner (holding collection)

## Main modules
### acl.move

Permission table list and functions for managing it + retreiving list of members with their roles

### config.move

Global config structure and functions for managing it. All setter functions are emitting specific events for off-chain tracking.

### utils.move

Number to string conversion.

### tick_math.move

Basically [Uniswap V3 Tick Math](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol) library rewritten for SUI.

Differences:
1. tick range is from -443636 to 443636 while in Uniswap V3 it's from -887272 to 887272
2. same goes for sqrt price range
3. for function `get_sqrt_price_at_tick` Uniswap is using Q64.96 while FullSail implementation is using Q64.64 format
4. function `get_tick_at_sqrt_price` is also was updated to use Q64.64 format

For third point constants are different from Uniswap V3 constants. For positive ticks conversion formula is `max(uint224)/(x/2^32)`, where `x` is constant from Uniswap. For negative ticks it's simple `x/2^64`

### clmm_math.move

Math functions for CLMM implementation.

Based on Uniswap V3 libraries [SqrtPriceMath](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/SqrtPriceMath.sol) and [SwapMath](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/SwapMath.sol)

For better math understanding it's recommended to explore [Uniswap V3 whitepaper](https://app.uniswap.org/whitepaper-v3.pdf), section 6.2 should be helpful for understanding.

### stats.move

Stats structure and functions for managing it. Mainly added for future upgrades, when tracking USD volume will be easier with help of oracles.

### tick.move

Tick structure implementation. Ticks are being stored in `TickManager` as a skip list.

Implementation is based on [Uniswap V3 Tick](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/Tick.sol) library.

Apart of managing fee growths it's also managing points_growth, rewards_growth and fullsail_growth as they are needed for FullSail protocol rewards calculation.

### position.move

Position and PositionInfo structure implementations. Position infos are being stored in `PositionManager` as a bidirectional linked list.

In this module there are methods for:
1. opening and closing
2. managing liquidity
3. managing rewards for position

### rewarder.move

Module for managing reward system. It provides distribution of additional rewards between pool participants, tracking accumulated rewards and managing reward token emissions.

Reward calculation is based on the amount of liquidity provided by the participant and the time spent in the pool. Same as for fees, reward per liquidity per second is stored after reward amount updates.

### partner.move

Module for managing partner system. It provides structure for storing partner data (main parameters are time bounds and referral fee rate).

### pool.move

Main module for managing pool. It's an entry point for all operations:
1. managing liquidity
2. managing configuration
3. managing rewards
4. doing swaps

### factory.move

Support module for creating new pools. Factory structure is very simple (it's just storing ) and module is providing functions for:
1. creating empty pools
2. creating pools with initial liquidity

## Entry points for main features
### Pool creation
`create_pool` and `create_pool_with_liquidity` functions inside factory module
### Providing liquidity
`open_position`, `increase_liquidity` functions inside pool module
### Removing liquidity
`close_position`, `decrease_liquidity` functions inside pool module
### Staking liquidity
`mark_position_staked`, `mark_position_unstaked` functions inside pool module

It is supposed, that staking is being processed inside `gauge` module, which is out of scope of CLMM.
### Swapping
`flash_swap`, `flash_swap_with_partner` functions inside pool module. These functions are returning `FlashSwapReceipt` structure, which must be passed to `repay_flash_swap` to settle payments.