/// Tick module for the CLMM (Concentrated Liquidity Market Maker) pool system.
/// This module provides functionality for:
/// * Managing price ticks and their boundaries
/// * Tracking liquidity at different price levels
/// * Handling tick state and transitions
/// * Managing tick-related calculations and validations
/// 
/// The module implements:
/// * Tick state management
/// * Liquidity tracking per tick
/// * Price level calculations
/// * Tick boundary validations
/// 
/// # Key Concepts
/// * Tick - A price level in the pool
/// * Tick State - Current state of a tick (liquidity, fees, etc.)
/// * Tick Boundary - Price range limits for a tick
/// * Tick Spacing - Minimum distance between ticks
/// 
/// # Events
/// * Tick state update events
/// * Liquidity change events
/// * Tick boundary crossing events
/// * Tick initialization events
module clmm_pool::tick {
    /// Manager for tick operations in the pool.
    /// Handles tick spacing and maintains a skip list of all ticks.
    /// 
    /// # Fields
    /// * `tick_spacing` - Minimum distance between ticks
    /// * `ticks` - Skip list containing all ticks in the pool
    public struct TickManager has store {
        tick_spacing: u32,
        ticks: move_stl::skip_list::SkipList<Tick>,
    }

    /// Represents a single price tick in the pool.
    /// Contains information about price, liquidity, fees, and rewards.
    /// 
    /// # Fields
    /// * `index` - Index of the tick
    /// * `sqrt_price` - Square root of the price at this tick
    /// * `liquidity_net` - Net liquidity at this tick (can be negative)
    /// * `liquidity_gross` - Gross liquidity at this tick
    /// * `fee_growth_outside_a` - Accumulated fees for token A outside this tick
    /// * `fee_growth_outside_b` - Accumulated fees for token B outside this tick
    /// * `points_growth_outside` - Accumulated points outside this tick
    /// * `rewards_growth_outside` - Vector of accumulated rewards outside this tick
    /// * `fullsail_distribution_staked_liquidity_net` - Net staked liquidity for FULLSAIL distribution
    /// * `fullsail_distribution_growth_outside` - Accumulated FULLSAIL distribution outside this tick
    public struct Tick has copy, drop, store {
        index: integer_mate::i32::I32,
        sqrt_price: u128,
        liquidity_net: integer_mate::i128::I128,
        liquidity_gross: u128,
        fee_growth_outside_a: u128,
        fee_growth_outside_b: u128,
        points_growth_outside: u128,
        rewards_growth_outside: vector<u128>,
        fullsail_distribution_staked_liquidity_net: integer_mate::i128::I128,
        fullsail_distribution_growth_outside: u128,
    }

    /// Creates a new TickManager instance with specified parameters.
    /// 
    /// # Arguments
    /// * `tick_spacing` - Minimum distance between ticks
    /// * `seed` - Random seed for skip list initialization
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Returns
    /// A new TickManager instance with:
    /// * Specified tick spacing
    /// * New skip list with max level 16 and probability 0.5
    public(package) fun new(tick_spacing: u32, seed: u64, ctx: &mut sui::tx_context::TxContext): TickManager {
        TickManager {
            tick_spacing,
            ticks: move_stl::skip_list::new<Tick>(16, 2, seed, ctx),
        }
    }

    /// Gets a reference to a tick by its index.
    /// 
    /// # Arguments
    /// * `tick_manager` - Reference to the tick manager
    /// * `tick_index` - Index of the tick to retrieve
    /// 
    /// # Returns
    /// Reference to the requested tick
    /// 
    /// # Abort Conditions
    /// * If the tick does not exist (error code: 2)
    public fun borrow_tick(tick_manager: &TickManager, tick_index: integer_mate::i32::I32): &Tick {
        move_stl::skip_list::borrow<Tick>(&tick_manager.ticks, tick_score(tick_index))
    }

    /// Gets a reference to a tick and its adjacent score for swap operations.
    /// Used to traverse ticks during swap execution.
    /// 
    /// # Arguments
    /// * `tick_manager` - Reference to the tick manager
    /// * `score` - Score of the current tick
    /// * `is_prev` - Whether to get the previous (true) or next (false) tick
    /// 
    /// # Returns
    /// Tuple containing:
    /// * Reference to the requested tick
    /// * Option containing the score of the adjacent tick (previous or next)
    /// 
    /// # Abort Conditions
    /// * If the tick does not exist (error code: 2)
    public fun borrow_tick_for_swap(
        tick_manager: &TickManager,
        score: u64,
        is_prev: bool
    ): (&Tick, move_stl::option_u64::OptionU64) {
        let node = move_stl::skip_list::borrow_node<Tick>(&tick_manager.ticks, score);
        let next_score = if (is_prev) {
            move_stl::skip_list::prev_score<Tick>(node)
        } else {
            move_stl::skip_list::next_score<Tick>(node)
        };
        (move_stl::skip_list::borrow_value<Tick>(node), next_score)
    }
    
