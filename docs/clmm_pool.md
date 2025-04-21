# CLMM Pool

## Overview

The CLMM Pool is a concentrated liquidity market maker for the FullSail protocol. It allows users to create and manage concentrated liquidity positions on the FullSail protocol.

Implementations is mainly based on the Uniswap V3 CLMM implementation. A lot of logic is just rewritten from Solidity to Move.

## Main structures
### Logic-related objects
* GlobalConfig - configuration structure. contains list of `FeeTier` structures. shared after creation
* Pool - pool structure. shared after creation.
* Position - position with provided liquidity structure. owned by `PositionManager`
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
* PositionManager - positions owner (holding collection)
* RewarderManager - rewarders owner (holding collection)
* TickManager - ticks owner (holding collection)

## Main modules
### acl.move
### config.move
### clmm_math.move
### utils.move
Number to string conversion.
### stats.move
### tick_math.move
### tick.move
### position.move
### rewarder.move
### partner.move
### pool.move
### factory.move

## Main pipelines
### Providing liquidity
### Providing and staking liquidity
### Removing liquidity 
### Swapping