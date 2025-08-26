/// © 2025 Metabyte Labs, Inc.  All Rights Reserved.
/// U.S. Patent Application No. 63/861,982. The technology described herein is the subject of a pending U.S. patent application.
/// Full Sail has added a license to its Full Sail protocol code. You can view the terms of the license at [ULR](LICENSE/250825_Metabyte_Negotiated_Services_Agreement21634227_2_002.docx).

/// Stats module for the CLMM (Concentrated Liquidity Market Maker) pool system.
/// This module provides functionality for tracking and managing pool statistics.
/// 
/// The module implements:
/// * Pool statistics tracking and updates
/// * Total volume monitoring and updates
/// 
/// # Key Concepts
/// * Stats - Represents pool statistics and metrics
/// * Total Volume - Cumulative trading volume in the pool
/// 
/// # Events
/// * InitStatsEvent - Emitted when stats are initialized, containing the stats object ID
/// 
/// # Functions
/// * `init` - Creates and shares a new Stats object
/// * `get_total_volume` - Retrieves the current total volume
/// * `add_total_volume_internal` - Internal function to update total volume
module clmm_pool::stats {
    #[allow(unused_const)]
    const COPYRIGHT_NOTICE: vector<u8> = b"© 2025 Metabyte Labs, Inc.  All Rights Reserved.";
    #[allow(unused_const)]
    const PATENT_NOTICE: vector<u8> = b"Patent pending - U.S. Patent Application No. 63/861,982";

    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use clmm_pool::config::{Self, GlobalConfig};

    const EOverflow: u64 = 932523069343634633;

    /// Event emitted when stats are initialized.
    /// Contains the ID of the created Stats object.
    /// 
    /// # Fields
    /// * `stats_id` - The ID of the initialized Stats object
    public struct InitStatsEvent has copy, drop {
        stats_id: ID,
    }

    /// Represents pool statistics and metrics.
    /// Stores cumulative trading volume and other pool-related statistics.
    /// 
    /// # Fields
    /// * `id` - Unique identifier for the Stats object
    /// * `total_volume` - Cumulative trading volume in the pool
    public struct Stats has store, key {
        id: UID,
        total_volume: u256,
    }

    /// Creates and initializes a new Stats object.
    /// The object is shared and can be accessed by other modules.
    /// 
    /// # Arguments
    /// * `ctx` - Transaction context
    /// 
    /// # Events
    /// Emits `InitStatsEvent` with the ID of the created Stats object
    fun init(ctx: &mut TxContext) {
        let stats = Stats {
            id: object::new(ctx),
            total_volume: 0,
        };
        let init_event = InitStatsEvent {
            stats_id: object::id<Stats>(&stats),
        };
        transfer::share_object<Stats>(stats);
        event::emit<InitStatsEvent>(init_event);
    }

    /// Retrieves the current total trading volume from the Stats object.
    /// 
    /// # Arguments
    /// * `stats` - Reference to the Stats object
    /// 
    /// # Returns
    /// The current total trading volume as u256
    public fun get_total_volume(stats: &Stats): u256 {
        stats.total_volume
    }

    /// Internal function to update the total trading volume.
    /// Only callable from within the package.
    /// 
    /// # Arguments
    /// * `stats` - Mutable reference to the Stats object
    /// * `amount` - Amount to add to the total volume (Q64.64)
    /// 
    /// # Implementation Details
    /// Adds the specified amount to the current total volume
    public(package) fun add_total_volume_internal(stats: &mut Stats, amount: u256) {
        assert!(integer_mate::math_u256::add_check(stats.total_volume, amount), EOverflow);
        
        stats.total_volume = stats.total_volume + amount;
    }

    #[test_only]
    public fun init_test(ctx: &mut TxContext) {
        let stats = Stats {
            id: object::new(ctx),
            total_volume: 0,
        };
        transfer::share_object<Stats>(stats);
    }
}