    /// Handles crossing a tick during a swap operation.
    /// Updates liquidity, fees, rewards, and points when crossing a tick boundary.
    /// 
    /// # Arguments
    /// * `tick_manager` - Mutable reference to the tick manager
    /// * `tick_index` - Index of the tick being crossed
    /// * `is_a2b` - Whether the swap is from token A to B (true) or B to A (false)
    /// * `current_liquidity` - Current liquidity in the pool
    /// * `staked_liquidity` - Current staked liquidity for FULLSAIL distribution
    /// * `fee_growth_global_a` - Global fee growth for token A
    /// * `fee_growth_global_b` - Global fee growth for token B
    /// * `points_growth_global` - Global points growth
    /// * `rewards_growth_global` - Vector of global rewards growth
    /// * `fullsail_growth_global` - Global FULLSAIL distribution growth
    /// 
    /// # Returns
    /// Tuple containing:
    /// * New liquidity after crossing
    /// * New staked liquidity after crossing
    /// 
    /// # Abort Conditions
    /// * If adding liquidity would cause overflow (error code: 1)
    /// * If subtracting liquidity would result in negative value (error code: 1)
    /// * If subtracting staked liquidity would result in negative value (error code: 9223372401926995967)
    public(package) fun cross_by_swap(
        tick_manager: &mut TickManager,
        tick_index: integer_mate::i32::I32,
        is_a2b: bool,
        current_liquidity: u128,
        staked_liquidity: u128,
        fee_growth_global_a: u128,
        fee_growth_global_b: u128,
        points_growth_global: u128,
        rewards_growth_global: vector<u128>,
        fullsail_growth_global: u128
    ): (u128, u128) {
        let tick = move_stl::skip_list::borrow_mut<Tick>(&mut tick_manager.ticks, tick_score(tick_index));
        let (liquidity_delta, staked_liquidity_delta) = if (is_a2b) {
            (integer_mate::i128::neg(tick.liquidity_net), integer_mate::i128::neg(
                tick.fullsail_distribution_staked_liquidity_net
            ))
        } else {
            (tick.liquidity_net, tick.fullsail_distribution_staked_liquidity_net)
        };
        let (new_liquidity, new_staked_liquidity) = if (!integer_mate::i128::is_neg(liquidity_delta)) {
            let liquidity_abs = integer_mate::i128::abs_u128(liquidity_delta);
            assert!(integer_mate::math_u128::add_check(liquidity_abs, current_liquidity), 1);
            let staked_abs = integer_mate::i128::abs_u128(staked_liquidity_delta);
            assert!(integer_mate::math_u128::add_check(staked_abs, staked_liquidity), 1);
            (current_liquidity + liquidity_abs, staked_liquidity + staked_abs)
        } else {
            let liquidity_abs = integer_mate::i128::abs_u128(liquidity_delta);
            assert!(current_liquidity >= liquidity_abs, 1);
            let staked_abs = integer_mate::i128::abs_u128(staked_liquidity_delta);
            assert!(staked_liquidity >= staked_abs, 9223372401926995967);
            (current_liquidity - liquidity_abs, staked_liquidity - staked_abs)
        };
        tick.fee_growth_outside_a = integer_mate::math_u128::wrapping_sub(fee_growth_global_a, tick.fee_growth_outside_a);
        tick.fee_growth_outside_b = integer_mate::math_u128::wrapping_sub(fee_growth_global_b, tick.fee_growth_outside_b);
        let mut i = 0;
        while (i < std::vector::length<u128>(&rewards_growth_global)) {
            let reward_growth = *std::vector::borrow<u128>(&rewards_growth_global, i);
            if (std::vector::length<u128>(&tick.rewards_growth_outside) > i) {
                let reward_outside = std::vector::borrow_mut<u128>(&mut tick.rewards_growth_outside, i);
                *reward_outside = integer_mate::math_u128::wrapping_sub(reward_growth, *reward_outside);
            } else {
                std::vector::push_back<u128>(&mut tick.rewards_growth_outside, reward_growth);
            };
            i = i + 1;
        };
        tick.points_growth_outside = integer_mate::math_u128::wrapping_sub(points_growth_global, tick.points_growth_outside);
        tick.fullsail_distribution_growth_outside = integer_mate::math_u128::wrapping_sub(
            fullsail_growth_global,
            tick.fullsail_distribution_growth_outside
        );
        (new_liquidity, new_staked_liquidity)
    }
    
    /// Decreases liquidity at specified tick boundaries.
    /// Updates or removes ticks based on the new liquidity values.
    /// 
    /// # Arguments
    /// * `tick_manager` - Mutable reference to the tick manager
    /// * `current_tick_index` - Current tick index in the pool
    /// * `tick_lower` - Lower tick boundary
    /// * `tick_upper` - Upper tick boundary
    /// * `liquidity` - Amount of liquidity to decrease
    /// * `fee_growth_global_a` - Global fee growth for token A
    /// * `fee_growth_global_b` - Global fee growth for token B
    /// * `points_growth_global` - Global points growth
    /// * `rewards_growth_global` - Vector of global rewards growth
    /// * `fullsail_growth_global` - Global FULLSAIL distribution growth
    /// 
    /// # Abort Conditions
    /// * If lower tick does not exist (error code: 3)
    /// * If upper tick does not exist (error code: 3)
    /// * If liquidity would become negative (error code: 1)
    /// * If tick's gross liquidity would become negative (error code: 0)
    /// * If liquidity net calculation would overflow (error code: 0)
    public(package) fun decrease_liquidity(
        tick_manager: &mut TickManager,
        current_tick_index: integer_mate::i32::I32,
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32,
        liquidity: u128,
        fee_growth_global_a: u128,
        fee_growth_global_b: u128,
        points_growth_global: u128,
        rewards_growth_global: vector<u128>,
        fullsail_growth_global: u128
    ) {
        if (liquidity == 0) {
            return
        };
        let lower_score = tick_score(tick_lower);
        let upper_score = tick_score(tick_upper);
        assert!(move_stl::skip_list::contains<Tick>(&tick_manager.ticks, lower_score), 3);
        assert!(move_stl::skip_list::contains<Tick>(&tick_manager.ticks, upper_score), 3);
        if (update_by_liquidity(
            move_stl::skip_list::borrow_mut<Tick>(&mut tick_manager.ticks, lower_score),
            current_tick_index,
            liquidity,
            false,
            false,
            false,
            fee_growth_global_a,
            fee_growth_global_b,
            points_growth_global,
            rewards_growth_global,
            fullsail_growth_global
        ) == 0) {
            move_stl::skip_list::remove<Tick>(&mut tick_manager.ticks, lower_score);
        };
        if (update_by_liquidity(
            move_stl::skip_list::borrow_mut<Tick>(&mut tick_manager.ticks, upper_score),
            current_tick_index,
            liquidity,
            false,
            false,
            true,
            fee_growth_global_a,
            fee_growth_global_b,
            points_growth_global,
            rewards_growth_global,
            fullsail_growth_global
        ) == 0) {
            move_stl::skip_list::remove<Tick>(&mut tick_manager.ticks, upper_score);
        };
    }

    /// Creates a new Tick instance with default values.
    /// Initializes all fields to zero and calculates the square root price.
    /// 
    /// # Arguments
    /// * `tick_index` - Index of the tick to create
    /// 
    /// # Returns
    /// A new Tick instance with:
    /// * Specified index
    /// * Calculated square root price
    /// * Zero liquidity (both net and gross)
    /// * Zero fee growth
    /// * Zero points growth
    /// * Empty rewards vector
    /// * Zero FULLSAIL distribution values
    fun default(tick_index: integer_mate::i32::I32): Tick {
        Tick {
            index: tick_index,
            sqrt_price: clmm_pool::tick_math::get_sqrt_price_at_tick(tick_index),
            liquidity_net: integer_mate::i128::from(0),
            liquidity_gross: 0,
            fee_growth_outside_a: 0,
            fee_growth_outside_b: 0,
            points_growth_outside: 0,
            rewards_growth_outside: std::vector::empty<u128>(),
            fullsail_distribution_staked_liquidity_net: integer_mate::i128::from(0),
            fullsail_distribution_growth_outside: 0,
        }
    }

    /// Creates a vector of zero rewards growth values with specified length.
    /// 
    /// # Arguments
    /// * `rewards_count` - Number of zero values to create
    /// 
    /// # Returns
    /// Vector of zero values with length rewards_count, or empty vector if count is 0
    fun default_rewards_growth_outside(rewards_count: u64): vector<u128> {
        if (rewards_count <= 0) {
            std::vector::empty<u128>()
        } else {
            let mut rewards = std::vector::empty<u128>();
            let mut index = 0;
            while (index < rewards_count) {
                std::vector::push_back<u128>(&mut rewards, 0);
                index = index + 1;
            };
            rewards
        }
    }

    /// Gets the fee growth values outside a tick.
    /// 
    /// # Arguments
    /// * `tick` - Reference to the tick
    /// 
    /// # Returns
    /// Tuple containing:
    /// * Fee growth for token A outside the tick
    /// * Fee growth for token B outside the tick
    public fun fee_growth_outside(tick: &Tick): (u128, u128) {
        (tick.fee_growth_outside_a, tick.fee_growth_outside_b)
    }
    
    /// Fetches a list of ticks starting from a specified index or the first tick.
    /// Returns up to the specified limit of ticks.
    /// 
    /// # Arguments
    /// * `tick_manager` - Reference to the tick manager
    /// * `tick_indices` - Vector of tick indices to start from (if empty, starts from first tick)
    /// * `limit` - Maximum number of ticks to return
    /// 
    /// # Returns
    /// Vector of Tick instances, up to the specified limit
    /// 
    /// # Abort Conditions
    /// * If tick index is out of bounds (error code: 2)
    public fun fetch_ticks(tick_manager: &TickManager, tick_indices: vector<u32>, limit: u64): vector<Tick> {
        let mut result = std::vector::empty<Tick>();
        let next_score = if (std::vector::is_empty<u32>(&tick_indices)) {
            move_stl::skip_list::head<Tick>(&tick_manager.ticks)
        } else {
            move_stl::skip_list::find_next<Tick>(
                &tick_manager.ticks,
                tick_score(integer_mate::i32::from_u32(*std::vector::borrow<u32>(&tick_indices, 0))),
                false
            )
        };
        let mut current_score = next_score;
        let mut count = 0;
        while (move_stl::option_u64::is_some(&current_score)) {
            let node = move_stl::skip_list::borrow_node<Tick>(&tick_manager.ticks, move_stl::option_u64::borrow(&current_score));
            std::vector::push_back<Tick>(&mut result, *move_stl::skip_list::borrow_value<Tick>(node));
            current_score = move_stl::skip_list::next_score<Tick>(node);
            let new_count = count + 1;
            count = new_count;
            if (new_count == limit) {
                break
            };
        };
        result
    }

    /// Gets the first score for swap operations based on direction.
    /// Used to determine the starting point for swap traversal.
    /// 
    /// # Arguments
    /// * `tick_manager` - Reference to the tick manager
    /// * `tick_index` - Current tick index
    /// * `is_reverse` - Whether to traverse in reverse direction
    /// 
    /// # Returns
    /// Option containing the first score for swap traversal:
    /// * For reverse direction: Previous tick score
    /// * For forward direction: Next tick score, or minimum tick if at boundary
    /// 
    /// # Abort Conditions
    /// * If tick index is out of bounds (error code: 2)
    public fun first_score_for_swap(
        tick_manager: &TickManager,
        tick_index: integer_mate::i32::I32,
        is_reverse: bool
    ): move_stl::option_u64::OptionU64 {
        if (is_reverse) {
            move_stl::skip_list::find_prev<Tick>(&tick_manager.ticks, tick_score(tick_index), true)
        } else {
            let next_score = if (integer_mate::i32::eq(
                tick_index,
                integer_mate::i32::neg_from(clmm_pool::tick_math::tick_bound() + 1)
            )) {
                move_stl::skip_list::find_next<Tick>(&tick_manager.ticks, tick_score(clmm_pool::tick_math::min_tick()), true)
            } else {
                move_stl::skip_list::find_next<Tick>(&tick_manager.ticks, tick_score(tick_index), false)
            };
            next_score
        }
    }

    /// Calculates the accumulated fees within a specified tick range.
    /// Takes into account fees both below and above the current tick.
    /// 
    /// # Arguments
    /// * `current_tick_index` - Current tick index in the pool
    /// * `fee_growth_global_a` - Global fee growth for token A
    /// * `fee_growth_global_b` - Global fee growth for token B
    /// * `tick_lower` - Option containing the lower tick boundary
    /// * `tick_upper` - Option containing the upper tick boundary
    /// 
    /// # Returns
    /// Tuple containing:
    /// * Accumulated fees for token A within the range
    /// * Accumulated fees for token B within the range
    /// 
    /// # Implementation Details
    /// * For lower tick:
    ///   - If current tick is below lower tick: uses global fees minus lower tick's outside fees
    ///   - If current tick is above lower tick: uses lower tick's outside fees
    /// * For upper tick:
    ///   - If current tick is below upper tick: uses upper tick's outside fees
    ///   - If current tick is above upper tick: uses global fees minus upper tick's outside fees
    /// * Final calculation: global fees minus fees below minus fees above
    public fun get_fee_in_range(
        current_tick_index: integer_mate::i32::I32,
        fee_growth_global_a: u128,
        fee_growth_global_b: u128,
        tick_lower: std::option::Option<Tick>,
        tick_upper: std::option::Option<Tick>
    ): (u128, u128) {
        let (fee_growth_below_a, fee_growth_below_b) = if (std::option::is_none<Tick>(&tick_lower)) {
            (fee_growth_global_a, fee_growth_global_b)
        } else {
            let tick_l = std::option::borrow<Tick>(&tick_lower);
            let (fee_a, fee_b) = if (integer_mate::i32::lt(current_tick_index, tick_l.index)) {
                (integer_mate::math_u128::wrapping_sub(
                    fee_growth_global_a,
                    tick_l.fee_growth_outside_a
                ), integer_mate::math_u128::wrapping_sub(
                    fee_growth_global_b,
                    tick_l.fee_growth_outside_b
                ))
            } else {
                (tick_l.fee_growth_outside_a, tick_l.fee_growth_outside_b)
            };
            (fee_a, fee_b)
        };

        let (fee_growth_above_a, fee_growth_above_b) = if (std::option::is_none<Tick>(&tick_upper)) {
            (0, 0)
        } else {
            let tick_u = std::option::borrow<Tick>(&tick_upper);
            let (fee_a, fee_b) = if (integer_mate::i32::lt(current_tick_index, tick_u.index)) {
                (tick_u.fee_growth_outside_a, tick_u.fee_growth_outside_b)
            } else {
                (integer_mate::math_u128::wrapping_sub(
                    fee_growth_global_a,
                    tick_u.fee_growth_outside_a
                ), integer_mate::math_u128::wrapping_sub(
                    fee_growth_global_b,
                    tick_u.fee_growth_outside_b
                ))
            };
            (fee_a, fee_b)
        };
        (integer_mate::math_u128::wrapping_sub(
            integer_mate::math_u128::wrapping_sub(fee_growth_global_a, fee_growth_below_a),
            fee_growth_above_a
        ), integer_mate::math_u128::wrapping_sub(
            integer_mate::math_u128::wrapping_sub(fee_growth_global_b, fee_growth_below_b),
            fee_growth_above_b
        ))
    }

    /// Calculates the accumulated FULLSAIL distribution growth within a specified tick range.
    /// Takes into account FULLSAIL growth both below and above the current tick.
    /// 
    /// # Arguments
    /// * `current_tick_index` - Current tick index in the pool
    /// * `fullsail_growth_global` - Global FULLSAIL distribution growth
    /// * `tick_lower` - Option containing the lower tick boundary
    /// * `tick_upper` - Option containing the upper tick boundary
    /// 
    /// # Returns
    /// The accumulated FULLSAIL distribution growth within the specified range
    /// 
    /// # Implementation Details
    /// * For lower tick:
    ///   - If current tick is below lower tick: uses global FULLSAIL growth minus lower tick's outside growth
    ///   - If current tick is above lower tick: uses lower tick's outside growth
    /// * For upper tick:
    ///   - If current tick is below upper tick: uses upper tick's outside growth
    ///   - If current tick is above upper tick: uses global FULLSAIL growth minus upper tick's outside growth
    /// * Final calculation: global FULLSAIL growth minus growth below minus growth above
    public fun get_fullsail_distribution_growth_in_range(
        current_tick_index: integer_mate::i32::I32,
        fullsail_growth_global: u128,
        tick_lower: std::option::Option<Tick>,
        tick_upper: std::option::Option<Tick>
    ): u128 {
        let fullsail_growth_below = if (std::option::is_none<Tick>(&tick_lower)) {
            fullsail_growth_global
        } else {
            let tick_l = std::option::borrow<Tick>(&tick_lower);
            let fullsail_below = if (integer_mate::i32::lt(current_tick_index, tick_l.index)) {
                integer_mate::math_u128::wrapping_sub(fullsail_growth_global, tick_l.fullsail_distribution_growth_outside)
            } else {
                tick_l.fullsail_distribution_growth_outside
            };
            fullsail_below
        };
        let fullsail_growth_above = if (std::option::is_none<Tick>(&tick_upper)) {
            0
        } else {
            let tick_u = std::option::borrow<Tick>(&tick_upper);
            let fullsail_above = if (integer_mate::i32::lt(current_tick_index, tick_u.index)) {
                tick_u.fullsail_distribution_growth_outside
            } else {
                integer_mate::math_u128::wrapping_sub(fullsail_growth_global, tick_u.fullsail_distribution_growth_outside)
            };
            fullsail_above
        };
        integer_mate::math_u128::wrapping_sub(integer_mate::math_u128::wrapping_sub(fullsail_growth_global, fullsail_growth_below), fullsail_growth_above)
    }

    /// Calculates the accumulated points within a specified tick range.
    /// Takes into account points both below and above the current tick.
    /// 
    /// # Arguments
    /// * `current_tick_index` - Current tick index in the pool
    /// * `points_growth_global` - Global points growth
    /// * `tick_lower` - Option containing the lower tick boundary
    /// * `tick_upper` - Option containing the upper tick boundary
    /// 
    /// # Returns
    /// The accumulated points within the specified range
    /// 
    /// # Implementation Details
    /// * For lower tick:
    ///   - If current tick is below lower tick: uses global points minus lower tick's outside points
    ///   - If current tick is above lower tick: uses lower tick's outside points
    /// * For upper tick:
    ///   - If current tick is below upper tick: uses upper tick's outside points
    ///   - If current tick is above upper tick: uses global points minus upper tick's outside points
    /// * Final calculation: global points minus points below minus points above
    public fun get_points_in_range(
        current_tick_index: integer_mate::i32::I32,
        points_growth_global: u128,
        tick_lower: std::option::Option<Tick>,
        tick_upper: std::option::Option<Tick>
    ): u128 {
        let points_growth_below = if (std::option::is_none<Tick>(&tick_lower)) {
            points_growth_global
        } else {
            let tick_l = std::option::borrow<Tick>(&tick_lower);
            let points_below = if (integer_mate::i32::lt(current_tick_index, tick_l.index)) {
                integer_mate::math_u128::wrapping_sub(points_growth_global, tick_l.points_growth_outside)
            } else {
                tick_l.points_growth_outside
            };
            points_below
        };
        let points_growth_above = if (std::option::is_none<Tick>(&tick_upper)) {
            0
        } else {
            let tick_u = std::option::borrow<Tick>(&tick_upper);
            let points_above = if (integer_mate::i32::lt(current_tick_index, tick_u.index)) {
                tick_u.points_growth_outside
            } else {
                integer_mate::math_u128::wrapping_sub(points_growth_global, tick_u.points_growth_outside)
            };
            points_above
        };
        integer_mate::math_u128::wrapping_sub(integer_mate::math_u128::wrapping_sub(points_growth_global, points_growth_below), points_growth_above)
    }

    /// Gets the reward growth outside a tick for a specific reward index.
    /// Returns 0 if the reward index is out of bounds.
    /// 
    /// # Arguments
    /// * `tick` - Reference to the tick
    /// * `reward_index` - Index of the reward to retrieve
    /// 
    /// # Returns
    /// The reward growth outside the tick for the specified index, or 0 if index is out of bounds
    public fun get_reward_growth_outside(tick: &Tick, reward_index: u64): u128 {
        if (std::vector::length<u128>(&tick.rewards_growth_outside) <= reward_index) {
            0
        } else {
            *std::vector::borrow<u128>(&tick.rewards_growth_outside, reward_index)
        }
    }

    /// Calculates the accumulated rewards within a specified tick range.
    /// Takes into account rewards both below and above the current tick for each reward type.
    /// 
    /// # Arguments
    /// * `current_tick_index` - Current tick index in the pool
    /// * `rewards_growth_global` - Vector of global rewards growth for each reward type
    /// * `tick_lower` - Option containing the lower tick boundary
    /// * `tick_upper` - Option containing the upper tick boundary
    /// 
    /// # Returns
    /// Vector of accumulated rewards within the specified range for each reward type
    /// 
    /// # Implementation Details
    /// * Iterates through each reward type in rewards_growth_global
    /// * For each reward type:
    ///   - For lower tick:
    ///     * If current tick is below lower tick: uses global reward minus lower tick's outside reward
    ///     * If current tick is above lower tick: uses lower tick's outside reward
    ///   - For upper tick:
    ///     * If current tick is below upper tick: uses upper tick's outside reward
    ///     * If current tick is above upper tick: uses global reward minus upper tick's outside reward
    ///   - Final calculation: global reward minus reward below minus reward above
    public fun get_rewards_in_range(
        current_tick_index: integer_mate::i32::I32,
        rewards_growth_global: vector<u128>,
        tick_lower: std::option::Option<Tick>,
        tick_upper: std::option::Option<Tick>
    ): vector<u128> {
        let mut rewards_in_range = std::vector::empty<u128>();
        let mut reward_index = 0;
        while (reward_index < std::vector::length<u128>(&rewards_growth_global)) {
            let reward_growth_global = *std::vector::borrow<u128>(&rewards_growth_global, reward_index);
            let reward_growth_below = if (std::option::is_none<Tick>(&tick_lower)) {
                reward_growth_global
            } else {
                let tick_l = std::option::borrow<Tick>(&tick_lower);
                let reward_below = if (integer_mate::i32::lt(current_tick_index, tick_l.index)) {
                    integer_mate::math_u128::wrapping_sub(reward_growth_global, get_reward_growth_outside(tick_l, reward_index))
                } else {
                    get_reward_growth_outside(tick_l, reward_index)
                };
                reward_below
            };
            let reward_growth_above = if (std::option::is_none<Tick>(&tick_upper)) {
                0
            } else {
                let tick_u = std::option::borrow<Tick>(&tick_upper);
                let reward_above = if (integer_mate::i32::lt(current_tick_index, tick_u.index)) {
                    get_reward_growth_outside(tick_u, reward_index)
                } else {
                    let reward_outside = get_reward_growth_outside(tick_u, reward_index);
                    integer_mate::math_u128::wrapping_sub(reward_growth_global, reward_outside)
                };
                reward_above
            };
            std::vector::push_back<u128>(
                &mut rewards_in_range,
                integer_mate::math_u128::wrapping_sub(integer_mate::math_u128::wrapping_sub(reward_growth_global, reward_growth_below), reward_growth_above)
            );
            reward_index = reward_index + 1;
        };
        rewards_in_range
    }
    
    /// Increases liquidity at specified tick boundaries.
    /// Creates new ticks if they don't exist and updates existing ones.
    /// 
    /// # Arguments
    /// * `tick_manager` - Mutable reference to the tick manager
    /// * `current_tick_index` - Current tick index in the pool
    /// * `tick_lower` - Lower tick boundary
    /// * `tick_upper` - Upper tick boundary
    /// * `liquidity` - Amount of liquidity to increase
    /// * `fee_growth_global_a` - Global fee growth for token A
    /// * `fee_growth_global_b` - Global fee growth for token B
    /// * `points_growth_global` - Global points growth
    /// * `rewards_growth_global` - Vector of global rewards growth
    /// * `fullsail_distribution_growth_global` - Global FULLSAIL distribution growth
    /// 
    /// # Implementation Details
    /// * Early return if liquidity is 0
    /// * Creates new ticks at lower and upper boundaries if they don't exist
    /// * Updates both lower and upper ticks with:
    ///   - New liquidity values
    ///   - Fee growth outside values
    ///   - Points growth outside values
    ///   - Rewards growth outside values
    ///   - FULLSAIL distribution growth outside values
    /// 
    /// # Abort Conditions
    /// * If adding liquidity would cause overflow (error code: 0)
    /// * If tick index is out of bounds (error code: 2)
    public(package) fun increase_liquidity(
        tick_manager: &mut TickManager,
        current_tick_index: integer_mate::i32::I32,
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32,
        liquidity: u128,
        fee_growth_global_a: u128,
        fee_growth_global_b: u128,
        points_growth_global: u128,
        rewards_growth_global: vector<u128>,
        fullsail_distribution_growth_global: u128
    ) {
        if (liquidity == 0) {
            return
        };
        let tick_lower_score = tick_score(tick_lower);
        let tick_upper_score = tick_score(tick_upper);
        let mut is_upper_initialized = false;
        let mut is_lower_initialized = false;
        if (!move_stl::skip_list::contains<Tick>(&tick_manager.ticks, tick_lower_score)) {
            move_stl::skip_list::insert<Tick>(&mut tick_manager.ticks, tick_lower_score, default(tick_lower));
            is_lower_initialized = true;
        };
        if (!move_stl::skip_list::contains<Tick>(&tick_manager.ticks, tick_upper_score)) {
            move_stl::skip_list::insert<Tick>(&mut tick_manager.ticks, tick_upper_score, default(tick_upper));
            is_upper_initialized = true;
        };
        update_by_liquidity(
            move_stl::skip_list::borrow_mut<Tick>(&mut tick_manager.ticks, tick_lower_score),
            current_tick_index,
            liquidity,
            is_lower_initialized,
            true,
            false,
            fee_growth_global_a,
            fee_growth_global_b,
            points_growth_global,
            rewards_growth_global,
            fullsail_distribution_growth_global
        );
        update_by_liquidity(
            move_stl::skip_list::borrow_mut<Tick>(&mut tick_manager.ticks, tick_upper_score),
            current_tick_index,
            liquidity,
            is_upper_initialized,
            true,
            true,
            fee_growth_global_a,
            fee_growth_global_b,
            points_growth_global,
            rewards_growth_global,
            fullsail_distribution_growth_global
        );
    }
    
    /// Returns the index of the tick.
    /// 
    /// # Arguments
    /// * `tick` - Reference to the tick
    /// 
    /// # Returns
    /// The tick index as an I32 value
    public fun index(tick: &Tick): integer_mate::i32::I32 {
        tick.index
    }

    /// Returns the gross liquidity of the tick.
    /// 
    /// # Arguments
    /// * `tick` - Reference to the tick
    /// 
    /// # Returns
    /// The gross liquidity as a u128 value
    public fun liquidity_gross(tick: &Tick): u128 {
        tick.liquidity_gross
    }

    /// Returns the net liquidity of the tick.
    /// 
    /// # Arguments
    /// * `tick` - Reference to the tick
    /// 
    /// # Returns
    /// The net liquidity as an I128 value
    public fun liquidity_net(tick: &Tick): integer_mate::i128::I128 {
        tick.liquidity_net
    }

    /// Returns the FULLSAIL distribution growth outside the tick.
    /// 
    /// # Arguments
    /// * `tick` - Reference to the tick
    /// 
    /// # Returns
    /// The FULLSAIL distribution growth outside as a u128 value
    public fun fullsail_distribution_growth_outside(tick: &Tick): u128 {
        tick.fullsail_distribution_growth_outside
    }

    /// Returns the net staked liquidity for FULLSAIL distribution.
    /// 
    /// # Arguments
    /// * `tick` - Reference to the tick
    /// 
    /// # Returns
    /// The net staked liquidity as an I128 value
    public fun fullsail_distribution_staked_liquidity_net(tick: &Tick): integer_mate::i128::I128 {
        tick.fullsail_distribution_staked_liquidity_net
    }

    /// Returns the points growth outside the tick.
    /// 
    /// # Arguments
    /// * `tick` - Reference to the tick
    /// 
    /// # Returns
    /// The points growth outside as a u128 value
    public fun points_growth_outside(tick: &Tick): u128 {
        tick.points_growth_outside
    }

    /// Returns a reference to the vector of rewards growth outside the tick.
    /// 
    /// # Arguments
    /// * `tick` - Reference to the tick
    /// 
    /// # Returns
    /// Reference to the vector of rewards growth outside values
    public fun rewards_growth_outside(tick: &Tick): &vector<u128> {
        &tick.rewards_growth_outside
    }

    /// Returns the square root price at the tick.
    /// 
    /// # Arguments
    /// * `tick` - Reference to the tick
    /// 
    /// # Returns
    /// The square root price as a u128 value
    public fun sqrt_price(tick: &Tick): u128 {
        tick.sqrt_price
    }

    /// Calculates the score for a tick index.
    /// Used for internal skip list operations.
    /// 
    /// # Arguments
    /// * `tick_index` - Index of the tick
    /// 
    /// # Returns
    /// The score as a u64 value
    /// 
    /// # Abort Conditions
    /// * If the adjusted tick index is out of bounds (error code: 2)
    fun tick_score(tick_index: integer_mate::i32::I32): u64 {
        let bound_adjusted_tick = integer_mate::i32::as_u32(
            integer_mate::i32::add(tick_index, integer_mate::i32::from(clmm_pool::tick_math::tick_bound()))
        );
        assert!(bound_adjusted_tick >= 0 && bound_adjusted_tick <= clmm_pool::tick_math::tick_bound() * 2, 2);
        bound_adjusted_tick as u64
    }

    /// Returns the tick spacing of the pool.
    /// 
    /// # Arguments
    /// * `manager` - Reference to the tick manager
    /// 
    /// # Returns
    /// The tick spacing as a u32 value
    public fun tick_spacing(manager: &TickManager): u32 {
        manager.tick_spacing
    }
    
    /// Attempts to borrow a tick at the specified index.
    /// 
    /// # Arguments
    /// * `manager` - Reference to the tick manager
    /// * `tick_index` - Index of the tick to borrow
    /// 
    /// # Returns
    /// Option containing the tick if it exists, none otherwise
    public(package) fun try_borrow_tick(manager: &TickManager, tick_index: integer_mate::i32::I32): std::option::Option<Tick> {
        let score = tick_score(tick_index);
        if (!move_stl::skip_list::contains<Tick>(&manager.ticks, score)) {
            return std::option::none<Tick>()
        };
        std::option::some<Tick>(*move_stl::skip_list::borrow<Tick>(&manager.ticks, score))
    }

    /// Updates a tick's state based on liquidity changes.
    /// 
    /// # Arguments
    /// * `tick` - Mutable reference to the tick
    /// * `current_tick_index` - Current tick index in the pool
    /// * `liquidity` - Amount of liquidity to update
    /// * `is_lower_initialized` - Whether this is a newly initialized lower tick
    /// * `is_add` - Whether to add (true) or remove (false) liquidity
    /// * `is_upper` - Whether this is an upper tick
    /// * `fee_growth_global_a` - Global fee growth for token A
    /// * `fee_growth_global_b` - Global fee growth for token B
    /// * `points_growth_global` - Global points growth
    /// * `rewards_growth_global` - Vector of global rewards growth
    /// * `fullsail_distribution_growth_global` - Global FULLSAIL distribution growth
    /// 
    /// # Returns
    /// Updated gross liquidity value
    /// 
    /// # Abort Conditions
    /// * If adding liquidity would cause overflow (error code: 0)
    /// * If removing more liquidity than available (error code: 1)
    fun update_by_liquidity(
        tick: &mut Tick,
        current_tick_index: integer_mate::i32::I32,
        liquidity: u128,
        is_lower_initialized: bool,
        is_add: bool,
        is_upper: bool,
        fee_growth_global_a: u128,
        fee_growth_global_b: u128,
        points_growth_global: u128,
        rewards_growth_global: vector<u128>,
        fullsail_distribution_growth_global: u128
    ): u128 {
        let updated_liquidity_gross = if (is_add) {
            assert!(integer_mate::math_u128::add_check(tick.liquidity_gross, liquidity), 0);
            tick.liquidity_gross + liquidity
        } else {
            assert!(tick.liquidity_gross >= liquidity, 1);
            tick.liquidity_gross - liquidity
        };
        if (updated_liquidity_gross == 0) {
            return 0
        };
        let (points_growth_outside, fullsail_growth_outside, fee_growth_outside_a, fee_growth_outside_b, rewards_growth_outside) = if (is_lower_initialized) {
            let (fee_outside_a, fee_outside_b, rewards_outside, points_outside, fullsail_outside) = if (integer_mate::i32::lt(current_tick_index, tick.index)) {
                (0, 0, default_rewards_growth_outside(std::vector::length<u128>(&rewards_growth_global)), 0, 0)
            } else {
                (fee_growth_global_a, fee_growth_global_b, rewards_growth_global, points_growth_global, fullsail_distribution_growth_global)
            };
            (points_outside, fullsail_outside, fee_outside_a, fee_outside_b, rewards_outside)
        } else {
            (tick.points_growth_outside, tick.fullsail_distribution_growth_outside, tick.fee_growth_outside_a, tick.fee_growth_outside_b, tick.rewards_growth_outside)
        };
        let (liquidity_delta_result, overflow_detected) = if (is_add) {
            let (delta_value_add, overflow_flag_add) = if (is_upper) {
                let (subtraction_result_add, subtraction_overflow_add) = integer_mate::i128::overflowing_sub(
                    tick.liquidity_net,
                    integer_mate::i128::from(liquidity)
                );
                (subtraction_result_add, subtraction_overflow_add)
            } else {
                let (addition_result_add, addition_overflow_add) = integer_mate::i128::overflowing_add(
                    tick.liquidity_net,
                    integer_mate::i128::from(liquidity)
                );
                (addition_result_add, addition_overflow_add)
            };
            (delta_value_add, overflow_flag_add)
        } else {
            let (delta_value_sub, overflow_flag_sub) = if (is_upper) {
                let (addition_result_sub, addition_overflow_sub) = integer_mate::i128::overflowing_add(
                    tick.liquidity_net,
                    integer_mate::i128::from(liquidity)
                );
                (addition_result_sub, addition_overflow_sub)
            } else {
                let (subtraction_result_sub, subtraction_overflow_sub) = integer_mate::i128::overflowing_sub(
                    tick.liquidity_net,
                    integer_mate::i128::from(liquidity)
                );
                (subtraction_result_sub, subtraction_overflow_sub)
            };
            (delta_value_sub, overflow_flag_sub)
        };
        if (overflow_detected) {
            abort 0
        };
        tick.liquidity_gross = updated_liquidity_gross;
        tick.liquidity_net = liquidity_delta_result;
        tick.fee_growth_outside_a = fee_growth_outside_a;
        tick.fee_growth_outside_b = fee_growth_outside_b;
        tick.rewards_growth_outside = rewards_growth_outside;
        tick.points_growth_outside = points_growth_outside;
        tick.fullsail_distribution_growth_outside = fullsail_growth_outside;
        updated_liquidity_gross
    }

    /// Updates the FULLSAIL stake for a tick.
    /// 
    /// # Arguments
    /// * `tick_manager` - Mutable reference to the tick manager
    /// * `tick_index` - Index of the tick to update
    /// * `liquidity_delta` - Change in liquidity
    /// * `is_decrease` - Whether this is a decrease in stake
    /// 
    /// # Implementation Details
    /// * For decrease: subtracts liquidity_delta from staked liquidity
    /// * For increase: adds liquidity_delta to staked liquidity
    public(package) fun update_fullsail_stake(
        tick_manager: &mut TickManager,
        tick_index: integer_mate::i32::I32,
        liquidity_delta: integer_mate::i128::I128,
        is_decrease: bool
    ) {
        let tick = move_stl::skip_list::borrow_mut<Tick>(&mut tick_manager.ticks, tick_score(tick_index));
        if (is_decrease) {
            tick.fullsail_distribution_staked_liquidity_net = integer_mate::i128::wrapping_sub(
                tick.fullsail_distribution_staked_liquidity_net,
                liquidity_delta
            );
        } else {
            tick.fullsail_distribution_staked_liquidity_net = integer_mate::i128::wrapping_add(
                tick.fullsail_distribution_staked_liquidity_net,
                liquidity_delta
            );
        };
    }

    #[test_only]
    public(package) fun update_by_liquidity_test(
        tick: &mut Tick,
        current_tick_index: integer_mate::i32::I32,
        liquidity: u128,
        is_lower_initialized: bool,
        is_add: bool,
        is_upper: bool,
        fee_growth_global_a: u128,
        fee_growth_global_b: u128,
        points_growth_global: u128,
        rewards_growth_global: vector<u128>,
        fullsail_distribution_growth_global: u128
    ): u128 {
        update_by_liquidity(
            tick,
            current_tick_index,
            liquidity,
            is_lower_initialized,
            is_add,
            is_upper,
            fee_growth_global_a,
            fee_growth_global_b,
            points_growth_global,
            rewards_growth_global,
            fullsail_distribution_growth_global
        )
    }
}

