/// The pool module serves as the core component of the CLMM (Concentrated Liquidity Market Maker) system.
/// It manages liquidity pools, handles swaps, and coordinates various aspects of the DEX including
/// fee collection, reward distribution, and position management.
///
/// Core Functions:
/// - Liquidity Management: Handles adding and removing liquidity from positions
/// - Swap Execution: Processes token swaps with concentrated liquidity
/// - Fee Management: Tracks and collects trading fees
/// - Reward Distribution: Manages reward rates and distribution
/// - Position Tracking: Maintains information about liquidity positions
///
/// Integration with Other Components:
/// - Tick Manager: Manages price ticks and their associated data
/// - Rewarder Manager: Handles reward distribution logic
/// - Position Manager: Tracks and manages liquidity positions
///
/// The pool enables efficient trading with concentrated liquidity while providing
/// infrastructure for fee collection and reward distribution to liquidity providers.

module clmm_pool::pool {
    public struct POOL has drop {}

    /// The main pool structure that represents a liquidity pool for a specific token pair.
    /// This structure maintains the state of the pool including balances, fees, and various
    /// management components.
    /// 
    /// # Fields
    /// * `id` - The unique identifier for this shared object
    /// * `coin_a`, `coin_b` - Balances of the two tokens in the pool
    /// * `tick_spacing` - The minimum tick spacing for positions
    /// * `fee_rate` - The fee rate for swaps (in basis points)
    /// * `liquidity` - The total liquidity in the pool
    /// * `current_sqrt_price` - The current square root price
    /// * `current_tick_index` - The current tick index
    /// * `fee_growth_global_a`, `fee_growth_global_b` - Global fee growth for each token
    /// * `fee_protocol_coin_a`, `fee_protocol_coin_b` - Protocol fees collected for each token
    /// * `tick_manager` - Manager for price ticks
    /// * `rewarder_manager` - Manager for reward distribution
    /// * `position_manager` - Manager for liquidity positions
    /// * `is_pause` - Whether the pool is paused
    /// * `index` - Pool index in the system
    /// * `url` - URL for pool metadata
    /// * `unstaked_liquidity_fee_rate` - Fee rate for unstaked liquidity
    /// * `fullsail_distribution_*` fields - Various fields for fullsail distribution system
    /// * `volume_usd_*` fields - Volume tracking in USD
    /// * `feed_id_*` fields - Price feed IDs for tokens
    /// * `auto_calculation_volumes` - Whether volumes are calculated automatically
    public struct Pool<phantom CoinTypeA, phantom CoinTypeB> has store, key {
        id: sui::object::UID,
        coin_a: sui::balance::Balance<CoinTypeA>,
        coin_b: sui::balance::Balance<CoinTypeB>,
        tick_spacing: u32,
        fee_rate: u64,
        liquidity: u128,
        current_sqrt_price: u128,
        current_tick_index: integer_mate::i32::I32,
        fee_growth_global_a: u128,
        fee_growth_global_b: u128,
        fee_protocol_coin_a: u64,
        fee_protocol_coin_b: u64,
        tick_manager: clmm_pool::tick::TickManager,
        rewarder_manager: clmm_pool::rewarder::RewarderManager,
        position_manager: clmm_pool::position::PositionManager,
        is_pause: bool,
        index: u64,
        url: std::string::String,
        unstaked_liquidity_fee_rate: u64,
        fullsail_distribution_gauger_id: std::option::Option<sui::object::ID>,
        fullsail_distribution_growth_global: u128,
        fullsail_distribution_rate: u128,
        fullsail_distribution_reserve: u64,
        fullsail_distribution_period_finish: u64,
        fullsail_distribution_rollover: u64,
        fullsail_distribution_last_updated: u64,
        fullsail_distribution_staked_liquidity: u128,
        fullsail_distribution_gauger_fee: PoolFee,
        volume: PoolVolume,
        feed_id: PoolFeedId,
        auto_calculation_volumes: bool,
    }

    /// Structure representing fees collected by the pool for each token.
    /// 
    /// # Fields
    /// * `coin_a` - Fee amount for token A
    /// * `coin_b` - Fee amount for token B
    public struct PoolFee has drop, store {
        coin_a: u64,
        coin_b: u64,
    }

    /// Structure representing the volume of tokens in USD for the pool.
    /// 
    /// # Fields
    /// * `volume_usd_coin_a` - Volume of token A in USD
    /// * `volume_usd_coin_b` - Volume of token B in USD
    public struct PoolVolume has drop, store {
        volume_usd_coin_a: u128,
        volume_usd_coin_b: u128,
    }

    /// Structure representing the price feed IDs for the tokens in the pool.
    /// 
    /// # Fields
    /// * `feed_id_coin_a` - Price feed ID for token A
    /// * `feed_id_coin_b` - Price feed ID for token B
    public struct PoolFeedId has drop, store {
        feed_id_coin_a: address,
        feed_id_coin_b: address,
    }

    /// Structure representing the result of a swap operation.
    /// 
    /// # Fields
    /// * `amount_in` - Amount of input token
    /// * `amount_out` - Amount of output token
    /// * `fee_amount` - Total fee amount
    /// * `protocol_fee_amount` - Protocol fee amount
    /// * `ref_fee_amount` - Referral fee amount
    /// * `gauge_fee_amount` - Gauge fee amount
    /// * `steps` - Number of steps taken in the swap
    public struct SwapResult has copy, drop {
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
        protocol_fee_amount: u64,
        ref_fee_amount: u64,
        gauge_fee_amount: u64,
        steps: u64,
    }

    /// Structure representing a flash swap receipt.
    /// 
    /// # Fields
    /// * `pool_id` - ID of the pool where the swap occurred
    /// * `a2b` - Whether the swap was from token A to B
    /// * `partner_id` - ID of the partner involved
    /// * `pay_amount` - Amount to be paid
    /// * `fee_amount` - Fee amount
    /// * `protocol_fee_amount` - Protocol fee amount
    /// * `ref_fee_amount` - Referral fee amount
    /// * `gauge_fee_amount` - Gauge fee amount
    public struct FlashSwapReceipt<phantom CoinTypeA, phantom CoinTypeB> {
        pool_id: sui::object::ID,
        a2b: bool,
        partner_id: sui::object::ID,
        pay_amount: u64,
        fee_amount: u64,
        protocol_fee_amount: u64,
        ref_fee_amount: u64,
        gauge_fee_amount: u64,
    }

    /// Structure representing a receipt for adding liquidity.
    /// 
    /// # Fields
    /// * `pool_id` - ID of the pool where liquidity was added
    /// * `amount_a` - Amount of token A added
    /// * `amount_b` - Amount of token B added
    public struct AddLiquidityReceipt<phantom CoinTypeA, phantom CoinTypeB> {
        pool_id: sui::object::ID,
        amount_a: u64,
        amount_b: u64,
    }

    /// Structure representing a calculated swap result with detailed information.
    /// 
    /// # Fields
    /// * `amount_in` - Amount of input token
    /// * `amount_out` - Amount of output token
    /// * `fee_amount` - Total fee amount
    /// * `fee_rate` - Fee rate applied
    /// * `ref_fee_amount` - Referral fee amount
    /// * `gauge_fee_amount` - Gauge fee amount
    /// * `protocol_fee_amount` - Protocol fee amount
    /// * `after_sqrt_price` - Square root price after swap
    /// * `is_exceed` - Whether the swap exceeded limits
    /// * `step_results` - Results of individual swap steps
    public struct CalculatedSwapResult has copy, drop, store {
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
        fee_rate: u64,
        ref_fee_amount: u64,
        gauge_fee_amount: u64,
        protocol_fee_amount: u64,
        after_sqrt_price: u128,
        is_exceed: bool,
        step_results: vector<SwapStepResult>,
    }

    /// Structure representing the result of a single swap step.
    /// 
    /// # Fields
    /// * `current_sqrt_price` - Current square root price
    /// * `target_sqrt_price` - Target square root price
    /// * `current_liquidity` - Current liquidity
    /// * `amount_in` - Amount of input token
    /// * `amount_out` - Amount of output token
    /// * `fee_amount` - Fee amount for this step
    /// * `remainder_amount` - Remaining amount after this step
    public struct SwapStepResult has copy, drop, store {
        current_sqrt_price: u128,
        target_sqrt_price: u128,
        current_liquidity: u128,
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
        remainder_amount: u64,
    }

    /// Event emitted when a new position is opened.
    /// 
    /// # Fields
    /// * `pool` - ID of the pool
    /// * `tick_lower` - Lower tick of the position
    /// * `tick_upper` - Upper tick of the position
    /// * `position` - ID of the new position
    public struct OpenPositionEvent has copy, drop, store {
        pool: sui::object::ID,
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32,
        position: sui::object::ID,
    }

    /// Event emitted when a position is closed.
    /// 
    /// # Fields
    /// * `pool` - ID of the pool
    /// * `position` - ID of the closed position
    public struct ClosePositionEvent has copy, drop, store {
        pool: sui::object::ID,
        position: sui::object::ID,
    }

    /// Event emitted when liquidity is added to a position.
    /// 
    /// # Fields
    /// * `pool` - ID of the pool
    /// * `position` - ID of the position
    /// * `tick_lower` - Lower tick of the position
    /// * `tick_upper` - Upper tick of the position
    /// * `liquidity` - Amount of liquidity added
    /// * `after_liquidity` - Total liquidity after addition
    /// * `amount_a` - Amount of token A added
    /// * `amount_b` - Amount of token B added
    public struct AddLiquidityEvent has copy, drop, store {
        pool: sui::object::ID,
        position: sui::object::ID,
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32,
        liquidity: u128,
        after_liquidity: u128,
        amount_a: u64,
        amount_b: u64,
    }

    /// Event emitted when liquidity is removed from a position.
    /// 
    /// # Fields
    /// * `pool` - ID of the pool
    /// * `position` - ID of the position
    /// * `tick_lower` - Lower tick of the position
    /// * `tick_upper` - Upper tick of the position
    /// * `liquidity` - Amount of liquidity removed
    /// * `after_liquidity` - Total liquidity after removal
    /// * `amount_a` - Amount of token A removed
    /// * `amount_b` - Amount of token B removed
    public struct RemoveLiquidityEvent has copy, drop, store {
        pool: sui::object::ID,
        position: sui::object::ID,
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32,
        liquidity: u128,
        after_liquidity: u128,
        amount_a: u64,
        amount_b: u64,
    }

    /// Event emitted when a swap occurs.
    /// 
    /// # Fields
    /// * `atob` - Whether the swap was from token A to B
    /// * `pool` - ID of the pool
    /// * `partner` - ID of the partner
    /// * `amount_in` - Amount of input token
    /// * `amount_out` - Amount of output token
    /// * `fullsail_fee_amount` - Fullsail fee amount
    /// * `protocol_fee_amount` - Protocol fee amount
    /// * `ref_fee_amount` - Referral fee amount
    /// * `fee_amount` - Total fee amount
    /// * `vault_a_amount` - Amount in vault A
    /// * `vault_b_amount` - Amount in vault B
    /// * `before_sqrt_price` - Square root price before swap
    /// * `after_sqrt_price` - Square root price after swap
    /// * `steps` - Number of steps in the swap
    public struct SwapEvent has copy, drop, store {
        atob: bool,
        pool: sui::object::ID,
        partner: sui::object::ID,
        amount_in: u64,
        amount_out: u64,
        fullsail_fee_amount: u64,
        protocol_fee_amount: u64,
        ref_fee_amount: u64,
        fee_amount: u64,
        vault_a_amount: u64,
        vault_b_amount: u64,
        before_sqrt_price: u128,
        after_sqrt_price: u128,
        steps: u64,
    }

    /// Event emitted when protocol fees are collected.
    /// 
    /// # Fields
    /// * `pool` - ID of the pool
    /// * `amount_a` - Amount of token A collected
    /// * `amount_b` - Amount of token B collected
    public struct CollectProtocolFeeEvent has copy, drop, store {
        pool: sui::object::ID,
        amount_a: u64,
        amount_b: u64,
    }

    /// Event emitted when fees are collected from a position.
    /// 
    /// # Fields
    /// * `position` - ID of the position
    /// * `pool` - ID of the pool
    /// * `amount_a` - Amount of token A collected
    /// * `amount_b` - Amount of token B collected
    public struct CollectFeeEvent has copy, drop, store {
        position: sui::object::ID,
        pool: sui::object::ID,
        amount_a: u64,
        amount_b: u64,
    }

    /// Event emitted when the fee rate is updated.
    /// 
    /// # Fields
    /// * `pool` - ID of the pool
    /// * `old_fee_rate` - Previous fee rate
    /// * `new_fee_rate` - New fee rate
    public struct UpdateFeeRateEvent has copy, drop, store {
        pool: sui::object::ID,
        old_fee_rate: u64,
        new_fee_rate: u64,
    }

    /// Event emitted when emission rates are updated.
    /// 
    /// # Fields
    /// * `pool` - ID of the pool
    /// * `rewarder_type` - Type of rewarder
    /// * `emissions_per_second` - New emission rate
    public struct UpdateEmissionEvent has copy, drop, store {
        pool: sui::object::ID,
        rewarder_type: std::type_name::TypeName,
        emissions_per_second: u128,
    }

    /// Event emitted when a new rewarder is added.
    /// 
    /// # Fields
    /// * `pool` - ID of the pool
    /// * `rewarder_type` - Type of rewarder added
    public struct AddRewarderEvent has copy, drop, store {
        pool: sui::object::ID,
        rewarder_type: std::type_name::TypeName,
    }

    /// Event emitted when rewards are collected.
    /// 
    /// # Fields
    /// * `position` - ID of the position
    /// * `pool` - ID of the pool
    /// * `amount` - Amount of rewards collected
    public struct CollectRewardEvent has copy, drop, store {
        position: sui::object::ID,
        pool: sui::object::ID,
        amount: u64,
    }

    /// Event emitted when gauge fees are collected.
    /// 
    /// # Fields
    /// * `pool` - ID of the pool
    /// * `amount_a` - Amount of token A collected
    /// * `amount_b` - Amount of token B collected
    public struct CollectGaugeFeeEvent has copy, drop, store {
        pool: sui::object::ID,
        amount_a: u64,
        amount_b: u64,
    }

    /// Event emitted when the unstaked liquidity fee rate is updated.
    /// 
    /// # Fields
    /// * `pool` - ID of the pool
    /// * `old_fee_rate` - Previous fee rate
    /// * `new_fee_rate` - New fee rate
    public struct UpdateUnstakedLiquidityFeeRateEvent has copy, drop, store {
        pool: sui::object::ID,
        old_fee_rate: u64,
        new_fee_rate: u64,
    }

    /// Creates a new liquidity pool with the specified parameters.
    /// This function initializes all the necessary components of a pool including
    /// tick management, reward distribution, and position tracking.
    ///
    /// # Arguments
    /// * `tick_spacing` - The minimum tick spacing for positions in this pool
    /// * `initial_sqrt_price` - The initial square root price for the pool
    /// * `fee_rate` - The fee rate for swaps (in basis points)
    /// * `pool_url` - URL containing pool metadata
    /// * `pool_index` - Index of this pool in the system
    /// * `feed_id_coin_a` - Price feed ID for token A
    /// * `feed_id_coin_b` - Price feed ID for token B
    /// * `auto_calculation_volumes` - Whether volumes should be calculated automatically
    /// * `clock` - The system clock for timestamp tracking
    /// * `ctx` - Transaction context for object creation
    ///
    /// # Returns
    /// A new Pool instance with all fields initialized to their default values
    public(package) fun new<CoinTypeA, CoinTypeB>(
        tick_spacing: u32,
        initial_sqrt_price: u128,
        fee_rate: u64,
        pool_url: std::string::String,
        pool_index: u64,
        feed_id_coin_a: address,
        feed_id_coin_b: address,
        auto_calculation_volumes: bool,
        clock: &sui::clock::Clock,
        ctx: &mut sui::tx_context::TxContext
    ): Pool<CoinTypeA, CoinTypeB> {
        let initial_pool_fee = PoolFee {
            coin_a: 0,
            coin_b: 0,
        };
        let initial_pool_volume = PoolVolume {
            volume_usd_coin_a: 0,
            volume_usd_coin_b: 0,
        };
        let initial_pool_feed_id = PoolFeedId {
            feed_id_coin_a,
            feed_id_coin_b,
        };
        Pool<CoinTypeA, CoinTypeB> {
            id: sui::object::new(ctx),
            coin_a: sui::balance::zero<CoinTypeA>(),
            coin_b: sui::balance::zero<CoinTypeB>(),
            tick_spacing,
            fee_rate,
            liquidity: 0,
            current_sqrt_price: initial_sqrt_price,
            current_tick_index: clmm_pool::tick_math::get_tick_at_sqrt_price(initial_sqrt_price),
            fee_growth_global_a: 0,
            fee_growth_global_b: 0,
            fee_protocol_coin_a: 0,
            fee_protocol_coin_b: 0,
            tick_manager: clmm_pool::tick::new(tick_spacing, sui::clock::timestamp_ms(clock), ctx),
            rewarder_manager: clmm_pool::rewarder::new(),
            position_manager: clmm_pool::position::new(tick_spacing, ctx),
            is_pause: false,
            index: pool_index,
            url: pool_url,
            unstaked_liquidity_fee_rate: clmm_pool::config::default_unstaked_fee_rate(),
            fullsail_distribution_gauger_id: std::option::none<sui::object::ID>(),
            fullsail_distribution_growth_global: 0,
            fullsail_distribution_rate: 0,
            fullsail_distribution_reserve: 0,
            fullsail_distribution_period_finish: 0,
            fullsail_distribution_rollover: 0,
            fullsail_distribution_last_updated: sui::clock::timestamp_ms(clock) / 1000,
            fullsail_distribution_staked_liquidity: 0,
            fullsail_distribution_gauger_fee: initial_pool_fee,
            volume: initial_pool_volume,
            feed_id: initial_pool_feed_id,
            auto_calculation_volumes,
        }
    }
    
    /// Calculates the amount of tokens required for a given liquidity amount within a price range.
    /// This function handles three different scenarios based on the current tick position:
    /// 1. Current tick below the lower tick
    /// 2. Current tick between lower and upper ticks
    /// 3. Current tick above the upper tick
    ///
    /// # Arguments
    /// * `tick_lower` - The lower tick of the price range
    /// * `tick_upper` - The upper tick of the price range
    /// * `current_tick` - The current tick of the pool
    /// * `current_sqrt_price` - The current square root price
    /// * `liquidity` - The amount of liquidity to calculate for
    /// * `round_up` - Whether to round up the calculated amounts
    ///
    /// # Returns
    /// A tuple containing (amount_a, amount_b) where:
    /// * `amount_a` - The amount of token A required
    /// * `amount_b` - The amount of token B required
    public fun get_amount_by_liquidity(
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32,
        current_tick: integer_mate::i32::I32,
        current_sqrt_price: u128,
        liquidity: u128,
        round_up: bool
    ): (u64, u64) {
        if (liquidity == 0) {
            return (0, 0)
        };
        if (integer_mate::i32::lt(current_tick, tick_lower)) {
            (clmm_pool::clmm_math::get_delta_a(
                clmm_pool::tick_math::get_sqrt_price_at_tick(tick_lower),
                clmm_pool::tick_math::get_sqrt_price_at_tick(tick_upper),
                liquidity,
                round_up
            ), 0)
        } else {
            let (amount_a, amount_b) = if (integer_mate::i32::lt(current_tick, tick_upper)) {
                (clmm_pool::clmm_math::get_delta_a(
                    current_sqrt_price,
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_upper),
                    liquidity,
                    round_up
                ), clmm_pool::clmm_math::get_delta_b(
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_lower),
                    current_sqrt_price,
                    liquidity,
                    round_up
                ))
            } else {
                (0, clmm_pool::clmm_math::get_delta_b(
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_lower),
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_upper),
                    liquidity,
                    round_up
                ))
            };
            (amount_a, amount_b)
        }
    }
    
    /// Returns the fee rate for unstaked liquidity in the pool.
    /// This rate is applied to liquidity that is not staked in a gauge.
    ///
    /// # Arguments
    /// * `pool` - The pool to get the fee rate from
    ///
    /// # Returns
    /// The fee rate for unstaked liquidity (in basis points)
    public fun unstaked_liquidity_fee_rate<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): u64 {
        pool.unstaked_liquidity_fee_rate
    }

    /// Returns a reference to the position information for a given position ID.
    ///
    /// # Arguments
    /// * `pool` - The pool containing the position
    /// * `position_id` - The ID of the position to get information for
    ///
    /// # Returns
    /// A reference to the PositionInfo struct for the specified position
    public fun borrow_position_info<CoinTypeA, CoinTypeB>(
        pool: &Pool<CoinTypeA, CoinTypeB>,
        position_id: sui::object::ID
    ): &clmm_pool::position::PositionInfo {
        clmm_pool::position::borrow_position_info(&pool.position_manager, position_id)
    }

    /// Closes a position in the pool and emits a ClosePositionEvent.
    /// This function can only be called if the pool is not paused.
    ///
    /// # Arguments
    /// * `config` - The global configuration for the pool
    /// * `pool` - The pool containing the position to close
    /// * `position` - The position to close
    ///
    /// # Aborts
    /// If the pool is paused
    public fun close_position<CoinTypeA, CoinTypeB>(
        config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        position: clmm_pool::position::Position
    ) {
        clmm_pool::config::checked_package_version(config);
        assert!(!pool.is_pause, 13);
        let position_id = sui::object::id<clmm_pool::position::Position>(&position);
        clmm_pool::position::close_position(&mut pool.position_manager, position);
        let event = ClosePositionEvent {
            pool: sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool),
            position: position_id,
        };
        sui::event::emit<ClosePositionEvent>(event);
    }

    /// Fetches information for multiple positions from the pool.
    ///
    /// # Arguments
    /// * `pool` - The pool containing the positions
    /// * `position_ids` - Vector of position IDs to fetch information for
    /// * `limit` - Maximum number of positions to fetch
    ///
    /// # Returns
    /// Vector of PositionInfo structs for the requested positions
    public fun fetch_positions<CoinTypeA, CoinTypeB>(
        pool: &Pool<CoinTypeA, CoinTypeB>,
        position_ids: vector<sui::object::ID>,
        limit: u64
    ): vector<clmm_pool::position::PositionInfo> {
        clmm_pool::position::fetch_positions(&pool.position_manager, position_ids, limit)
    }

    /// Checks if a position exists in the pool.
    ///
    /// # Arguments
    /// * `pool` - The pool to check
    /// * `position_id` - The ID of the position to check
    ///
    /// # Returns
    /// true if the position exists, false otherwise
    public fun is_position_exist<CoinTypeA, CoinTypeB>(
        pool: &Pool<CoinTypeA, CoinTypeB>, 
        position_id: sui::object::ID
    ): bool {
        clmm_pool::position::is_position_exist(&pool.position_manager, position_id)
    }

    /// Returns the total liquidity in the pool.
    ///
    /// # Arguments
    /// * `pool` - The pool to get liquidity from
    ///
    /// # Returns
    /// The total liquidity in the pool
    public fun liquidity<CoinTypeA, CoinTypeB>(
        pool: &Pool<CoinTypeA, CoinTypeB>
    ): u128 {
        pool.liquidity
    }

    /// Marks a position as staked in the pool.
    /// This function can only be called if the pool is not paused.
    ///
    /// # Arguments
    /// * `pool` - The pool containing the position
    /// * `gauge_cap` - The gauge capability for the position
    /// * `position_id` - The ID of the position to mark as staked
    ///
    /// # Aborts
    /// If the pool is paused
    public fun mark_position_staked<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        gauge_cap: &gauge_cap::gauge_cap::GaugeCap,
        position_id: sui::object::ID
    ) {
        assert!(!pool.is_pause, 13);
        check_gauge_cap<CoinTypeA, CoinTypeB>(pool, gauge_cap);
        clmm_pool::position::mark_position_staked(&mut pool.position_manager, position_id, true);
    }

    /// Opens a new position in the pool with the specified tick range.
    /// This function can only be called if the pool is not paused.
    ///
    /// # Arguments
    /// * `global_config` - The global configuration for the pool
    /// * `pool` - The pool to open the position in
    /// * `tick_lower` - The lower tick of the position
    /// * `tick_upper` - The upper tick of the position
    /// * `ctx` - Transaction context for object creation
    ///
    /// # Returns
    /// A new Position instance
    ///
    /// # Aborts
    /// If the pool is paused
    public fun open_position<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        tick_lower: u32,
        tick_upper: u32,
        ctx: &mut sui::tx_context::TxContext
    ): clmm_pool::position::Position {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        let tick_lower_i32 = integer_mate::i32::from_u32(tick_lower);
        let tick_upper_i32 = integer_mate::i32::from_u32(tick_upper);
        let pool_id = sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool);
        let position = clmm_pool::position::open_position<CoinTypeA, CoinTypeB>(
            &mut pool.position_manager,
            pool_id,
            pool.index,
            pool.url,
            tick_lower_i32,
            tick_upper_i32,
            ctx
        );
        let event = OpenPositionEvent {
            pool: pool_id,
            tick_lower: tick_lower_i32,
            tick_upper: tick_upper_i32,
            position: sui::object::id<clmm_pool::position::Position>(&position),
        };
        sui::event::emit<OpenPositionEvent>(event);
        position
    }

    /// Updates the emission rate for rewards in the pool.
    /// This function can only be called by the rewarder manager role and if the pool is not paused.
    ///
    /// # Arguments
    /// * `global_config` - The global configuration for the pool
    /// * `pool` - The pool to update emission for
    /// * `rewarder_global_vault` - The global vault for reward distribution
    /// * `emissions_per_second` - The new emission rate in tokens per second
    /// * `clock` - The system clock for timestamp tracking
    /// * `ctx` - Transaction context for sender verification
    ///
    /// # Aborts
    /// * If the pool is paused
    /// * If the caller is not the rewarder manager role
    public fun update_emission<CoinTypeA, CoinTypeB, RewardCoinType>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        rewarder_global_vault: &clmm_pool::rewarder::RewarderGlobalVault,
        emissions_per_second: u128,
        clock: &sui::clock::Clock,
        ctx: &mut sui::tx_context::TxContext
    ) {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        clmm_pool::config::check_rewarder_manager_role(global_config, sui::tx_context::sender(ctx));
        clmm_pool::rewarder::update_emission<RewardCoinType>(
            rewarder_global_vault,
            &mut pool.rewarder_manager,
            pool.liquidity,
            emissions_per_second,
            sui::clock::timestamp_ms(clock) / 1000
        );
        let event = UpdateEmissionEvent {
            pool: sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool),
            rewarder_type: std::type_name::get<RewardCoinType>(),
            emissions_per_second: emissions_per_second,
        };
        sui::event::emit<UpdateEmissionEvent>(event);
    }

    /// Returns a reference to a specific tick in the pool.
    ///
    /// # Arguments
    /// * `pool` - The pool containing the tick
    /// * `tick_index` - The index of the tick to retrieve
    ///
    /// # Returns
    /// A reference to the requested Tick struct
    public fun borrow_tick<CoinTypeA, CoinTypeB>(
        pool: &Pool<CoinTypeA, CoinTypeB>,
        tick_index: integer_mate::i32::I32
    ): &clmm_pool::tick::Tick {
        clmm_pool::tick::borrow_tick(&pool.tick_manager, tick_index)
    }

    /// Fetches multiple ticks from the pool based on their indexes.
    ///
    /// # Arguments
    /// * `pool` - The pool containing the ticks
    /// * `tick_indexes` - Vector of tick indexes to fetch
    /// * `limit` - Maximum number of ticks to fetch
    ///
    /// # Returns
    /// Vector of Tick structs for the requested indexes
    public fun fetch_ticks<CoinTypeA, CoinTypeB>(
        pool: &Pool<CoinTypeA, CoinTypeB>, 
        tick_indexes: vector<u32>,
        limit: u64
    ): vector<clmm_pool::tick::Tick> {
        clmm_pool::tick::fetch_ticks(&pool.tick_manager, tick_indexes, limit)
    }

    /// Returns the index of the pool in the system.
    ///
    /// # Arguments
    /// * `pool` - The pool to get the index from
    ///
    /// # Returns
    /// The pool's index as a u64
    public fun index<CoinTypeA, CoinTypeB>(
        pool: &Pool<CoinTypeA, CoinTypeB>
    ): u64 {
        pool.index
    }
    
    /// Adds liquidity to a position in the pool.
    /// This function can only be called if the pool is not paused and the delta liquidity is non-zero.
    ///
    /// # Arguments
    /// * `global_config` - The global configuration for the pool
    /// * `pool` - The pool to add liquidity to
    /// * `position` - The position to add liquidity to
    /// * `delta_liquidity` - The amount of liquidity to add
    /// * `clock` - The system clock for timestamp tracking
    ///
    /// # Returns
    /// An AddLiquidityReceipt containing the results of the operation
    ///
    /// # Aborts
    /// * If delta_liquidity is zero
    /// * If the pool is paused
    public fun add_liquidity<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        position: &mut clmm_pool::position::Position,
        delta_liquidity: u128,
        clock: &sui::clock::Clock
    ): AddLiquidityReceipt<CoinTypeA, CoinTypeB> {
        clmm_pool::config::checked_package_version(global_config);
        assert!(delta_liquidity != 0, 3);
        add_liquidity_internal<CoinTypeA, CoinTypeB>(
            pool,
            position,
            false,
            delta_liquidity,
            0,
            false,
            sui::clock::timestamp_ms(clock) / 1000
        )
    }
    
    /// Adds liquidity to a position with a fixed amount of one token.
    /// This function allows adding liquidity by specifying the exact amount of either token A or B.
    ///
    /// # Arguments
    /// * `global_config` - The global configuration for the pool
    /// * `pool` - The pool to add liquidity to
    /// * `position` - The position to add liquidity to
    /// * `amount_in` - The fixed amount of tokens to add
    /// * `fix_amount_a` - If true, amount_in represents token A, otherwise token B
    /// * `clock` - The system clock for timestamp tracking
    ///
    /// # Returns
    /// An AddLiquidityReceipt containing the results of the operation
    ///
    /// # Aborts
    /// * If amount_in is zero
    /// * If the pool is paused
    /// * If the position is not valid for this pool
    public fun add_liquidity_fix_coin<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        position: &mut clmm_pool::position::Position,
        amount_in: u64,
        fix_amount_a: bool,
        clock: &sui::clock::Clock
    ): AddLiquidityReceipt<CoinTypeA, CoinTypeB> {
        clmm_pool::config::checked_package_version(global_config);
        assert!(amount_in > 0, 0);
        add_liquidity_internal<CoinTypeA, CoinTypeB>(
            pool,
            position,
            true,
            0,
            amount_in,
            fix_amount_a,
            sui::clock::timestamp_ms(clock) / 1000
        )
    }
    
    /// Internal function for adding liquidity to a position.
    /// This function handles the core logic of adding liquidity, including calculations
    /// for both fixed liquidity and fixed token amount scenarios.
    ///
    /// # Arguments
    /// * `pool` - The pool to add liquidity to
    /// * `position` - The position to add liquidity to
    /// * `is_fix_amount` - If true, uses amount_in as the fixed token amount, otherwise uses liquidity_delta
    /// * `liquidity_delta` - The amount of liquidity to add (used when is_fix_amount is false)
    /// * `amount_in` - The fixed amount of tokens to add (used when is_fix_amount is true)
    /// * `is_fix_amount_a` - If true, amount_in represents token A, otherwise token B
    /// * `timestamp` - Current timestamp for reward calculations
    ///
    /// # Returns
    /// An AddLiquidityReceipt containing the results of the operation
    ///
    /// # Aborts
    /// * If the pool is paused
    /// * If the position is not valid for this pool
    fun add_liquidity_internal<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        position: &mut clmm_pool::position::Position,
        is_fix_amount: bool,
        liquidity_delta: u128,
        amount_in: u64,
        is_fix_amount_a: bool,
        timestamp: u64
    ): AddLiquidityReceipt<CoinTypeA, CoinTypeB> {
        assert!(!pool.is_pause, 13);
        validate_pool_position<CoinTypeA, CoinTypeB>(pool, position);
        clmm_pool::rewarder::settle(&mut pool.rewarder_manager, pool.liquidity, timestamp);

        let (tick_lower, tick_upper) = clmm_pool::position::tick_range(position);

        let (liquidity, amount_a, amount_b) = if (is_fix_amount) {
            let (liquidity_calc, amount_a_calc, amount_b_calc) = clmm_pool::clmm_math::get_liquidity_by_amount(
                tick_lower,
                tick_upper,
                pool.current_tick_index,
                pool.current_sqrt_price,
                amount_in,
                is_fix_amount_a
            );
            (liquidity_calc, amount_a_calc, amount_b_calc)
        } else {
            let (amount_a_calc, amount_b_calc) = clmm_pool::clmm_math::get_amount_by_liquidity(
                tick_lower,
                tick_upper,
                pool.current_tick_index,
                pool.current_sqrt_price,
                liquidity_delta,
                true
            );
            (liquidity_delta, amount_a_calc, amount_b_calc)
        };

        let (fee_growth_a, fee_growth_b, rewards_growth, points_growth, fullsail_growth) = 
            get_all_growths_in_tick_range<CoinTypeA, CoinTypeB>(pool, tick_lower, tick_upper);

        clmm_pool::tick::increase_liquidity(
            &mut pool.tick_manager,
            pool.current_tick_index,
            tick_lower,
            tick_upper,
            liquidity,
            pool.fee_growth_global_a,
            pool.fee_growth_global_b,
            clmm_pool::rewarder::points_growth_global(&pool.rewarder_manager),
            clmm_pool::rewarder::rewards_growth_global(&pool.rewarder_manager),
            pool.fullsail_distribution_growth_global
        );
        if (integer_mate::i32::gte(pool.current_tick_index, tick_lower) && 
            integer_mate::i32::lt(pool.current_tick_index, tick_upper)) {
            assert!(integer_mate::math_u128::add_check(pool.liquidity, liquidity), 1);
            pool.liquidity = pool.liquidity + liquidity;
        };

        let event = AddLiquidityEvent {
            pool: sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool),
            position: sui::object::id<clmm_pool::position::Position>(position),
            tick_lower,
            tick_upper,
            liquidity: liquidity_delta,
            after_liquidity: clmm_pool::position::increase_liquidity(
                &mut pool.position_manager,
                position,
                liquidity,
                fee_growth_a,
                fee_growth_b,
                points_growth,
                rewards_growth,
                fullsail_growth
            ),
            amount_a,
            amount_b,
        };

        sui::event::emit<AddLiquidityEvent>(event);

        AddLiquidityReceipt<CoinTypeA, CoinTypeB> {
            pool_id: sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool),
            amount_a,
            amount_b,
        }
    }

    /// Returns the amounts of tokens required to add liquidity based on the receipt.
    ///
    /// # Arguments
    /// * `receipt` - The AddLiquidityReceipt containing the calculated amounts
    ///
    /// # Returns
    /// A tuple containing (amount_a, amount_b) where:
    /// * `amount_a` - The amount of token A required
    /// * `amount_b` - The amount of token B required
    public fun add_liquidity_pay_amount<CoinTypeA, CoinTypeB>(receipt: &AddLiquidityReceipt<CoinTypeA, CoinTypeB>): (u64, u64) {
        (receipt.amount_a, receipt.amount_b)
    }

    /// Calculates the unstaked fee portion and updates the total amount.
    /// This function applies the unstaked fee rate to calculate the portion of fees
    /// that should be distributed to unstaked liquidity providers.
    ///
    /// # Arguments
    /// * `fee_amount` - The total fee amount to be distributed
    /// * `total_amount` - The total amount before fee distribution
    /// * `unstaked_fee_rate` - The fee rate for unstaked liquidity (in basis points)
    ///
    /// # Returns
    /// A tuple containing (staked_fee, updated_total) where:
    /// * `staked_fee` - The fee amount for staked liquidity
    /// * `updated_total` - The total amount after fee distribution
    fun apply_unstaked_fees(fee_amount: u128, total_amount: u128, unstaked_fee_rate: u64): (u128, u128) {
        let unstaked_fee = integer_mate::full_math_u128::mul_div_ceil(fee_amount, unstaked_fee_rate as u128, 10000);
        (fee_amount - unstaked_fee, total_amount + unstaked_fee)
    }

    /// Returns the current balances of both tokens in the pool.
    ///
    /// # Arguments
    /// * `pool` - The pool to get balances from
    ///
    /// # Returns
    /// A tuple containing (balance_a, balance_b) where:
    /// * `balance_a` - The current balance of token A in the pool
    /// * `balance_b` - The current balance of token B in the pool
    public fun balances<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): (u64, u64) {
        (sui::balance::value<CoinTypeA>(&pool.coin_a), sui::balance::value<CoinTypeB>(&pool.coin_b))
    }

    /// Calculates and updates the fees earned by a position.
    /// This function can only be called if the pool is not paused.
    ///
    /// # Arguments
    /// * `global_config` - The global configuration for the pool
    /// * `pool` - The pool containing the position
    /// * `position_id` - The ID of the position to calculate fees for
    ///
    /// # Returns
    /// A tuple containing (fee_a, fee_b) where:
    /// * `fee_a` - The amount of fees earned in token A
    /// * `fee_b` - The amount of fees earned in token B
    ///
    /// # Aborts
    /// * If the pool is paused
    /// * If the position is not valid for this pool
    public fun calculate_and_update_fee<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        position_id: sui::object::ID
    ): (u64, u64) {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        let position_info = clmm_pool::position::borrow_position_info(&pool.position_manager, position_id);
        if (clmm_pool::position::info_liquidity(position_info) != 0) {
            let (tick_lower, tick_upper) = clmm_pool::position::info_tick_range(position_info);
            let (fee_growth_a, fee_growth_b) = get_fee_in_tick_range<CoinTypeA, CoinTypeB>(pool, tick_lower, tick_upper);
            let (fee_a, fee_b) = clmm_pool::position::update_fee(&mut pool.position_manager, position_id, fee_growth_a, fee_growth_b);
            (fee_a, fee_b)
        } else {
            let (fee_a, fee_b) = clmm_pool::position::info_fee_owned(position_info);
            (fee_a, fee_b)
        }
    }

    /// Calculates and updates the fullsail distribution rewards for a position.
    /// This function can only be called if the pool is not paused.
    ///
    /// # Arguments
    /// * `global_config` - The global configuration for the pool
    /// * `pool` - The pool containing the position
    /// * `position_id` - The ID of the position to calculate rewards for
    ///
    /// # Returns
    /// The amount of fullsail distribution rewards earned by the position
    ///
    /// # Aborts
    /// * If the pool is paused
    /// * If the position is not valid for this pool
    public fun calculate_and_update_fullsail_distribution<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        position_id: sui::object::ID
    ): u64 {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        let position_info = clmm_pool::position::borrow_position_info(&pool.position_manager, position_id);
        if (clmm_pool::position::info_liquidity(position_info) != 0) {
            let (tick_lower, tick_upper) = clmm_pool::position::info_tick_range(position_info);
            clmm_pool::position::update_fullsail_distribution(
                &mut pool.position_manager,
                position_id,
                clmm_pool::tick::get_fullsail_distribution_growth_in_range(
                    pool.current_tick_index,
                    pool.fullsail_distribution_growth_global,
                    clmm_pool::tick::try_borrow_tick(&pool.tick_manager, tick_lower),
                    clmm_pool::tick::try_borrow_tick(&pool.tick_manager, tick_upper)
                )
            )
        } else {
            clmm_pool::position::info_fullsail_distribution_owned(position_info)
        }
    }

    /// Calculates and updates the points earned by a position.
    /// Points are used for governance and rewards distribution.
    /// This function can only be called if the pool is not paused.
    ///
    /// # Arguments
    /// * `global_config` - The global configuration for the pool
    /// * `pool` - The pool containing the position
    /// * `position_id` - The ID of the position to calculate points for
    /// * `clock` - The system clock for timestamp tracking
    ///
    /// # Returns
    /// The amount of points earned by the position
    ///
    /// # Aborts
    /// * If the pool is paused
    /// * If the position is not valid for this pool
    public fun calculate_and_update_points<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        position_id: sui::object::ID,
        clock: &sui::clock::Clock
    ): u128 {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        clmm_pool::rewarder::settle(&mut pool.rewarder_manager, pool.liquidity, sui::clock::timestamp_ms(clock) / 1000);
        let position_info = clmm_pool::position::borrow_position_info(&pool.position_manager, position_id);
        if (clmm_pool::position::info_liquidity(position_info) != 0) {
            let (tick_lower, tick_upper) = clmm_pool::position::info_tick_range(position_info);
            let points = get_points_in_tick_range<CoinTypeA, CoinTypeB>(pool, tick_lower, tick_upper);
            let position_manager = &mut pool.position_manager;
            clmm_pool::position::update_points(position_manager, position_id, points)
        } else {
            clmm_pool::position::info_points_owned(
                clmm_pool::position::borrow_position_info(&pool.position_manager, position_id)
            )
        }
    }

    /// Calculates and updates the rewards earned by a position for a specific reward token.
    /// This function can only be called if the pool is not paused and the reward token exists.
    ///
    /// # Arguments
    /// * `global_config` - The global configuration for the pool
    /// * `pool` - The pool containing the position
    /// * `position_id` - The ID of the position to calculate rewards for
    /// * `clock` - The system clock for timestamp tracking
    ///
    /// # Returns
    /// The amount of rewards earned by the position for the specified reward token
    ///
    /// # Aborts
    /// * If the pool is paused
    /// * If the position is not valid for this pool
    /// * If the reward token does not exist
    public fun calculate_and_update_reward<CoinTypeA, CoinTypeB, RewardCoinType>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        position_id: sui::object::ID,
        clock: &sui::clock::Clock
    ): u64 {
        let mut rewarder_idx = clmm_pool::rewarder::rewarder_index<RewardCoinType>(&pool.rewarder_manager);
        assert!(std::option::is_some<u64>(&rewarder_idx), 17);
        let rewards = calculate_and_update_rewards<CoinTypeA, CoinTypeB>(global_config, pool, position_id, clock);
        *std::vector::borrow<u64>(&rewards, std::option::extract<u64>(&mut rewarder_idx))
    }

    /// Calculates and updates rewards for a specific position in the pool.
    /// This function can only be called if the pool is not paused.
    ///
    /// # Arguments
    /// * `global_config` - The global configuration for the pool
    /// * `pool` - The pool containing the position
    /// * `position_id` - The ID of the position to calculate rewards for
    /// * `clock` - The system clock for timestamp tracking
    ///
    /// # Returns
    /// A vector containing the amounts of rewards earned by the position for each reward token
    ///
    /// # Aborts
    /// * If the pool is paused
    /// * If the package version is not compatible
    public fun calculate_and_update_rewards<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        position_id: sui::object::ID,
        clock: &sui::clock::Clock
    ): vector<u64> {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        clmm_pool::rewarder::settle(&mut pool.rewarder_manager, pool.liquidity, sui::clock::timestamp_ms(clock) / 1000);
        let position_info = clmm_pool::position::borrow_position_info(&pool.position_manager, position_id);
        if (clmm_pool::position::info_liquidity(position_info) != 0) {
            let (tick_lower, tick_upper) = clmm_pool::position::info_tick_range(position_info);
            let rewards = get_rewards_in_tick_range<CoinTypeA, CoinTypeB>(pool, tick_lower, tick_upper);
            let position_manager = &mut pool.position_manager;
            clmm_pool::position::update_rewards(position_manager, position_id, rewards)
        } else {
            clmm_pool::position::rewards_amount_owned(&pool.position_manager, position_id)
        }
    }

    /// Calculates the distribution of fees between staked and unstaked liquidity providers.
    /// This function handles the fee splitting logic based on the total liquidity and staked liquidity.
    ///
    /// # Arguments
    /// * `pool` - The pool containing the liquidity information
    /// * `fee_amount` - The total amount of fees to distribute
    /// * `total_liquidity` - The total liquidity in the pool
    /// * `staked_liquidity` - The amount of staked liquidity
    /// * `unstaked_fee_rate` - The fee rate for unstaked liquidity
    ///
    /// # Returns
    /// A tuple containing:
    /// * The amount of fees allocated to staked liquidity providers
    /// * The amount of fees allocated to unstaked liquidity providers
    fun calculate_fees<CoinTypeA, CoinTypeB>(
        pool: &Pool<CoinTypeA, CoinTypeB>,
        fee_amount: u64,
        total_liquidity: u128,
        staked_liquidity: u128,
        unstaked_fee_rate: u64
    ): (u128, u64) {
        if (total_liquidity == pool.fullsail_distribution_staked_liquidity) {
            (0, fee_amount)
        } else {
            let (staked_fee, unstaked_fee) = if (staked_liquidity == 0) {
                let (unstaked_amount, unstaked_fee_amount) = apply_unstaked_fees(fee_amount as u128, 0, unstaked_fee_rate);
                (integer_mate::full_math_u128::mul_div_floor(unstaked_amount, 18446744073709551616, total_liquidity), unstaked_fee_amount as u64)
            } else {
                let (staked_amount, unstaked_fee_amount) = split_fees(fee_amount, total_liquidity, staked_liquidity, unstaked_fee_rate);
                (integer_mate::full_math_u128::mul_div_floor(staked_amount as u128, 18446744073709551616, total_liquidity - staked_liquidity), unstaked_fee_amount)
            };
            (staked_fee, unstaked_fee)
        }
    }

    /// Calculates the result of a swap operation in the pool without executing it.
    /// This function simulates the swap and returns detailed information about how it would execute,
    /// including amounts, fees, and price impact.
    ///
    /// # Arguments
    /// * `global_config` - The global configuration for the pool
    /// * `pool` - The pool to simulate the swap in
    /// * `a2b` - Direction of the swap: true for swapping token A to B, false for B to A
    /// * `by_amount_in` - Whether the amount specified is the input amount (true) or output amount (false)
    /// * `amount` - The amount to swap (interpreted as input or output based on by_amount_in)
    ///
    /// # Returns
    /// A CalculatedSwapResult containing:
    /// * amount_in - The amount of input tokens that would be used
    /// * amount_out - The amount of output tokens that would be received
    /// * fee_amount - The total amount of fees that would be charged
    /// * fee_rate - The fee rate used for the swap
    /// * ref_fee_amount - The amount of referral fees
    /// * gauge_fee_amount - The amount of fees allocated to gauges
    /// * protocol_fee_amount - The amount of protocol fees
    /// * after_sqrt_price - The square root of the price after the swap
    /// * is_exceed - Whether the swap would exceed available liquidity
    /// * step_results - Detailed results for each step of the swap calculation
    ///
    /// # Example
    /// This function is typically used before executing a swap to:
    /// * Calculate expected output amounts
    /// * Determine price impact
    /// * Estimate fees
    /// * Check if the swap is viable
    public fun calculate_swap_result<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &Pool<CoinTypeA, CoinTypeB>,
        a2b: bool,
        by_amount_in: bool,
        amount: u64
    ): CalculatedSwapResult {
        let mut current_sqrt_price = pool.current_sqrt_price;
        let mut current_liquidity = pool.liquidity;
        let mut staked_liquidity = pool.fullsail_distribution_staked_liquidity;
        let mut swap_result = default_swap_result();
        let mut remaining_amount = amount;
        let mut next_tick = clmm_pool::tick::first_score_for_swap(&pool.tick_manager, pool.current_tick_index, a2b);
        let mut calculated_result = CalculatedSwapResult {
            amount_in: 0,
            amount_out: 0,
            fee_amount: 0,
            fee_rate: pool.fee_rate,
            ref_fee_amount: 0,
            gauge_fee_amount: 0,
            protocol_fee_amount: 0,
            after_sqrt_price: pool.current_sqrt_price,
            is_exceed: false,
            step_results: std::vector::empty<SwapStepResult>(),
        };
        let unstaked_fee_rate = if (pool.unstaked_liquidity_fee_rate == clmm_pool::config::default_unstaked_fee_rate()) {
            clmm_pool::config::unstaked_liquidity_fee_rate(global_config)
        } else {
            pool.unstaked_liquidity_fee_rate
        };
        while (remaining_amount > 0) {
            if (move_stl::option_u64::is_none(&next_tick)) {
                calculated_result.is_exceed = true;
                break
            };
            let (tick, next_tick_score) = clmm_pool::tick::borrow_tick_for_swap(
                &pool.tick_manager,
                move_stl::option_u64::borrow(&next_tick),
                a2b
            );
            next_tick = next_tick_score;
            let target_sqrt_price = clmm_pool::tick::sqrt_price(tick);
            let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_pool::clmm_math::compute_swap_step(
                current_sqrt_price,
                target_sqrt_price,
                current_liquidity,
                remaining_amount,
                pool.fee_rate,
                a2b,
                by_amount_in
            );
            if (amount_in != 0 || fee_amount != 0) {
                let new_remaining_amount = if (by_amount_in) {
                    let after_amount_in = check_remainer_amount_sub(remaining_amount, amount_in);
                    check_remainer_amount_sub(after_amount_in, fee_amount)
                } else {
                    check_remainer_amount_sub(remaining_amount, amount_out)
                };
                remaining_amount = new_remaining_amount;
                let protocol_fee = integer_mate::full_math_u64::mul_div_ceil(
                    fee_amount,
                    clmm_pool::config::protocol_fee_rate(global_config),
                    clmm_pool::config::protocol_fee_rate_denom()
                );
                let (_, gauge_fee) = calculate_fees<CoinTypeA, CoinTypeB>(
                    pool,
                    fee_amount - protocol_fee,
                    pool.liquidity,
                    pool.fullsail_distribution_staked_liquidity,
                    unstaked_fee_rate
                );
                update_swap_result(&mut swap_result, amount_in, amount_out, fee_amount, protocol_fee, 0, gauge_fee);
            };
            let step_result = SwapStepResult {
                current_sqrt_price,
                target_sqrt_price,
                current_liquidity,
                amount_in,
                amount_out,
                fee_amount,
                remainder_amount: remaining_amount,
            };
            std::vector::push_back<SwapStepResult>(&mut calculated_result.step_results, step_result);
            if (next_sqrt_price == target_sqrt_price) {
                current_sqrt_price = target_sqrt_price;
                let (liquidity_delta, staked_liquidity_delta) = if (a2b) {
                    (integer_mate::i128::neg(clmm_pool::tick::liquidity_net(tick)), integer_mate::i128::neg(
                        clmm_pool::tick::fullsail_distribution_staked_liquidity_net(tick)
                    ))
                } else {
                    (clmm_pool::tick::liquidity_net(tick), clmm_pool::tick::fullsail_distribution_staked_liquidity_net(tick))
                };
                let liquidity_abs = integer_mate::i128::abs_u128(liquidity_delta);
                let staked_liquidity_abs = integer_mate::i128::abs_u128(staked_liquidity_delta);
                if (!integer_mate::i128::is_neg(liquidity_delta)) {
                    assert!(integer_mate::math_u128::add_check(current_liquidity, liquidity_abs), 1);
                    current_liquidity = current_liquidity + liquidity_abs;
                } else {
                    assert!(current_liquidity >= liquidity_abs, 1);
                    current_liquidity = current_liquidity - liquidity_abs;
                };
                if (!integer_mate::i128::is_neg(staked_liquidity_delta)) {
                    assert!(integer_mate::math_u128::add_check(staked_liquidity, staked_liquidity_abs), 1);
                    staked_liquidity = staked_liquidity + staked_liquidity_abs;
                    continue
                };
                assert!(staked_liquidity >= staked_liquidity_abs, 1);
                staked_liquidity = staked_liquidity - staked_liquidity_abs;
                continue
            };
            current_sqrt_price = next_sqrt_price;
        };
        calculated_result.amount_in = swap_result.amount_in;
        calculated_result.amount_out = swap_result.amount_out;
        calculated_result.fee_amount = swap_result.fee_amount;
        calculated_result.gauge_fee_amount = swap_result.gauge_fee_amount;
        calculated_result.protocol_fee_amount = swap_result.protocol_fee_amount;
        calculated_result.after_sqrt_price = current_sqrt_price;
        calculated_result
    }

    /// Returns a reference to the vector of swap step results from the calculated swap result.
    /// Each step result contains detailed information about a single step in the swap calculation,
    /// including prices, liquidity, amounts, and fees.
    ///
    /// # Arguments
    /// * `calculated_swap_result` - Reference to the CalculatedSwapResult containing the swap simulation data
    ///
    /// # Returns
    /// A reference to the vector of SwapStepResult structs containing detailed information about each swap step
    public fun calculate_swap_result_step_results(calculated_swap_result: &CalculatedSwapResult): &vector<SwapStepResult> {
        &calculated_swap_result.step_results
    }

    /// Calculates the expected result of a swap operation with partner fee rate.
    /// This function simulates a swap operation and returns detailed information about the expected outcome,
    /// including amounts, fees, and price changes. It handles both input and output amount-based swaps.
    ///
    /// # Arguments
    /// * `global_config` - Reference to the global configuration containing protocol parameters
    /// * `pool` - Reference to the pool containing the current state
    /// * `a2b` - Boolean indicating the swap direction (true for A to B, false for B to A)
    /// * `by_amount_in` - Boolean indicating whether the amount parameter represents input or output amount
    /// * `amount` - The amount to swap (either input or output amount based on by_amount_in)
    /// * `ref_fee_rate` - The partner fee rate in basis points
    ///
    /// # Returns
    /// A CalculatedSwapResult struct containing:
    /// * Input and output amounts
    /// * Various fee amounts (total, gauge, protocol, referral)
    /// * Final price after the swap
    /// * Whether the swap would exceed available liquidity
    /// * Detailed step-by-step results of the swap calculation
    ///
    /// # Aborts
    /// * If liquidity calculations would overflow
    /// * If fee calculations would overflow
    /// * If price calculations would overflow
    public fun calculate_swap_result_with_partner<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &Pool<CoinTypeA, CoinTypeB>,
        a2b: bool,
        by_amount_in: bool,
        amount: u64,
        ref_fee_rate: u64
    ): CalculatedSwapResult {
        let mut current_sqrt_price = pool.current_sqrt_price;
        let mut current_liquidity = pool.liquidity;
        let mut staked_liquidity = pool.fullsail_distribution_staked_liquidity;
        let mut swap_result = default_swap_result();
        let mut remaining_amount = amount;
        let mut next_tick = clmm_pool::tick::first_score_for_swap(&pool.tick_manager, pool.current_tick_index, a2b);
        let mut calculated_result = CalculatedSwapResult {
            amount_in: 0,
            amount_out: 0,
            fee_amount: 0,
            fee_rate: pool.fee_rate,
            ref_fee_amount: 0,
            gauge_fee_amount: 0,
            protocol_fee_amount: 0,
            after_sqrt_price: pool.current_sqrt_price,
            is_exceed: false,
            step_results: std::vector::empty<SwapStepResult>(),
        };
        let unstaked_fee_rate = if (pool.unstaked_liquidity_fee_rate == clmm_pool::config::default_unstaked_fee_rate()) {
            clmm_pool::config::unstaked_liquidity_fee_rate(global_config)
        } else {
            pool.unstaked_liquidity_fee_rate
        };
        while (remaining_amount > 0) {
            if (move_stl::option_u64::is_none(&next_tick)) {
                calculated_result.is_exceed = true;
                break
            };
            let (tick, next_tick_score) = clmm_pool::tick::borrow_tick_for_swap(
                &pool.tick_manager,
                move_stl::option_u64::borrow(&next_tick),
                a2b
            );
            next_tick = next_tick_score;
            let target_sqrt_price = clmm_pool::tick::sqrt_price(tick);
            let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_pool::clmm_math::compute_swap_step(
                current_sqrt_price,
                target_sqrt_price,
                current_liquidity,
                remaining_amount,
                pool.fee_rate,
                a2b,
                by_amount_in
            );
            if (amount_in != 0 || fee_amount != 0) {
                let new_remaining_amount = if (by_amount_in) {
                    let amount_after_in = check_remainer_amount_sub(remaining_amount, amount_in);
                    check_remainer_amount_sub(amount_after_in, fee_amount)
                } else {
                    check_remainer_amount_sub(remaining_amount, amount_out)
                };
                remaining_amount = new_remaining_amount;
                let ref_fee = integer_mate::full_math_u64::mul_div_ceil(
                    fee_amount,
                    ref_fee_rate,
                    clmm_pool::config::protocol_fee_rate_denom()
                );
                let remaining_fee = fee_amount - ref_fee;
                let mut gauge_fee = 0;
                let mut protocol_fee = 0;
                if (remaining_fee > 0) {
                    let protocol_fee_amount = integer_mate::full_math_u64::mul_div_ceil(
                        remaining_fee,
                        clmm_pool::config::protocol_fee_rate(global_config),
                        clmm_pool::config::protocol_fee_rate_denom()
                    );
                    protocol_fee = protocol_fee_amount;
                    let fee_after_protocol = remaining_fee - protocol_fee_amount;
                    if (fee_after_protocol > 0) {
                        let (_, gauge_fee_amount) = calculate_fees<CoinTypeA, CoinTypeB>(
                            pool,
                            fee_after_protocol,
                            pool.liquidity,
                            pool.fullsail_distribution_staked_liquidity,
                            unstaked_fee_rate
                        );
                        gauge_fee = gauge_fee_amount;
                    };
                };
                update_swap_result(&mut swap_result, amount_in, amount_out, fee_amount, protocol_fee, ref_fee, gauge_fee);
            };
            let step_result = SwapStepResult {
                current_sqrt_price,
                target_sqrt_price,
                current_liquidity,
                amount_in,
                amount_out,
                fee_amount,
                remainder_amount: remaining_amount,
            };
            std::vector::push_back<SwapStepResult>(&mut calculated_result.step_results, step_result);
            if (next_sqrt_price == target_sqrt_price) {
                current_sqrt_price = target_sqrt_price;
                let (liquidity_delta, staked_liquidity_delta) = if (a2b) {
                    (integer_mate::i128::neg(clmm_pool::tick::liquidity_net(tick)), integer_mate::i128::neg(
                        clmm_pool::tick::fullsail_distribution_staked_liquidity_net(tick)
                    ))
                } else {
                    (clmm_pool::tick::liquidity_net(tick), clmm_pool::tick::fullsail_distribution_staked_liquidity_net(tick))
                };
                let liquidity_abs = integer_mate::i128::abs_u128(liquidity_delta);
                let staked_liquidity_abs = integer_mate::i128::abs_u128(staked_liquidity_delta);
                if (!integer_mate::i128::is_neg(liquidity_delta)) {
                    assert!(integer_mate::math_u128::add_check(current_liquidity, liquidity_abs), 1);
                    current_liquidity = current_liquidity + liquidity_abs;
                } else {
                    assert!(current_liquidity >= liquidity_abs, 1);
                    current_liquidity = current_liquidity - liquidity_abs;
                };
                if (!integer_mate::i128::is_neg(staked_liquidity_delta)) {
                    assert!(integer_mate::math_u128::add_check(staked_liquidity, staked_liquidity_abs), 1);
                    staked_liquidity = staked_liquidity + staked_liquidity_abs;
                    continue
                };
                assert!(staked_liquidity >= staked_liquidity_abs, 1);
                staked_liquidity = staked_liquidity - staked_liquidity_abs;
                continue
            };
            current_sqrt_price = next_sqrt_price;
        };
        calculated_result.amount_in = swap_result.amount_in;
        calculated_result.amount_out = swap_result.amount_out;
        calculated_result.fee_amount = swap_result.fee_amount;
        calculated_result.gauge_fee_amount = swap_result.gauge_fee_amount;
        calculated_result.protocol_fee_amount = swap_result.protocol_fee_amount;
        calculated_result.ref_fee_amount = swap_result.ref_fee_amount;
        calculated_result.after_sqrt_price = current_sqrt_price;
        calculated_result
    }

    /// Returns the square root of the price after the simulated swap.
    /// This value represents the final price level that would be reached after executing the swap.
    ///
    /// # Arguments
    /// * `swap_result` - The CalculatedSwapResult containing the swap simulation data
    ///
    /// # Returns
    /// The square root of the final price as a u128 value
    public fun calculated_swap_result_after_sqrt_price(swap_result: &CalculatedSwapResult): u128 {
        swap_result.after_sqrt_price
    }

    /// Returns the amount of input tokens that would be required for the swap.
    ///
    /// # Arguments
    /// * `swap_result` - The CalculatedSwapResult containing the swap simulation data
    ///
    /// # Returns
    /// The amount of input tokens needed as a u64 value
    public fun calculated_swap_result_amount_in(swap_result: &CalculatedSwapResult): u64 {
        swap_result.amount_in
    }

    /// Returns the amount of output tokens that would be received from the swap.
    ///
    /// # Arguments
    /// * `swap_result` - The CalculatedSwapResult containing the swap simulation data
    ///
    /// # Returns
    /// The amount of output tokens to be received as a u64 value
    public fun calculated_swap_result_amount_out(swap_result: &CalculatedSwapResult): u64 {
        swap_result.amount_out
    }

    /// Returns all fee amounts associated with the simulated swap.
    ///
    /// # Arguments
    /// * `swap_result` - The CalculatedSwapResult containing the swap simulation data
    ///
    /// # Returns
    /// A tuple containing:
    /// * Total fee amount
    /// * Referral fee amount
    /// * Protocol fee amount
    /// * Gauge fee amount
    public fun calculated_swap_result_fees_amount(swap_result: &CalculatedSwapResult): (u64, u64, u64, u64) {
        (swap_result.fee_amount, swap_result.ref_fee_amount, swap_result.protocol_fee_amount, swap_result.gauge_fee_amount)
    }

    /// Indicates whether the simulated swap would exceed the available liquidity.
    ///
    /// # Arguments
    /// * `swap_result` - The CalculatedSwapResult containing the swap simulation data
    ///
    /// # Returns
    /// true if the swap would exceed available liquidity, false otherwise
    public fun calculated_swap_result_is_exceed(swap_result: &CalculatedSwapResult): bool {
        swap_result.is_exceed
    }

    /// Returns a reference to a specific swap step result at the given index.
    /// This function allows accessing detailed information about a particular step in the swap calculation.
    ///
    /// # Arguments
    /// * `swap_result` - Reference to the CalculatedSwapResult containing the swap simulation data
    /// * `step_index` - The index of the step result to retrieve
    ///
    /// # Returns
    /// A reference to the SwapStepResult at the specified index
    ///
    /// # Aborts
    /// * If step_index is out of bounds
    public fun calculated_swap_result_step_swap_result(swap_result: &CalculatedSwapResult, step_index: u64): &SwapStepResult {
        std::vector::borrow<SwapStepResult>(&swap_result.step_results, step_index)
    }

    /// Returns the total number of steps in the swap calculation.
    /// This function provides the count of individual steps that were calculated during the swap simulation.
    ///
    /// # Arguments
    /// * `swap_result` - Reference to the CalculatedSwapResult containing the swap simulation data
    ///
    /// # Returns
    /// The number of steps in the swap calculation
    public fun calculated_swap_result_steps_length(swap_result: &CalculatedSwapResult): u64 {
        std::vector::length<SwapStepResult>(&swap_result.step_results)
    }

    /// Verifies that the provided gauge cap is valid for the given pool.
    /// This function checks if the gauge cap's pool ID matches the pool's ID and if the gauge ID matches
    /// the pool's configured gauger ID.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool to check against
    /// * `gauge_cap` - Reference to the gauge cap to validate
    ///
    /// # Aborts
    /// * If the gauge cap is not valid for the pool (error code: 9223379355479048191)
    fun check_gauge_cap<CoinTypeA, CoinTypeB>(
        pool: &Pool<CoinTypeA, CoinTypeB>, 
        gauge_cap: &gauge_cap::gauge_cap::GaugeCap
    ) {
        let is_valid = if (gauge_cap::gauge_cap::get_pool_id(gauge_cap) == sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool)) {
            let gauger_id = &pool.fullsail_distribution_gauger_id;
            let has_valid_gauge = if (std::option::is_some<sui::object::ID>(gauger_id)) {
                let cap_gauge_id = gauge_cap::gauge_cap::get_gauge_id(gauge_cap);
                std::option::borrow<sui::object::ID>(gauger_id) == &cap_gauge_id
            } else {
                false
            };
            has_valid_gauge
        } else {
            false
        };
        assert!(is_valid, 9223379355479048191);
    }

    /// Safely subtracts a value from an amount, ensuring the result is non-negative.
    /// This is a helper function used in swap calculations to handle amount subtractions
    /// while preventing underflows.
    ///
    /// # Arguments
    /// * `amount` - The amount to subtract from
    /// * `sub_amount` - The amount to subtract
    ///
    /// # Returns
    /// The result of the subtraction
    ///
    /// # Aborts
    /// * If sub_amount is greater than amount (error code: 5)
    fun check_remainer_amount_sub(amount: u64, sub_amount: u64): u64 {
        assert!(amount >= sub_amount, 5);
        amount - sub_amount
    }

    /// Validates if a given tick range is valid for the pool.
    /// A tick range is considered valid if:
    /// * The lower tick is less than the upper tick
    /// * The lower tick is not less than the minimum allowed tick
    /// * The upper tick is not greater than the maximum allowed tick
    ///
    /// # Arguments
    /// * `tick_lower` - The lower tick of the range
    /// * `tick_upper` - The upper tick of the range
    ///
    /// # Returns
    /// * true if the tick range is valid
    /// * false if the tick range is invalid
    fun check_tick_range(tick_lower: integer_mate::i32::I32, tick_upper: integer_mate::i32::I32): bool {
        let is_invalid = if (integer_mate::i32::gte(tick_lower, tick_upper)) {
            true
        } else {
            if (integer_mate::i32::lt(tick_lower, clmm_pool::tick_math::min_tick())) {
                true
            } else {
                integer_mate::i32::gt(tick_upper, clmm_pool::tick_math::max_tick())
            }
        };
        if (is_invalid) {
            return false
        };
        true
    }
    
    /// Collects accumulated fees from a position in the pool.
    /// This function handles fee collection for non-staked positions, including:
    /// * Updating and resetting fees if requested and position has liquidity
    /// * Resetting fees without updating if position has no liquidity
    /// * Emitting a CollectFeeEvent with the collected amounts
    /// * Splitting the collected fees from the pool's token balances
    ///
    /// # Arguments
    /// * `global_config` - Reference to the global configuration containing protocol parameters
    /// * `pool` - Reference to the pool containing the position
    /// * `position` - Reference to the position to collect fees from
    /// * `update_fee` - Boolean indicating whether to update fees before collection
    ///
    /// # Returns
    /// A tuple containing:
    /// * Balance of CoinTypeA collected as fees
    /// * Balance of CoinTypeB collected as fees
    ///
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    /// * If the package version is invalid
    /// * If the position is staked (returns zero balances)
    public fun collect_fee<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        position: &clmm_pool::position::Position,
        update_fee: bool
    ): (sui::balance::Balance<CoinTypeA>, sui::balance::Balance<CoinTypeB>) {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        let position_id = sui::object::id<clmm_pool::position::Position>(position);
        if (clmm_pool::position::is_staked(borrow_position_info<CoinTypeA, CoinTypeB>(pool, position_id))) {
            return (sui::balance::zero<CoinTypeA>(), sui::balance::zero<CoinTypeB>())
        };
        let (tick_lower, tick_upper) = clmm_pool::position::tick_range(position);
        let (fee_amount_a, fee_amount_b) = if (update_fee && clmm_pool::position::liquidity(position) != 0) {
            let (fee_growth_a, fee_growth_b) = get_fee_in_tick_range<CoinTypeA, CoinTypeB>(pool, tick_lower, tick_upper);
            let (amount_a, amount_b) = clmm_pool::position::update_and_reset_fee(&mut pool.position_manager, position_id, fee_growth_a, fee_growth_b);
            (amount_a, amount_b)
        } else {
            let (amount_a, amount_b) = clmm_pool::position::reset_fee(&mut pool.position_manager, position_id);
            (amount_a, amount_b)
        };
        let collect_fee_event = CollectFeeEvent {
            position: position_id,
            pool: sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool),
            amount_a: fee_amount_a,
            amount_b: fee_amount_b,
        };
        sui::event::emit<CollectFeeEvent>(collect_fee_event);
        (sui::balance::split<CoinTypeA>(&mut pool.coin_a, fee_amount_a), sui::balance::split<CoinTypeB>(&mut pool.coin_b, fee_amount_b))
    }
    
    /// Collects accumulated gauge fees from the pool.
    /// This function handles fee collection for the gauge, including:
    /// * Validating the gauge cap
    /// * Collecting accumulated fees for both token types
    /// * Resetting the gauge fee accumulators
    /// * Emitting a CollectGaugeFeeEvent with the collected amounts
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the gauge fees
    /// * `gauge_cap` - Reference to the gauge cap for validation
    ///
    /// # Returns
    /// A tuple containing:
    /// * Balance of CoinTypeA collected as gauge fees
    /// * Balance of CoinTypeB collected as gauge fees
    ///
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    /// * If the gauge cap is invalid for the pool
    public fun collect_fullsail_distribution_gauger_fees<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        gauge_cap: &gauge_cap::gauge_cap::GaugeCap
    ): (sui::balance::Balance<CoinTypeA>, sui::balance::Balance<CoinTypeB>) {
        assert!(!pool.is_pause, 13);
        check_gauge_cap<CoinTypeA, CoinTypeB>(pool, gauge_cap);
        let mut balance_a = sui::balance::zero<CoinTypeA>();
        let mut balance_b = sui::balance::zero<CoinTypeB>();
        
        if (pool.fullsail_distribution_gauger_fee.coin_a > 0) {
            sui::balance::join<CoinTypeA>(
                &mut balance_a,
                sui::balance::split<CoinTypeA>(&mut pool.coin_a, pool.fullsail_distribution_gauger_fee.coin_a)
            );
            pool.fullsail_distribution_gauger_fee.coin_a = 0;
        };

        if (pool.fullsail_distribution_gauger_fee.coin_b > 0) {
            sui::balance::join<CoinTypeB>(
                &mut balance_b,
                sui::balance::split<CoinTypeB>(&mut pool.coin_b, pool.fullsail_distribution_gauger_fee.coin_b)
            );
            pool.fullsail_distribution_gauger_fee.coin_b = 0;
        };

        let event = CollectGaugeFeeEvent {
            pool: sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool),
            amount_a: sui::balance::value<CoinTypeA>(&balance_a),
            amount_b: sui::balance::value<CoinTypeB>(&balance_b),
        };
        sui::event::emit<CollectGaugeFeeEvent>(event);
        (balance_a, balance_b)
    }
    
    /// Collects accumulated protocol fees from the pool.
    /// This function handles protocol fee collection, including:
    /// * Validating package version
    /// * Checking pool pause status
    /// * Verifying protocol fee claim role
    /// * Resetting protocol fee accumulators
    /// * Emitting a CollectProtocolFeeEvent with the collected amounts
    ///
    /// # Arguments
    /// * `global_config` - Reference to the global configuration containing protocol parameters
    /// * `pool` - Reference to the pool containing the protocol fees
    /// * `ctx` - Reference to the transaction context
    ///
    /// # Returns
    /// A tuple containing:
    /// * Balance of CoinTypeA collected as protocol fees
    /// * Balance of CoinTypeB collected as protocol fees
    ///
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    /// * If the package version is invalid
    /// * If the caller does not have protocol fee claim role
    public fun collect_protocol_fee<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>, 
        ctx: &mut sui::tx_context::TxContext
    ): (sui::balance::Balance<CoinTypeA>, sui::balance::Balance<CoinTypeB>) {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        clmm_pool::config::check_protocol_fee_claim_role(global_config, sui::tx_context::sender(ctx));
        
        let fee_amount_a = pool.fee_protocol_coin_a;
        let fee_amount_b = pool.fee_protocol_coin_b;
        pool.fee_protocol_coin_a = 0;
        pool.fee_protocol_coin_b = 0;

        let event = CollectProtocolFeeEvent {
            pool: sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool),
            amount_a: fee_amount_a,
            amount_b: fee_amount_b,
        };
        sui::event::emit<CollectProtocolFeeEvent>(event);
        
        (sui::balance::split<CoinTypeA>(&mut pool.coin_a, fee_amount_a), 
         sui::balance::split<CoinTypeB>(&mut pool.coin_b, fee_amount_b))
    }

    /// Collects accumulated rewards from a position in the pool.
    /// This function handles reward collection, including:
    /// * Validating package version
    /// * Checking pool pause status
    /// * Settling rewards based on current timestamp
    /// * Updating rewards if requested and position has liquidity
    /// * Collecting rewards from the rewarder vault
    ///
    /// # Arguments
    /// * `global_config` - Reference to the global configuration containing protocol parameters
    /// * `pool` - Reference to the pool containing the position
    /// * `position` - Reference to the position to collect rewards from
    /// * `rewarder_vault` - Reference to the rewarder vault containing the rewards
    /// * `update_rewards` - Boolean indicating whether to update rewards before collection
    /// * `clock` - Reference to the clock for timestamp calculations
    ///
    /// # Returns
    /// Balance of RewardCoinType collected as rewards
    ///
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    /// * If the package version is invalid
    /// * If the rewarder index is not found (error code: 17)
    public fun collect_reward<CoinTypeA, CoinTypeB, RewardCoinType>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        position: &clmm_pool::position::Position,
        rewarder_vault: &mut clmm_pool::rewarder::RewarderGlobalVault,
        update_rewards: bool,
        clock: &sui::clock::Clock
    ): sui::balance::Balance<RewardCoinType> {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        clmm_pool::rewarder::settle(&mut pool.rewarder_manager, pool.liquidity, sui::clock::timestamp_ms(clock) / 1000);
        let position_id = sui::object::id<clmm_pool::position::Position>(position);
        let mut rewarder_idx = clmm_pool::rewarder::rewarder_index<RewardCoinType>(&pool.rewarder_manager);
        assert!(std::option::is_some<u64>(&rewarder_idx), 17);
        let rewarder_index = std::option::extract<u64>(&mut rewarder_idx);
        let reward_amount = if (update_rewards && clmm_pool::position::liquidity(position) != 0 || clmm_pool::position::inited_rewards_count(
            &pool.position_manager,
            position_id
        ) <= rewarder_index) {
            let (tick_lower, tick_upper) = clmm_pool::position::tick_range(position);
            let rewards = get_rewards_in_tick_range<CoinTypeA, CoinTypeB>(pool, tick_lower, tick_upper);
            let position_manager = &mut pool.position_manager;
            clmm_pool::position::update_and_reset_rewards(position_manager, position_id, rewards, rewarder_index)
        } else {
            clmm_pool::position::reset_rewarder(&mut pool.position_manager, position_id, rewarder_index)
        };
        let event = CollectRewardEvent {
            position: position_id,
            pool: sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool),
            amount: reward_amount,
        };
        sui::event::emit<CollectRewardEvent>(event);
        clmm_pool::rewarder::withdraw_reward<RewardCoinType>(rewarder_vault, reward_amount)
    }
    
    /// Returns the current square root price of the pool.
    /// This value represents the current price of the pool in square root form.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool to get the price from
    ///
    /// # Returns
    /// The current square root price of the pool
    public fun current_sqrt_price<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): u128 {
        pool.current_sqrt_price
    }

    /// Returns the current tick index of the pool.
    /// The tick index represents the current price level in the pool's price range.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool to get the tick index from
    ///
    /// # Returns
    /// The current tick index of the pool
    public fun current_tick_index<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): integer_mate::i32::I32 {
        pool.current_tick_index
    }

    /// Creates a default SwapResult with all fields initialized to zero.
    /// This is used as an initial state for swap calculations.
    ///
    /// # Returns
    /// A new SwapResult with all fields set to zero
    fun default_swap_result(): SwapResult {
        SwapResult {
            amount_in: 0,
            amount_out: 0,
            fee_amount: 0,
            protocol_fee_amount: 0,
            ref_fee_amount: 0,
            gauge_fee_amount: 0,
            steps: 0,
        }
    }

    /// Returns the fee rate of the pool in basis points.
    /// The fee rate determines the percentage of fees charged for swaps.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool to get the fee rate from
    ///
    /// # Returns
    /// The fee rate in basis points (1/10000)
    public fun fee_rate<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): u64 {
        pool.fee_rate
    }

    /// Returns all fee amounts from a flash swap receipt.
    /// This includes the total fee amount, referral fee, protocol fee, and gauge fee.
    ///
    /// # Arguments
    /// * `receipt` - Reference to the FlashSwapReceipt containing the fee information
    ///
    /// # Returns
    /// A tuple containing:
    /// * Total fee amount
    /// * Referral fee amount
    /// * Protocol fee amount
    /// * Gauge fee amount
    public fun fees_amount<CoinTypeA, CoinTypeB>(receipt: &FlashSwapReceipt<CoinTypeA, CoinTypeB>): (u64, u64, u64, u64) {
        (receipt.fee_amount, receipt.ref_fee_amount, receipt.protocol_fee_amount, receipt.gauge_fee_amount)
    }

    /// Returns the global fee growth accumulators for both tokens.
    /// These values track the total fees earned per unit of liquidity over time.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool to get the fee growth from
    ///
    /// # Returns
    /// A tuple containing:
    /// * Global fee growth for token A
    /// * Global fee growth for token B
    public fun fees_growth_global<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): (u128, u128) {
        (pool.fee_growth_global_a, pool.fee_growth_global_b)
    }

    /// Executes a flash swap operation in the pool.
    /// This function allows performing a swap operation with a specified amount and price limit.
    /// The swap can be executed in either direction (A to B or B to A) and can be specified
    /// by either input or output amount.
    ///
    /// # Arguments
    /// * `global_config` - Reference to the global configuration containing protocol parameters
    /// * `pool` - Reference to the pool to perform the swap in
    /// * `a2b` - Boolean indicating the swap direction (true for A to B, false for B to A)
    /// * `by_amount_in` - Boolean indicating whether the amount parameter represents input or output amount
    /// * `amount` - The amount to swap (either input or output amount based on by_amount_in)
    /// * `sqrt_price_limit` - The price limit for the swap in square root form
    /// * `stats` - Reference to the pool statistics to update
    /// * `price_provider` - Reference to the price provider for price calculations
    /// * `clock` - Reference to the clock for timestamp calculations
    ///
    /// # Returns
    /// A tuple containing:
    /// * Balance of CoinTypeA (output if B to A, zero if A to B)
    /// * Balance of CoinTypeB (output if A to B, zero if B to A)
    /// * FlashSwapReceipt containing swap details and fees
    ///
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    /// * If the package version is invalid
    /// * If the amount is zero (error code: 0)
    /// * If the price limit is invalid (error code: 11)
    /// * If no output amount is received (error code: 18)
    public fun flash_swap<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        a2b: bool,
        by_amount_in: bool,
        amount: u64,
        sqrt_price_limit: u128,
        stats: &mut clmm_pool::stats::Stats,
        price_provider: &price_provider::price_provider::PriceProvider,
        clock: &sui::clock::Clock
    ): (sui::balance::Balance<CoinTypeA>, sui::balance::Balance<CoinTypeB>, FlashSwapReceipt<CoinTypeA, CoinTypeB>) {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        flash_swap_internal<CoinTypeA, CoinTypeB>(
            pool,
            global_config,
            sui::object::id_from_address(@0x0),
            0,
            a2b,
            by_amount_in,
            amount,
            sqrt_price_limit,
            stats,
            price_provider,
            clock
        )
    }

    /// Internal function that executes a flash swap operation with partner fee rate.
    /// This function handles the core swap logic, including:
    /// * Validating swap parameters
    /// * Settling rewards
    /// * Calculating fees
    /// * Executing the swap
    /// * Emitting swap events
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool to perform the swap in
    /// * `global_config` - Reference to the global configuration containing protocol parameters
    /// * `partner_id` - ID of the partner for fee calculation
    /// * `ref_fee_rate` - Partner referral fee rate in basis points
    /// * `a2b` - Boolean indicating the swap direction
    /// * `by_amount_in` - Boolean indicating whether amount is input or output
    /// * `amount` - The amount to swap
    /// * `sqrt_price_limit` - The price limit for the swap
    /// * `stats` - Reference to the pool statistics
    /// * `price_provider` - Reference to the price provider for price calculations
    /// * `clock` - Reference to the clock for timestamp calculations
    ///
    /// # Returns
    /// A tuple containing:
    /// * Balance of CoinTypeA (output if B to A, zero if A to B)
    /// * Balance of CoinTypeB (output if A to B, zero if B to A)
    /// * FlashSwapReceipt containing swap details and fees
    ///
    /// # Aborts
    /// * If the amount is zero (error code: 0)
    /// * If the price limit is invalid (error code: 11)
    /// * If no output amount is received (error code: 18)
    fun flash_swap_internal<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        global_config: &clmm_pool::config::GlobalConfig,
        partner_id: sui::object::ID,
        ref_fee_rate: u64,
        a2b: bool,
        by_amount_in: bool,
        amount: u64,
        sqrt_price_limit: u128,
        stats: &mut clmm_pool::stats::Stats,
        price_provider: &price_provider::price_provider::PriceProvider,
        clock: &sui::clock::Clock
    ): (sui::balance::Balance<CoinTypeA>, sui::balance::Balance<CoinTypeB>, FlashSwapReceipt<CoinTypeA, CoinTypeB>) {
        assert!(amount > 0, 0);
        clmm_pool::rewarder::settle(&mut pool.rewarder_manager, pool.liquidity, sui::clock::timestamp_ms(clock) / 1000);
        if (a2b) {
            assert!(pool.current_sqrt_price > sqrt_price_limit && sqrt_price_limit >= clmm_pool::tick_math::min_sqrt_price(), 11);
        } else {
            assert!(pool.current_sqrt_price < sqrt_price_limit && sqrt_price_limit <= clmm_pool::tick_math::max_sqrt_price(), 11);
        };
        let unstaked_fee_rate = pool.unstaked_liquidity_fee_rate;
        let final_unstaked_fee_rate = if (unstaked_fee_rate == clmm_pool::config::default_unstaked_fee_rate()) {
            clmm_pool::config::unstaked_liquidity_fee_rate(global_config)
        } else {
            unstaked_fee_rate
        };
        let swap_result = swap_in_pool<CoinTypeA, CoinTypeB>(
            pool,
            a2b,
            by_amount_in,
            sqrt_price_limit,
            amount,
            final_unstaked_fee_rate,
            clmm_pool::config::protocol_fee_rate(global_config),
            ref_fee_rate,
            clock
        );
        assert!(swap_result.amount_out > 0, 18);
        let (balance_b, balance_a) = if (a2b) {
            (sui::balance::split<CoinTypeB>(&mut pool.coin_b, swap_result.amount_out), sui::balance::zero<CoinTypeA>())
        } else {
            (sui::balance::zero<CoinTypeB>(), sui::balance::split<CoinTypeA>(&mut pool.coin_a, swap_result.amount_out))
        };

        // TODO volumes
        // let price = global_config.price_supplier;
        // if (a2b) {
        // let price_a = price_provider::price_provider::get_price(price_provider, pool.feed_id_coin_a);
        //     pool.volume_usd_coin_a
          //      stats.add_total_volume_internal();
        // } else {
        //     pool.volume_usd_coin_b
        //  stats.add_total_volume_internal();
        // }

        let swap_event = SwapEvent {
            atob: a2b,
            pool: sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool),
            partner: partner_id,
            amount_in: swap_result.amount_in + swap_result.fee_amount,
            amount_out: swap_result.amount_out,
            fullsail_fee_amount: swap_result.gauge_fee_amount,
            protocol_fee_amount: swap_result.protocol_fee_amount,
            ref_fee_amount: swap_result.ref_fee_amount,
            fee_amount: swap_result.fee_amount,
            vault_a_amount: sui::balance::value<CoinTypeA>(&pool.coin_a),
            vault_b_amount: sui::balance::value<CoinTypeB>(&pool.coin_b),
            before_sqrt_price: pool.current_sqrt_price,
            after_sqrt_price: pool.current_sqrt_price,
            steps: swap_result.steps,
        };
        sui::event::emit<SwapEvent>(swap_event);
        let receipt = FlashSwapReceipt<CoinTypeA, CoinTypeB> {
            pool_id: sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool),
            a2b: a2b,
            partner_id: partner_id,
            pay_amount: swap_result.amount_in + swap_result.fee_amount,
            fee_amount: swap_result.fee_amount,
            protocol_fee_amount: swap_result.protocol_fee_amount,
            ref_fee_amount: swap_result.ref_fee_amount,
            gauge_fee_amount: swap_result.gauge_fee_amount,
        };
        (balance_a, balance_b, receipt)
    }

    /// Executes a flash swap operation with partner fees.
    /// This function is similar to flash_swap but includes partner fee calculations.
    /// The partner's referral fee rate is determined based on the current timestamp.
    ///
    /// # Arguments
    /// * `global_config` - Reference to the global configuration containing protocol parameters
    /// * `pool` - Reference to the pool to perform the swap in
    /// * `partner` - Reference to the partner for fee calculation
    /// * `a2b` - Boolean indicating the swap direction (true for A to B, false for B to A)
    /// * `by_amount_in` - Boolean indicating whether the amount parameter represents input or output amount
    /// * `amount` - The amount to swap (either input or output amount based on by_amount_in)
    /// * `sqrt_price_limit` - The price limit for the swap in square root form
    /// * `stats` - Reference to the pool statistics to update
    /// * `price_provider` - Reference to the price provider for price calculations
    /// * `clock` - Reference to the clock for timestamp calculations
    ///
    /// # Returns
    /// A tuple containing:
    /// * Balance of CoinTypeA (output if B to A, zero if A to B)
    /// * Balance of CoinTypeB (output if A to B, zero if B to A)
    /// * FlashSwapReceipt containing swap details and fees
    ///
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    /// * If the package version is invalid
    /// * If the amount is zero (error code: 0)
    /// * If the price limit is invalid (error code: 11)
    /// * If no output amount is received (error code: 18)
    public fun flash_swap_with_partner<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        partner: &clmm_pool::partner::Partner,
        a2b: bool,
        by_amount_in: bool,
        amount: u64,
        sqrt_price_limit: u128,
        stats: &mut clmm_pool::stats::Stats,
        price_provider: &price_provider::price_provider::PriceProvider,
        clock: &sui::clock::Clock
    ): (sui::balance::Balance<CoinTypeA>, sui::balance::Balance<CoinTypeB>, FlashSwapReceipt<CoinTypeA, CoinTypeB>) {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        flash_swap_internal<CoinTypeA, CoinTypeB>(
            pool,
            global_config,
            sui::object::id<clmm_pool::partner::Partner>(partner),
            clmm_pool::partner::current_ref_fee_rate(partner, sui::clock::timestamp_ms(clock) / 1000),
            a2b,
            by_amount_in,
            amount,
            sqrt_price_limit,
            stats,
            price_provider,
            clock
        )
    }

    /// Returns all growth accumulators within a specified tick range.
    /// This function calculates the accumulated values for fees, rewards, points, and fullsail distribution
    /// between the specified lower and upper ticks.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the growth accumulators
    /// * `tick_lower` - The lower tick of the range
    /// * `tick_upper` - The upper tick of the range
    ///
    /// # Returns
    /// A tuple containing:
    /// * Fee growth for token A
    /// * Fee growth for token B
    /// * Vector of reward growths for each rewarder
    /// * Points growth
    /// * Fullsail distribution growth
    public fun get_all_growths_in_tick_range<CoinTypeA, CoinTypeB>(
        pool: &Pool<CoinTypeA, CoinTypeB>,
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32
    ): (u128, u128, vector<u128>, u128, u128) {
        let tick_lower_info = clmm_pool::tick::try_borrow_tick(&pool.tick_manager, tick_lower);
        let tick_upper_info = clmm_pool::tick::try_borrow_tick(&pool.tick_manager, tick_upper);
        let (fee_growth_a, fee_growth_b) = clmm_pool::tick::get_fee_in_range(
            pool.current_tick_index,
            pool.fee_growth_global_a,
            pool.fee_growth_global_b,
            tick_lower_info,
            tick_upper_info
        );
        (
            fee_growth_a,
            fee_growth_b,
            clmm_pool::tick::get_rewards_in_range(
                pool.current_tick_index,
                clmm_pool::rewarder::rewards_growth_global(&pool.rewarder_manager),
                tick_lower_info,
                tick_upper_info
            ),
            clmm_pool::tick::get_points_in_range(
                pool.current_tick_index,
                clmm_pool::rewarder::points_growth_global(&pool.rewarder_manager),
                tick_lower_info,
                tick_upper_info
            ),
            clmm_pool::tick::get_fullsail_distribution_growth_in_range(
                pool.current_tick_index,
                pool.fullsail_distribution_growth_global,
                tick_lower_info,
                tick_upper_info
            )
        )
    }

    /// Returns the accumulated fees within a specified tick range.
    /// This function calculates the total fees earned for both tokens between the specified ticks.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the fee accumulators
    /// * `tick_lower` - The lower tick of the range
    /// * `tick_upper` - The upper tick of the range
    ///
    /// # Returns
    /// A tuple containing:
    /// * Fee growth for token A
    /// * Fee growth for token B
    public fun get_fee_in_tick_range<CoinTypeA, CoinTypeB>(
        pool: &Pool<CoinTypeA, CoinTypeB>,
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32
    ): (u128, u128) {
        clmm_pool::tick::get_fee_in_range(
            pool.current_tick_index,
            pool.fee_growth_global_a,
            pool.fee_growth_global_b,
            clmm_pool::tick::try_borrow_tick(&pool.tick_manager, tick_lower),
            clmm_pool::tick::try_borrow_tick(&pool.tick_manager, tick_upper)
        )
    }

    /// Calculates the liquidity and token amounts for a given input amount.
    /// This function determines the liquidity and corresponding token amounts needed
    /// for a position within a specified price range.
    ///
    /// # Arguments
    /// * `tick_lower` - The lower tick of the price range
    /// * `tick_upper` - The upper tick of the price range
    /// * `current_tick` - The current tick of the pool
    /// * `current_sqrt_price` - The current square root price of the pool
    /// * `amount` - The input amount to calculate liquidity for
    /// * `a2b` - Boolean indicating the direction (true for A to B, false for B to A)
    ///
    /// # Returns
    /// A tuple containing:
    /// * The calculated liquidity
    /// * Amount of token A needed
    /// * Amount of token B needed
    ///
    /// # Aborts
    /// * If current_tick is not within the specified range (error code: 19)
    public fun get_liquidity_from_amount(
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32,
        current_tick: integer_mate::i32::I32,
        current_sqrt_price: u128,
        amount: u64,
        a2b: bool
    ): (u128, u64, u64) {
        if (a2b) {
            let (liquidity_a, amount_b) = if (integer_mate::i32::lt(current_tick, tick_lower)) {
                (clmm_pool::clmm_math::get_liquidity_from_a(
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_lower),
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_upper),
                    amount,
                    false
                ), 0)
            } else {
                assert!(integer_mate::i32::lt(current_tick, tick_upper), 19);
                let liquidity_current = clmm_pool::clmm_math::get_liquidity_from_a(
                    current_sqrt_price,
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_upper),
                    amount,
                    false
                );
                (liquidity_current, clmm_pool::clmm_math::get_delta_b(
                    current_sqrt_price,
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_lower),
                    liquidity_current,
                    true
                ))
            };
            (liquidity_a, amount, amount_b)
        } else {
            let (liquidity_b, amount_a) = if (integer_mate::i32::gte(current_tick, tick_upper)) {
                (clmm_pool::clmm_math::get_liquidity_from_b(
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_lower),
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_upper),
                    amount,
                    false
                ), 0)
            } else {
                assert!(integer_mate::i32::gte(current_tick, tick_lower), 19);
                let liquidity_current = clmm_pool::clmm_math::get_liquidity_from_b(
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_lower),
                    current_sqrt_price,
                    amount,
                    false
                );
                (liquidity_current, clmm_pool::clmm_math::get_delta_a(
                    current_sqrt_price,
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_upper),
                    liquidity_current,
                    true
                ))
            };
            (liquidity_b, amount_a, amount)
        }
    }

    /// Returns the ID of the fullsail distribution gauger.
    /// This function retrieves the ID of the gauger responsible for fullsail distribution in the pool.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the gauger ID
    ///
    /// # Returns
    /// The ID of the fullsail distribution gauger
    ///
    /// # Aborts
    /// * If the gauger ID is not set (error code: 9223379295349506047)
    public fun get_fullsail_distribution_gauger_id<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): sui::object::ID {
        assert!(std::option::is_some<sui::object::ID>(&pool.fullsail_distribution_gauger_id), 9223379295349506047);
        *std::option::borrow<sui::object::ID>(&pool.fullsail_distribution_gauger_id)
    }

    /// Returns the global fullsail distribution growth accumulator.
    /// This value represents the total fullsail distribution growth across all positions.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the growth accumulator
    ///
    /// # Returns
    /// The global fullsail distribution growth value
    public fun get_fullsail_distribution_growth_global<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): u128 {
        pool.fullsail_distribution_growth_global
    }

    /// Returns the fullsail distribution growth within a specified tick range.
    /// This function calculates the accumulated fullsail distribution between the specified ticks.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the growth accumulator
    /// * `tick_lower` - The lower tick of the range
    /// * `tick_upper` - The upper tick of the range
    /// * `growth_global` - Optional global growth value to use for calculation
    ///
    /// # Returns
    /// The fullsail distribution growth within the specified range
    ///
    /// # Aborts
    /// * If the tick range is invalid (error code: 9223378947457155071)
    public fun get_fullsail_distribution_growth_inside<CoinTypeA, CoinTypeB>(
        pool: &Pool<CoinTypeA, CoinTypeB>,
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32,
        mut growth_global: u128
    ): u128 {
        assert!(check_tick_range(tick_lower, tick_upper), 9223378947457155071);
        if (growth_global == 0) {
            growth_global = pool.fullsail_distribution_growth_global;
        };
        clmm_pool::tick::get_fullsail_distribution_growth_in_range(
            pool.current_tick_index,
            growth_global,
            std::option::some<clmm_pool::tick::Tick>(*borrow_tick<CoinTypeA, CoinTypeB>(pool, tick_lower)),
            std::option::some<clmm_pool::tick::Tick>(*borrow_tick<CoinTypeA, CoinTypeB>(pool, tick_upper))
        )
    }

    /// Returns the timestamp of the last fullsail distribution update.
    /// This value indicates when the fullsail distribution parameters were last modified.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the last update timestamp
    ///
    /// # Returns
    /// The timestamp of the last fullsail distribution update
    public fun get_fullsail_distribution_last_updated<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): u64 {
        pool.fullsail_distribution_last_updated
    }

    /// Returns the fullsail distribution reserve amount.
    /// This value represents the amount of rewards reserved for distribution.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the reserve amount
    ///
    /// # Returns
    /// The fullsail distribution reserve amount
    public fun get_fullsail_distribution_reserve<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): u64 {
        pool.fullsail_distribution_reserve
    }

    /// Returns the fullsail distribution rollover amount.
    /// This value represents the amount of rewards that were not distributed in the previous period.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the rollover amount
    ///
    /// # Returns
    /// The fullsail distribution rollover amount
    public fun get_fullsail_distribution_rollover<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): u64 {
        pool.fullsail_distribution_rollover
    }

    /// Returns the total staked liquidity for fullsail distribution.
    /// This value represents the total amount of liquidity that is currently staked in the fullsail distribution system.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the staked liquidity
    ///
    /// # Returns
    /// The total staked liquidity for fullsail distribution
    public fun get_fullsail_distribution_staked_liquidity<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): u128 {
        pool.fullsail_distribution_staked_liquidity
    }

    /// Returns the accumulated points within a specified tick range.
    /// This function calculates the total points earned between the specified ticks.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the points accumulator
    /// * `tick_lower` - The lower tick of the range
    /// * `tick_upper` - The upper tick of the range
    ///
    /// # Returns
    /// The points accumulated within the specified range
    public fun get_points_in_tick_range<CoinTypeA, CoinTypeB>(
        pool: &Pool<CoinTypeA, CoinTypeB>,
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32
    ): u128 {
        clmm_pool::tick::get_points_in_range(
            pool.current_tick_index,
            clmm_pool::rewarder::points_growth_global(&pool.rewarder_manager),
            clmm_pool::tick::try_borrow_tick(&pool.tick_manager, tick_lower),
            clmm_pool::tick::try_borrow_tick(&pool.tick_manager, tick_upper)
        )
    }

    /// Returns the current token amounts for a position.
    /// This function calculates the actual token amounts based on the position's liquidity
    /// and the current pool state.
    ///
    /// # Arguments
    /// * `pool_state` - Reference to the pool containing the position
    /// * `position_id` - ID of the position to get amounts for
    ///
    /// # Returns
    /// A tuple containing:
    /// * Amount of token A in the position
    /// * Amount of token B in the position
    public fun get_position_amounts<CoinTypeA, CoinTypeB>(
        pool_state: &mut Pool<CoinTypeA, CoinTypeB>,
        position_id: sui::object::ID
    ): (u64, u64) {
        let current_position = clmm_pool::position::borrow_position_info(&pool_state.position_manager, position_id);
        let (tick_lower, tick_upper) = clmm_pool::position::info_tick_range(current_position);
        get_amount_by_liquidity(
            tick_lower,
            tick_upper, 
            pool_state.current_tick_index,
            pool_state.current_sqrt_price,
            clmm_pool::position::info_liquidity(current_position),
            false
        )
    }

    /// Returns the fee amounts for a position.
    /// This function calculates the fee amounts earned by the position based on the current pool state.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the position
    /// * `position_id` - ID of the position to get fees for
    ///
    /// # Returns
    /// A tuple containing:
    /// * Amount of fees earned in token A
    /// * Amount of fees earned in token B
    public fun get_position_fee<CoinTypeA, CoinTypeB>(
        pool: &Pool<CoinTypeA, CoinTypeB>,
        position_id: sui::object::ID
    ): (u64, u64) {
        clmm_pool::position::info_fee_owned(
            clmm_pool::position::borrow_position_info(&pool.position_manager, position_id)
        )
    }

    /// Returns the points earned by a position.
    /// This function calculates the points earned by the position based on the current pool state.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the position
    /// * `position_id` - ID of the position to get points for
    ///
    /// # Returns
    /// The points earned by the position
    public fun get_position_points<CoinTypeA, CoinTypeB>(
        pool: &Pool<CoinTypeA, CoinTypeB>, 
        position_id: sui::object::ID
    ): u128 {
        clmm_pool::position::info_points_owned(
            clmm_pool::position::borrow_position_info(&pool.position_manager, position_id)
        )
    }
    
    /// Returns the rewards earned by a position for a specific reward token.
    /// This function calculates the rewards earned by the position for a given reward token based on the current pool state.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the position
    /// * `position_id` - ID of the position to get rewards for
    /// * `rewarder_type` - Type of reward token to get rewards for
    ///
    /// # Returns
    /// The rewards earned by the position for the specified reward token
    public fun get_position_reward<CoinTypeA, CoinTypeB, RewardCoinType>(
        pool: &Pool<CoinTypeA, CoinTypeB>,
        position_id: sui::object::ID
    ): u64 {
        let mut rewarder_idx = clmm_pool::rewarder::rewarder_index<RewardCoinType>(&pool.rewarder_manager);
        assert!(std::option::is_some<u64>(&rewarder_idx), 17);
        let rewards = clmm_pool::position::rewards_amount_owned(&pool.position_manager, position_id);
        *std::vector::borrow<u64>(&rewards, std::option::extract<u64>(&mut rewarder_idx))
    }

    /// Returns the rewards earned by a position for all reward tokens.
    /// This function calculates the rewards earned by the position for all reward tokens based on the current pool state.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the position
    /// * `position_id` - ID of the position to get rewards for
    ///
    /// # Returns
    /// A vector containing the rewards earned by the position for each reward token
    public fun get_position_rewards<CoinTypeA, CoinTypeB>(
        pool: &Pool<CoinTypeA, CoinTypeB>, 
        position_id: sui::object::ID
    ): vector<u64> {
        clmm_pool::position::rewards_amount_owned(&pool.position_manager, position_id)
    }

    /// Returns the rewards earned by a position for all reward tokens within a specified tick range.
    /// This function calculates the rewards earned by the position for all reward tokens between the specified ticks.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the position
    /// * `tick_lower` - The lower tick of the range
    /// * `tick_upper` - The upper tick of the range
    ///
    /// # Returns
    /// A vector containing the rewards earned by the position for each reward token
    public fun get_rewards_in_tick_range<CoinTypeA, CoinTypeB>(
        pool: &Pool<CoinTypeA, CoinTypeB>,
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32
    ): vector<u128> {
        clmm_pool::tick::get_rewards_in_range(
            pool.current_tick_index,
            clmm_pool::rewarder::rewards_growth_global(&pool.rewarder_manager),
            clmm_pool::tick::try_borrow_tick(&pool.tick_manager, tick_lower),
            clmm_pool::tick::try_borrow_tick(&pool.tick_manager, tick_upper)
        )
    }

    /// Initializes a new pool by transferring the publisher to the sender.
    /// This function is called during pool creation to set up the initial state.
    ///
    /// # Arguments
    /// * `pool` - The pool to initialize
    /// * `ctx` - Reference to the transaction context
    fun init(pool: POOL, ctx: &mut sui::tx_context::TxContext) {
        sui::transfer::public_transfer<sui::package::Publisher>(
            sui::package::claim<POOL>(pool, ctx),
            sui::tx_context::sender(ctx)
        );
    }

    /// Initializes the fullsail distribution gauge for a pool.
    /// This function sets up the gauge capability for fullsail distribution rewards.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool to initialize the gauge for
    /// * `gauge_cap` - Reference to the gauge capability
    ///
    /// # Aborts
    /// * If the pool ID in the gauge capability does not match the pool's ID (error code: 9223379334004211711)
    public fun init_fullsail_distribution_gauge<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        gauge_cap: &gauge_cap::gauge_cap::GaugeCap
    ) {
        assert!(
            gauge_cap::gauge_cap::get_pool_id(gauge_cap) == sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool),
            9223379334004211711
        );
        std::option::fill<sui::object::ID>(
            &mut pool.fullsail_distribution_gauger_id,
            gauge_cap::gauge_cap::get_gauge_id(gauge_cap)
        );
    }

    /// Initializes a new rewarder for the pool.
    /// This function adds a new reward token type to the pool's reward system.
    ///
    /// # Arguments
    /// * `global_config` - Reference to the global configuration
    /// * `pool` - Reference to the pool to add the rewarder to
    /// * `ctx` - Reference to the transaction context
    ///
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    public fun initialize_rewarder<CoinTypeA, CoinTypeB, RewardCoinType>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        ctx: &mut sui::tx_context::TxContext
    ) {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        clmm_pool::config::check_rewarder_manager_role(global_config, sui::tx_context::sender(ctx));
        clmm_pool::rewarder::add_rewarder<RewardCoinType>(&mut pool.rewarder_manager);
        let event = AddRewarderEvent {
            pool: sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool),
            rewarder_type: std::type_name::get<RewardCoinType>(),
        };
        sui::event::emit<AddRewarderEvent>(event);
    }

    /// Returns whether the pool is currently paused.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool to check
    ///
    /// # Returns
    /// True if the pool is paused, false otherwise
    public fun is_pause<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): bool {
        pool.is_pause
    }

    /// Returns the fullsail distribution gauger fee for the pool.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the gauger fee
    ///
    /// # Returns
    /// The fullsail distribution gauger fee structure containing fees for both tokens
    public fun fullsail_distribution_gauger_fee<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): PoolFee {
        PoolFee {
            coin_a: pool.fullsail_distribution_gauger_fee.coin_a,
            coin_b: pool.fullsail_distribution_gauger_fee.coin_b,
        }
    }

    /// Marks a position as unstaked in the fullsail distribution system.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the position
    /// * `gauge_cap` - Reference to the gauge capability
    /// * `position_id` - ID of the position to mark as unstaked
    ///
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    public fun mark_position_unstaked<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        gauge_cap: &gauge_cap::gauge_cap::GaugeCap,
        position_id: sui::object::ID
    ) {
        assert!(!pool.is_pause, 13);
        check_gauge_cap<CoinTypeA, CoinTypeB>(pool, gauge_cap);
        clmm_pool::position::mark_position_staked(&mut pool.position_manager, position_id, false);
    }

    /// Pauses the pool, preventing all operations except unpausing.
    /// This function can only be called by the pool manager role.
    ///
    /// # Arguments
    /// * `global_config` - Reference to the global configuration
    /// * `pool` - Reference to the pool to pause
    /// * `ctx` - Reference to the transaction context
    ///
    /// # Aborts
    /// * If the pool is already paused (error code: 9223376739843964927)
    public fun pause<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        ctx: &mut sui::tx_context::TxContext
    ) {
        clmm_pool::config::checked_package_version(global_config);
        clmm_pool::config::check_pool_manager_role(global_config, sui::tx_context::sender(ctx));
        assert!(!pool.is_pause, 9223376739843964927);
        pool.is_pause = true;
    }

    /// Returns the fee amounts for both tokens in a pool fee structure.
    ///
    /// # Arguments
    /// * `pool_fee` - Reference to the pool fee structure
    ///
    /// # Returns
    /// A tuple containing:
    /// * Fee amount for token A
    /// * Fee amount for token B
    public fun pool_fee_a_b(pool_fee: &PoolFee): (u64, u64) {
        (pool_fee.coin_a, pool_fee.coin_b)
    }

    /// Returns a reference to the position manager of the pool.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the position manager
    ///
    /// # Returns
    /// A reference to the pool's position manager
    public fun position_manager<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): &clmm_pool::position::PositionManager {
        &pool.position_manager
    }

    /// Returns the protocol fee amounts for both tokens.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the protocol fees
    ///
    /// # Returns
    /// A tuple containing:
    /// * Protocol fee amount for token A
    /// * Protocol fee amount for token B
    public fun protocol_fee<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): (u64, u64) {
        (pool.fee_protocol_coin_a, pool.fee_protocol_coin_b)
    }
    
    /// Removes liquidity from a position in the pool.
    /// This function calculates the token amounts to return based on the liquidity being removed
    /// and updates the position's state accordingly.
    ///
    /// # Arguments
    /// * `global_config` - Reference to the global configuration
    /// * `pool` - Reference to the pool containing the position
    /// * `position` - Reference to the position to remove liquidity from
    /// * `liquidity` - The amount of liquidity to remove
    /// * `clock` - Reference to the clock for timestamp calculations
    ///
    /// # Returns
    /// A tuple containing:
    /// * Balance of token A to return
    /// * Balance of token B to return
    ///
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    /// * If the liquidity amount is zero or negative (error code: 3)
    public fun remove_liquidity<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        position: &mut clmm_pool::position::Position,
        liquidity: u128,
        clock: &sui::clock::Clock
    ): (sui::balance::Balance<CoinTypeA>, sui::balance::Balance<CoinTypeB>) {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        assert!(liquidity > 0, 3);
        
        clmm_pool::rewarder::settle(
            &mut pool.rewarder_manager, 
            pool.liquidity, 
            sui::clock::timestamp_ms(clock) / 1000
        );

        let (tick_lower, tick_upper) = clmm_pool::position::tick_range(position);
        
        let (
            fee_growth_a,
            fee_growth_b,
            rewards_growth,
            points_growth,
            fullsail_growth,
        ) = get_all_growths_in_tick_range<CoinTypeA, CoinTypeB>(
            pool,
            tick_lower,
            tick_upper
        );

        clmm_pool::tick::decrease_liquidity(
            &mut pool.tick_manager,
            pool.current_tick_index,
            tick_lower,
            tick_upper,
            liquidity,
            pool.fee_growth_global_a,
            pool.fee_growth_global_b,
            clmm_pool::rewarder::points_growth_global(&pool.rewarder_manager),
            clmm_pool::rewarder::rewards_growth_global(&pool.rewarder_manager),
            pool.fullsail_distribution_growth_global
        );

        if (integer_mate::i32::lte(tick_lower, pool.current_tick_index) && 
            integer_mate::i32::lt(pool.current_tick_index, tick_upper)) {
            pool.liquidity = pool.liquidity - liquidity;
        };

        let (amount_a, amount_b) = get_amount_by_liquidity(
            tick_lower,
            tick_upper,
            pool.current_tick_index,
            pool.current_sqrt_price,
            liquidity,
            false
        );

        let event = RemoveLiquidityEvent {
            pool: sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool),
            position: sui::object::id<clmm_pool::position::Position>(position),
            tick_lower,
            tick_upper,
            liquidity,
            after_liquidity: clmm_pool::position::decrease_liquidity(
                &mut pool.position_manager,
                position,
                liquidity,
                fee_growth_a,
                fee_growth_b,
                points_growth,
                rewards_growth,
                fullsail_growth
            ),
            amount_a,
            amount_b,
        };

        sui::event::emit<RemoveLiquidityEvent>(event);

        (
            sui::balance::split<CoinTypeA>(&mut pool.coin_a, amount_a),
            sui::balance::split<CoinTypeB>(&mut pool.coin_b, amount_b)
        )
    }

    /// Repays the liquidity added to a pool.
    /// This function verifies and processes the repayment of tokens after adding liquidity.
    ///
    /// # Arguments
    /// * `global_config` - Reference to the global configuration
    /// * `pool` - Reference to the pool to repay liquidity to
    /// * `balance_a` - Balance of token A to repay
    /// * `balance_b` - Balance of token B to repay
    /// * `receipt` - Receipt containing the original liquidity addition details
    ///
    /// # Aborts
    /// * If the balance of token A does not match the expected amount (error code: 0)
    /// * If the balance of token B does not match the expected amount (error code: 0)
    /// * If the pool ID in the receipt does not match the pool's ID (error code: 12)
    public fun repay_add_liquidity<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        balance_a: sui::balance::Balance<CoinTypeA>,
        balance_b: sui::balance::Balance<CoinTypeB>,
        receipt: AddLiquidityReceipt<CoinTypeA, CoinTypeB>
    ) {
        clmm_pool::config::checked_package_version(global_config);
        let AddLiquidityReceipt {
            pool_id,
            amount_a,
            amount_b,
        } = receipt;
        assert!(sui::balance::value<CoinTypeA>(&balance_a) == amount_a, 0);
        assert!(sui::balance::value<CoinTypeB>(&balance_b) == amount_b, 0);
        assert!(sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool) == pool_id, 12);
        sui::balance::join<CoinTypeA>(&mut pool.coin_a, balance_a);
        sui::balance::join<CoinTypeB>(&mut pool.coin_b, balance_b);
    }

    /// Repays a flash swap operation.
    /// This function processes the repayment of tokens after a flash swap operation.
    ///
    /// # Arguments
    /// * `global_config` - Reference to the global configuration
    /// * `pool` - Reference to the pool to repay the flash swap to
    /// * `balance_a` - Balance of token A to repay
    /// * `balance_b` - Balance of token B to repay
    /// * `receipt` - Receipt containing the flash swap operation details
    ///
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    /// * If the pool ID in the receipt does not match the pool's ID (error code: 14)
    /// * If the reference fee amount is non-zero (error code: 14)
    /// * If the balance of token A does not match the expected amount (error code: 0)
    /// * If the balance of token B does not match the expected amount (error code: 0)
    public fun repay_flash_swap<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        balance_a: sui::balance::Balance<CoinTypeA>,
        balance_b: sui::balance::Balance<CoinTypeB>,
        receipt: FlashSwapReceipt<CoinTypeA, CoinTypeB>
    ) {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        let FlashSwapReceipt {
            pool_id,
            a2b,
            partner_id: _,
            pay_amount,
            fee_amount: _,
            protocol_fee_amount: _,
            ref_fee_amount,
            gauge_fee_amount: _,
        } = receipt;
        assert!(sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool) == pool_id, 14);
        assert!(ref_fee_amount == 0, 14);
        if (a2b) {
            assert!(sui::balance::value<CoinTypeA>(&balance_a) == pay_amount, 0);
            sui::balance::join<CoinTypeA>(&mut pool.coin_a, balance_a);
            sui::balance::destroy_zero<CoinTypeB>(balance_b);
        } else {
            assert!(sui::balance::value<CoinTypeB>(&balance_b) == pay_amount, 0);
            sui::balance::join<CoinTypeB>(&mut pool.coin_b, balance_b);
            sui::balance::destroy_zero<CoinTypeA>(balance_a);
        };
    }

    /// Repays a flash swap operation with partner referral fees.
    /// Processes the repayment of tokens after a flash swap operation,
    /// handling partner referral fees if applicable.
    ///
    /// # Arguments
    /// * `global_config` - Reference to the global configuration for version checking
    /// * `pool` - Reference to the pool to repay the flash swap to
    /// * `partner` - Reference to the partner to receive referral fees
    /// * `balance_a` - Balance of token A to repay
    /// * `balance_b` - Balance of token B to repay
    /// * `receipt` - Receipt containing the flash swap operation details
    ///
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    /// * If the pool ID in the receipt does not match the pool's ID (error code: 14)
    /// * If the partner ID in the receipt does not match the partner's ID (error code: 14)
    /// * If the balance of token A does not match the expected amount (error code: 0)
    /// * If the balance of token B does not match the expected amount (error code: 0)
    public fun repay_flash_swap_with_partner<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        partner: &mut clmm_pool::partner::Partner,
        mut balance_a: sui::balance::Balance<CoinTypeA>,
        mut balance_b: sui::balance::Balance<CoinTypeB>,
        receipt: FlashSwapReceipt<CoinTypeA, CoinTypeB>
    ) {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        let FlashSwapReceipt {
            pool_id: pool_id,
            a2b: a2b,
            partner_id: partner_id,
            pay_amount: pay_amount,
            fee_amount: _,
            protocol_fee_amount: _,
            ref_fee_amount: ref_fee_amount,
            gauge_fee_amount: _,
        } = receipt;
        assert!(sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool) == pool_id, 14);
        assert!(sui::object::id<clmm_pool::partner::Partner>(partner) == partner_id, 15);
        if (a2b) {
            assert!(sui::balance::value<CoinTypeA>(&balance_a) == pay_amount, 0);
            if (ref_fee_amount > 0) {
                clmm_pool::partner::receive_ref_fee<CoinTypeA>(partner, sui::balance::split<CoinTypeA>(&mut balance_a, ref_fee_amount));
            };
            sui::balance::join<CoinTypeA>(&mut pool.coin_a, balance_a);
            sui::balance::destroy_zero<CoinTypeB>(balance_b);
        } else {
            assert!(sui::balance::value<CoinTypeB>(&balance_b) == pay_amount, 0);
            if (ref_fee_amount > 0) {
                clmm_pool::partner::receive_ref_fee<CoinTypeB>(partner, sui::balance::split<CoinTypeB>(&mut balance_b, ref_fee_amount));
            };
            sui::balance::join<CoinTypeB>(&mut pool.coin_b, balance_b);
            sui::balance::destroy_zero<CoinTypeA>(balance_a);
        };
    }

    /// Returns a reference to the pool's rewarder manager.
    /// The rewarder manager is responsible for handling reward distributions and
    /// managing reward-related operations within the pool.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the rewarder manager
    ///
    /// # Returns
    /// * Reference to the RewarderManager instance associated with the pool
    public fun rewarder_manager<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): &clmm_pool::rewarder::RewarderManager {
        &pool.rewarder_manager
    }

    /// Sets up display metadata for the pool object.
    /// Creates and configures display information for the pool in the Sui object system,
    /// including basic pool information and associated resource links.
    ///
    /// # Arguments
    /// * `global_config` - Reference to the global configuration for version checking
    /// * `publisher` - Reference to the package publisher for display creation
    /// * `name` - Name of the pool to be displayed
    /// * `description` - Detailed description of the pool
    /// * `image_url` - URL of the pool's image representation
    /// * `link` - URL to the pool's main interface
    /// * `project_url` - URL to the project's documentation or website
    /// * `creator` - Information about the pool's creator
    /// * `ctx` - Mutable reference to transaction context
    ///
    /// # Aborts
    /// * If the package version check fails
    ///
    /// # Effects
    /// * Creates a new Display object for the pool
    /// * Transfers the Display object to the transaction sender
    public fun set_display<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        publisher: &sui::package::Publisher,
        name: std::string::String,
        description: std::string::String,
        image_url: std::string::String,
        link: std::string::String,
        project_url: std::string::String,
        creator: std::string::String,
        ctx: &mut sui::tx_context::TxContext
    ) {
        clmm_pool::config::checked_package_version(global_config);
        let mut keys = std::vector::empty<std::string::String>();
        std::vector::push_back<std::string::String>(&mut keys, std::string::utf8(b"name"));
        std::vector::push_back<std::string::String>(&mut keys, std::string::utf8(b"coin_a"));
        std::vector::push_back<std::string::String>(&mut keys, std::string::utf8(b"coin_b"));
        std::vector::push_back<std::string::String>(&mut keys, std::string::utf8(b"link"));
        std::vector::push_back<std::string::String>(&mut keys, std::string::utf8(b"image_url"));
        std::vector::push_back<std::string::String>(&mut keys, std::string::utf8(b"description"));
        std::vector::push_back<std::string::String>(&mut keys, std::string::utf8(b"project_url"));
        std::vector::push_back<std::string::String>(&mut keys, std::string::utf8(b"creator"));
        let mut values = std::vector::empty<std::string::String>();
        std::vector::push_back<std::string::String>(&mut values, name);
        std::vector::push_back<std::string::String>(
            &mut values,
            std::string::from_ascii(std::type_name::into_string(std::type_name::get<CoinTypeA>()))
        );
        std::vector::push_back<std::string::String>(
            &mut values,
            std::string::from_ascii(std::type_name::into_string(std::type_name::get<CoinTypeB>()))
        );
        std::vector::push_back<std::string::String>(&mut values, link);
        std::vector::push_back<std::string::String>(&mut values, image_url);
        std::vector::push_back<std::string::String>(&mut values, description);
        std::vector::push_back<std::string::String>(&mut values, project_url);
        std::vector::push_back<std::string::String>(&mut values, creator);
        let mut display = sui::display::new_with_fields<Pool<CoinTypeA, CoinTypeB>>(publisher, keys, values, ctx);
        sui::display::update_version<Pool<CoinTypeA, CoinTypeB>>(&mut display);
        sui::transfer::public_transfer<sui::display::Display<Pool<CoinTypeA, CoinTypeB>>>(display, sui::tx_context::sender(ctx));
    }

    /// Splits fees between staked and unstaked portions of liquidity.
    /// Calculates fee distribution based on growth inside and outside the given tick range,
    /// and takes into account the unstaked fee rate.
    ///
    /// # Arguments
    /// * `fee_amount` - Total fee amount to be distributed
    /// * `total_growth` - Total fee growth in the pool
    /// * `growth_inside` - Fee growth inside the given tick range
    /// * `unstaked_fee_rate` - Fee rate for unstaked liquidity
    ///
    /// # Returns
    /// A tuple of two values:
    /// * First value - fee amount for staked liquidity
    /// * Second value - fee amount for unstaked liquidity
    fun split_fees(
        fee_amount: u64,
        total_growth: u128,
        growth_inside: u128,
        unstaked_fee_rate: u64
    ): (u64, u64) {
        let inside_amount = integer_mate::full_math_u128::mul_div_ceil(
            fee_amount as u128,
            growth_inside,
            total_growth
        );
        let (staked_amount, unstaked_amount) = apply_unstaked_fees(
            (fee_amount as u128) - inside_amount,
            inside_amount,
            unstaked_fee_rate
        );
        (staked_amount as u64, unstaked_amount as u64)
    }

    /// Stakes liquidity in the fullsail distribution system for a given tick range.
    /// This function allows users to participate in the fullsail distribution rewards program
    /// by staking their liquidity position within a specified tick range.
    ///
    /// # Arguments
    /// * `pool` - Mutable reference to the pool where liquidity will be staked
    /// * `gauge_cap` - Reference to the gauge capability for authorization
    /// * `liquidity` - Amount of liquidity to stake
    /// * `tick_lower` - Lower bound of the tick range for staking
    /// * `tick_upper` - Upper bound of the tick range for staking
    /// * `clock` - Reference to the Sui clock for timestamp verification
    ///
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    /// * If the liquidity amount is zero (error code: 9223379140730683391)
    /// * If the gauge capability verification fails
    public fun stake_in_fullsail_distribution<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        gauge_cap: &gauge_cap::gauge_cap::GaugeCap, 
        liquidity: u128,
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32,
        clock: &sui::clock::Clock
    ) {
        assert!(!pool.is_pause, 13);
        assert!(liquidity != 0, 9223379140730683391);
        check_gauge_cap<CoinTypeA, CoinTypeB>(pool, gauge_cap);
        update_fullsail_distribution_internal<CoinTypeA, CoinTypeB>(
            pool,
            integer_mate::i128::from(liquidity),
            tick_lower,
            tick_upper,
            clock
        );
    }

    /// Returns the amount of tokens sent in the swap step.
    /// This function extracts the amount_in field from the SwapStepResult,
    /// representing the actual amount of tokens sent in the swap operation.
    ///
    /// # Arguments
    /// * `result` - Reference to the SwapStepResult structure containing swap step details
    ///
    /// # Returns
    /// The amount of input tokens from the swap step as a u64 value
    public fun step_swap_result_amount_in(result: &SwapStepResult): u64 {
        result.amount_in
    }

    /// Returns the amount of tokens received from the swap step.
    /// This function extracts the amount_out field from the SwapStepResult,
    /// representing the actual amount of tokens received in the swap operation.
    ///
    /// # Arguments
    /// * `result` - Reference to the SwapStepResult structure containing swap step details
    ///
    /// # Returns
    /// The amount of output tokens from the swap step as a u64 value
    public fun step_swap_result_amount_out(result: &SwapStepResult): u64 {
        result.amount_out
    }

    /// Returns the current liquidity in the pool after the swap step.
    /// Provides the liquidity value that remains in the pool after
    /// the swap operation has been executed.
    ///
    /// # Arguments
    /// * `result` - Reference to the SwapStepResult structure
    ///
    /// # Returns
    /// The current liquidity value as a u128
    public fun step_swap_result_current_liquidity(result: &SwapStepResult): u128 {
        result.current_liquidity
    }

    /// Returns the current square root price after the swap step.
    /// This represents the updated price after the swap operation
    /// has been completed.
    ///
    /// # Arguments
    /// * `result` - Reference to the SwapStepResult structure
    ///
    /// # Returns
    /// The current square root price as a u128
    public fun step_swap_result_current_sqrt_price(result: &SwapStepResult): u128 {
        result.current_sqrt_price
    }

    /// Returns the fee amount collected during the swap step.
    /// Represents the total fees charged for this particular
    /// swap operation.
    ///
    /// # Arguments
    /// * `result` - Reference to the SwapStepResult structure
    ///
    /// # Returns
    /// The fee amount collected as a u64
    public fun step_swap_result_fee_amount(result: &SwapStepResult): u64 {
        result.fee_amount
    }

    /// Returns the remaining amount of tokens that weren't swapped in this step.
    /// This represents any tokens that couldn't be swapped due to price limits
    /// or insufficient liquidity.
    ///
    /// # Arguments
    /// * `result` - Reference to the SwapStepResult structure
    ///
    /// # Returns
    /// The remaining amount of tokens as a u64
    public fun step_swap_result_remainder_amount(result: &SwapStepResult): u64 {
        result.remainder_amount
    }

    /// Returns the target square root price for the swap step.
    /// This represents the price limit that was set for this
    /// particular swap operation.
    ///
    /// # Arguments
    /// * `result` - Reference to the SwapStepResult structure
    ///
    /// # Returns
    /// The target square root price as a u128
    public fun step_swap_result_target_sqrt_price(result: &SwapStepResult): u128 {
        result.target_sqrt_price
    }

    /// Executes a swap operation within the pool.
    /// This function handles the core swap logic, including price calculations,
    /// fee processing, and liquidity adjustments across multiple ticks.
    ///
    /// # Arguments
    /// * `pool` - Mutable reference to the pool where the swap will be executed
    /// * `a2b` - Boolean indicating the swap direction (true for token A to B, false for B to A)
    /// * `by_amount_in` - Boolean indicating whether the amount parameter represents input or output amount
    /// * `sqrt_price_limit` - The price limit for the swap operation as a square root price
    /// * `amount` - The amount of tokens to swap (either input or output depending on by_amount_in)
    /// * `unstaked_fee_rate` - Fee rate applied to unstaked liquidity positions
    /// * `protocol_fee_rate` - Fee rate collected by the protocol
    /// * `ref_fee_rate` - Fee rate for referral rewards
    /// * `clock` - Reference to the Sui clock for timestamp verification
    ///
    /// # Returns
    /// A SwapResult structure containing:
    /// - Amount of tokens input and output
    /// - Fee amounts (protocol, referral, liquidity provider fees)
    /// - Final square root price and tick index
    ///
    /// # Aborts
    /// * If the referral fee rate exceeds 10000 (error code: 16)
    /// * If there are no more ticks available for the swap (error code: 20)
   fun swap_in_pool<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        a2b: bool,
        by_amount_in: bool,
        sqrt_price_limit: u128,
        amount: u64,
        unstaked_fee_rate: u64,
        protocol_fee_rate: u64,
        ref_fee_rate: u64,
        clock: &sui::clock::Clock
    ): SwapResult {
        assert!(ref_fee_rate <= 10000, 16);
        let mut swap_result = default_swap_result();
        let mut remaining_amount = amount;
        let mut next_tick_score = clmm_pool::tick::first_score_for_swap(
            &pool.tick_manager, 
            pool.current_tick_index, 
            a2b
        );
        while (remaining_amount > 0 && pool.current_sqrt_price != sqrt_price_limit) {
            if (move_stl::option_u64::is_none(&next_tick_score)) {
                abort 20
            };
            let (tick_info, next_score) = clmm_pool::tick::borrow_tick_for_swap(
                &pool.tick_manager, 
                move_stl::option_u64::borrow(&next_tick_score), 
                a2b
            );
            next_tick_score = next_score;
            let tick_index = clmm_pool::tick::index(tick_info);
            let tick_sqrt_price = clmm_pool::tick::sqrt_price(tick_info);
            let target_sqrt_price = if (a2b) {
                integer_mate::math_u128::max(sqrt_price_limit, tick_sqrt_price)
            } else {
                integer_mate::math_u128::min(sqrt_price_limit, tick_sqrt_price)
            };
            let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_pool::clmm_math::compute_swap_step(
                pool.current_sqrt_price, 
                target_sqrt_price, 
                pool.liquidity, 
                remaining_amount, 
                pool.fee_rate, 
                a2b, 
                by_amount_in
            );
            if (amount_in != 0 || fee_amount != 0) {
                if (by_amount_in) {
                    let amount_after_in = check_remainer_amount_sub(remaining_amount, amount_in);
                    remaining_amount = check_remainer_amount_sub(amount_after_in, fee_amount);
                } else {
                    remaining_amount = check_remainer_amount_sub(remaining_amount, amount_out);
                };
                let ref_fee_amount = integer_mate::full_math_u64::mul_div_ceil(
                    fee_amount, 
                    ref_fee_rate, 
                    clmm_pool::config::protocol_fee_rate_denom()
                );
                let remaining_fee = fee_amount - ref_fee_amount;
                let mut fee_after_protocol = remaining_fee;
                let mut gauge_fee = 0;
                let mut protocol_fee = 0;
                if (remaining_fee > 0) {
                    let protocol_fee_amount = integer_mate::full_math_u64::mul_div_ceil(
                        remaining_fee, 
                        protocol_fee_rate, 
                        clmm_pool::config::protocol_fee_rate_denom()
                    );
                    protocol_fee = protocol_fee_amount;
                    let remaining_fee_after_protocol = remaining_fee - protocol_fee_amount;
                    fee_after_protocol = remaining_fee_after_protocol;
                    if (remaining_fee_after_protocol > 0) {
                        let (_, gauge_fee_amount) = calculate_fees<CoinTypeA, CoinTypeB>(
                            pool, 
                            remaining_fee_after_protocol, 
                            pool.liquidity, 
                            pool.fullsail_distribution_staked_liquidity, 
                            unstaked_fee_rate
                        );
                        gauge_fee = gauge_fee_amount;
                        fee_after_protocol = remaining_fee_after_protocol - gauge_fee_amount;
                    }
                };
                update_swap_result(
                    &mut swap_result, 
                    amount_in, 
                    amount_out, 
                    fee_amount, 
                    protocol_fee, 
                    ref_fee_amount, 
                    gauge_fee
                );
                if (fee_after_protocol > 0) {
                    update_fee_growth_global<CoinTypeA, CoinTypeB>(pool, fee_after_protocol, a2b);
                };
            };
            if (next_sqrt_price == tick_sqrt_price) {
                pool.current_sqrt_price = target_sqrt_price;
                let next_tick_index = if (a2b) {
                    integer_mate::i32::sub(tick_index, integer_mate::i32::from(1))
                } else {
                    tick_index
                };
                pool.current_tick_index = next_tick_index;
                update_fullsail_distribution_growth_global_internal<CoinTypeA, CoinTypeB>(pool, clock);
                let (new_liquidity, new_staked_liquidity) = clmm_pool::tick::cross_by_swap(
                    &mut pool.tick_manager,
                    tick_index,
                    a2b,
                    pool.liquidity,
                    pool.fullsail_distribution_staked_liquidity,
                    pool.fee_growth_global_a,
                    pool.fee_growth_global_b,
                    clmm_pool::rewarder::points_growth_global(&pool.rewarder_manager),
                    clmm_pool::rewarder::rewards_growth_global(&pool.rewarder_manager),
                    pool.fullsail_distribution_growth_global
                );
                pool.liquidity = new_liquidity;
                pool.fullsail_distribution_staked_liquidity = new_staked_liquidity;
                continue
            };
            if (pool.current_sqrt_price != next_sqrt_price) {
                pool.current_sqrt_price = next_sqrt_price;
                pool.current_tick_index = clmm_pool::tick_math::get_tick_at_sqrt_price(next_sqrt_price);
                continue
            };
        };
        if (a2b) {
            pool.fee_protocol_coin_a = pool.fee_protocol_coin_a + swap_result.protocol_fee_amount;
            pool.fullsail_distribution_gauger_fee.coin_a = pool.fullsail_distribution_gauger_fee.coin_a + swap_result.gauge_fee_amount;
        } else {
            pool.fee_protocol_coin_b = pool.fee_protocol_coin_b + swap_result.protocol_fee_amount;
            pool.fullsail_distribution_gauger_fee.coin_b = pool.fullsail_distribution_gauger_fee.coin_b + swap_result.gauge_fee_amount;
        };
        swap_result
    }

    /// Returns the amount that needs to be paid for a flash swap operation.
    /// This function extracts the payment amount from the flash swap receipt.
    ///
    /// # Arguments
    /// * `receipt` - Reference to the flash swap receipt containing operation details
    ///
    /// # Returns
    /// The amount of tokens that needs to be paid back as a u64 value
    public fun swap_pay_amount<CoinTypeA, CoinTypeB>(receipt: &FlashSwapReceipt<CoinTypeA, CoinTypeB>): u64 {
        receipt.pay_amount
    }

    /// Synchronizes the fullsail distribution reward parameters for the pool.
    /// Updates the distribution rate, reserve, period finish time, and resets the rollover amount.
    ///
    /// # Arguments
    /// * `pool` - Mutable reference to the pool to update
    /// * `gauge_cap` - Reference to the gauge capability for authorization
    /// * `distribution_rate` - New rate at which rewards will be distributed
    /// * `distribution_reserve` - Amount of tokens reserved for distribution
    /// * `period_finish` - Timestamp when the distribution period ends
    ///
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    /// * If the gauge capability verification fails
    public fun sync_fullsail_distribution_reward<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        gauge_cap: &gauge_cap::gauge_cap::GaugeCap,
        distribution_rate: u128,
        distribution_reserve: u64,
        period_finish: u64
    ) {
        assert!(!pool.is_pause, 13);
        check_gauge_cap<CoinTypeA, CoinTypeB>(pool, gauge_cap);
        pool.fullsail_distribution_rate = distribution_rate;
        pool.fullsail_distribution_reserve = distribution_reserve;
        pool.fullsail_distribution_period_finish = period_finish;
        pool.fullsail_distribution_rollover = 0;
    }

    /// Returns a reference to the pool's tick manager.
    /// The tick manager handles the initialization, tracking, and management
    /// of price ticks within the pool.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool containing the tick manager
    ///
    /// # Returns
    /// Reference to the TickManager instance of the pool
    public fun tick_manager<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): &clmm_pool::tick::TickManager {
        &pool.tick_manager
    }

    /// Returns the tick spacing value for the pool.
    /// Tick spacing determines the minimum distance between initialized ticks
    /// and affects the granularity of price movements.
    ///
    /// # Arguments
    /// * `pool` - Reference to the pool
    ///
    /// # Returns
    /// The tick spacing value as a u32
    public fun tick_spacing<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): u32 {
        pool.tick_spacing
    }

    /// Unpauses the pool, allowing trading and other operations to resume.
    /// Can only be called by an account with pool manager role.
    ///
    /// # Arguments
    /// * `global_config` - Reference to the global configuration for version checking
    /// * `pool` - Mutable reference to the pool to unpause
    /// * `ctx` - Mutable reference to transaction context for sender verification
    ///
    /// # Aborts
    /// * If the pool is not paused (error code: 9223378204427812863)
    /// * If the caller does not have pool manager role
    /// * If the package version check fails
    public fun unpause<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>, 
        ctx: &mut sui::tx_context::TxContext
    ) {
        clmm_pool::config::checked_package_version(global_config);
        clmm_pool::config::check_pool_manager_role(global_config, sui::tx_context::sender(ctx));
        assert!(pool.is_pause, 9223378204427812863);
        pool.is_pause = false;
    }

    /// Removes liquidity from the fullsail distribution system, reducing the amount of liquidity participating in reward distribution.
    /// 
    /// # Arguments
    /// * `pool` - Mutable reference to the pool
    /// * `gauge_cap` - Reference to the gauge capability for access control verification
    /// * `liquidity` - Amount of liquidity to remove
    /// * `tick_lower` - Lower tick boundary for the position
    /// * `tick_upper` - Upper tick boundary for the position
    /// * `clock` - Reference to the Sui clock for timestamp verification
    /// 
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    /// * If the liquidity amount is zero (error code: 9223379200860225535)
    /// * If gauge capability verification fails
    public fun unstake_from_fullsail_distribution<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        gauge_cap: &gauge_cap::gauge_cap::GaugeCap,
        liquidity: u128,
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32,
        clock: &sui::clock::Clock
    ) {
        assert!(!pool.is_pause, 13);
        assert!(liquidity != 0, 9223379200860225535);
        check_gauge_cap<CoinTypeA, CoinTypeB>(pool, gauge_cap);
        update_fullsail_distribution_internal<CoinTypeA, CoinTypeB>(
            pool,
            integer_mate::i128::neg(integer_mate::i128::from(liquidity)),
            tick_lower,
            tick_upper,
            clock
        );
    }
    
    /// Updates the global fee growth for the pool, distributing fees among all liquidity positions.
    /// Fees are distributed proportionally to the amount of liquidity in the pool.
    /// 
    /// # Arguments
    /// * `pool` - Mutable reference to the pool
    /// * `fee_after_protocol` - Amount of fees after protocol fees deduction
    /// * `a2b` - Flag indicating swap direction (true for A->B, false for B->A)
    fun update_fee_growth_global<CoinTypeA, CoinTypeB>(pool: &mut Pool<CoinTypeA, CoinTypeB>, fee_after_protocol: u64, a2b: bool) {
        if (fee_after_protocol == 0 || pool.liquidity == 0) {
            return
        };
        if (a2b) {
            pool.fee_growth_global_a = integer_mate::math_u128::wrapping_add(
                pool.fee_growth_global_a,
                ((fee_after_protocol as u128) << 64) / pool.liquidity
            );
        } else {
            pool.fee_growth_global_b = integer_mate::math_u128::wrapping_add(
                pool.fee_growth_global_b,
                ((fee_after_protocol as u128) << 64) / pool.liquidity
            );
        };
    }

    /// Updates the fee rate for the pool. This function can only be called by an account with pool manager role.
    /// The new fee rate must not exceed the maximum allowed fee rate.
    /// 
    /// # Arguments
    /// * `global_config` - Reference to the global configuration for version checking and role verification
    /// * `pool` - Mutable reference to the pool to update
    /// * `fee_rate` - New fee rate to set for the pool
    /// * `ctx` - Mutable reference to the transaction context for sender verification
    /// 
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    /// * If the new fee rate exceeds the maximum allowed fee rate (error code: 9)
    /// * If the caller does not have pool manager role
    /// * If the package version check fails
    /// 
    /// # Events
    /// Emits an UpdateFeeRateEvent containing:
    /// * The pool ID
    /// * The old fee rate
    /// * The new fee rate
    public fun update_fee_rate<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        fee_rate: u64,
        ctx: &mut sui::tx_context::TxContext
    ) {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        if (fee_rate > clmm_pool::config::max_fee_rate()) {
            abort 9
        };
        clmm_pool::config::check_pool_manager_role(global_config, sui::tx_context::sender(ctx));
        pool.fee_rate = fee_rate;
        let event = UpdateFeeRateEvent {
            pool: sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool),
            old_fee_rate: pool.fee_rate,
            new_fee_rate: fee_rate,
        };
        sui::event::emit<UpdateFeeRateEvent>(event);
    }

    /// Updates the global growth of fullsail distribution rewards for the pool.
    /// This function can only be called by an account with gauge capability.
    /// 
    /// # Arguments
    /// * `pool` - Mutable reference to the pool
    /// * `gauge_cap` - Reference to the gauge capability for access control verification
    /// * `clock` - Reference to the Sui clock for timestamp verification
    /// 
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    /// * If gauge capability verification fails
    public fun update_fullsail_distribution_growth_global<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        gauge_cap: &gauge_cap::gauge_cap::GaugeCap,
        clock: &sui::clock::Clock
    ) {
        assert!(!pool.is_pause, 13);
        check_gauge_cap<CoinTypeA, CoinTypeB>(pool, gauge_cap);
        update_fullsail_distribution_growth_global_internal<CoinTypeA, CoinTypeB>(pool, clock);
    }

    /// Updates the global growth of fullsail distribution rewards based on the time elapsed since last update.
    /// Calculates and distributes rewards to all staked positions.
    /// 
    /// # Arguments
    /// * `pool` - Mutable reference to the pool
    /// * `clock` - Reference to the Sui clock for timestamp verification
    /// 
    /// # Returns
    /// The amount of rewards distributed in this update
    fun update_fullsail_distribution_growth_global_internal<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        clock: &sui::clock::Clock
    ): u64 {
        let current_timestamp = sui::clock::timestamp_ms(clock) / 1000;
        let time_delta = current_timestamp - pool.fullsail_distribution_last_updated;
        let mut distributed_amount = 0;
        if (time_delta != 0) {
            if (pool.fullsail_distribution_reserve > 0) {
                let calculated_distribution = integer_mate::full_math_u128::mul_div_floor(
                    pool.fullsail_distribution_rate,
                    time_delta as u128,
                    18446744073709551616
                ) as u64;
                let mut actual_distribution = calculated_distribution;
                if (calculated_distribution > pool.fullsail_distribution_reserve) {
                    actual_distribution = pool.fullsail_distribution_reserve;
                };
                pool.fullsail_distribution_reserve = pool.fullsail_distribution_reserve - actual_distribution;
                if (pool.fullsail_distribution_staked_liquidity > 0) {
                    pool.fullsail_distribution_growth_global = pool.fullsail_distribution_growth_global + integer_mate::full_math_u128::mul_div_floor(
                        actual_distribution as u128,
                        18446744073709551616,
                        pool.fullsail_distribution_staked_liquidity
                    );
                } else {
                    pool.fullsail_distribution_rollover = pool.fullsail_distribution_rollover + actual_distribution;
                };
                distributed_amount = actual_distribution;
            };
            pool.fullsail_distribution_last_updated = current_timestamp;
        };
        distributed_amount
    }
    
    /// Updates the internal state of fullsail distribution for a position, including staked liquidity and growth tracking.
    /// This function is called when liquidity is added or removed from a position.
    /// 
    /// # Arguments
    /// * `pool` - Mutable reference to the pool
    /// * `liquidity_delta` - Change in liquidity amount (positive for adding, negative for removing)
    /// * `tick_lower` - Lower tick boundary for the position
    /// * `tick_upper` - Upper tick boundary for the position
    /// * `clock` - Reference to the Sui clock for timestamp verification
    /// 
    /// # Aborts
    /// * If attempting to remove more liquidity than is currently staked (error code: 9223379024766566399)
    fun update_fullsail_distribution_internal<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        liquidity_delta: integer_mate::i128::I128,
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32,
        clock: &sui::clock::Clock
    ) {
        if (integer_mate::i32::gte(pool.current_tick_index, tick_lower) && integer_mate::i32::lt(
            pool.current_tick_index,
            tick_upper
        )) {
            update_fullsail_distribution_growth_global_internal<CoinTypeA, CoinTypeB>(pool, clock);
            if (integer_mate::i128::is_neg(liquidity_delta)) {
                assert!(
                    pool.fullsail_distribution_staked_liquidity >= integer_mate::i128::abs_u128(liquidity_delta),
                    9223379024766566399
                );
            } else {
                let (_, overflow) = integer_mate::i128::overflowing_add(
                    integer_mate::i128::from(pool.fullsail_distribution_staked_liquidity),
                    liquidity_delta
                );
                assert!(!overflow, 9223379033357877270);
            };
            pool.fullsail_distribution_staked_liquidity = integer_mate::i128::as_u128(
                integer_mate::i128::add(integer_mate::i128::from(pool.fullsail_distribution_staked_liquidity), liquidity_delta)
            );
        };
        let tick_lower_opt = clmm_pool::tick::try_borrow_tick(&pool.tick_manager, tick_lower);
        let tick_upper_opt = clmm_pool::tick::try_borrow_tick(&pool.tick_manager, tick_upper);
        if (std::option::is_some<clmm_pool::tick::Tick>(&tick_lower_opt)) {
            clmm_pool::tick::update_fullsail_stake(&mut pool.tick_manager, tick_lower, liquidity_delta, false);
        };
        if (std::option::is_some<clmm_pool::tick::Tick>(&tick_upper_opt)) {
            clmm_pool::tick::update_fullsail_stake(&mut pool.tick_manager, tick_upper, liquidity_delta, true);
        };
    }

    /// Updates the URL associated with the pool position.
    /// This function can only be called by an account with pool manager role.
    /// 
    /// # Arguments
    /// * `global_config` - Reference to the global configuration for version checking and role verification
    /// * `pool` - Mutable reference to the pool to update
    /// * `new_url` - New URL string to set for the pool position
    /// * `ctx` - Mutable reference to the transaction context for sender verification
    /// 
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    /// * If the caller does not have pool manager role
    /// * If the package version check fails
    public fun update_position_url<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        new_url: std::string::String,
        ctx: &mut sui::tx_context::TxContext
    ) {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        clmm_pool::config::check_pool_manager_role(global_config, sui::tx_context::sender(ctx));
        pool.url = new_url;
    }

    /// Updates the swap result structure with new amounts and fees from a swap step.
    /// Performs overflow checks before updating the values.
    /// 
    /// # Arguments
    /// * `swap_result` - Mutable reference to the swap result structure to update
    /// * `amount_in_delta` - Change in input amount
    /// * `amount_out_delta` - Change in output amount
    /// * `fee_amount_delta` - Change in fee amount
    /// * `protocol_fee_delta` - Change in protocol fee amount
    /// * `ref_fee_delta` - Change in referral fee amount
    /// * `gauge_fee_delta` - Change in gauge fee amount
    /// 
    /// # Aborts
    /// * If amount_in addition would overflow (error code: 6)
    /// * If amount_out addition would overflow (error code: 7)
    /// * If fee_amount addition would overflow (error code: 8)
    fun update_swap_result(
        swap_result: &mut SwapResult,
        amount_in_delta: u64,
        amount_out_delta: u64,
        fee_amount_delta: u64,
        protocol_fee_delta: u64,
        ref_fee_delta: u64,
        gauge_fee_delta: u64
    ) {
        assert!(integer_mate::math_u64::add_check(swap_result.amount_in, amount_in_delta), 6);
        assert!(integer_mate::math_u64::add_check(swap_result.amount_out, amount_out_delta), 7);
        assert!(integer_mate::math_u64::add_check(swap_result.fee_amount, fee_amount_delta), 8);
        swap_result.amount_in = swap_result.amount_in + amount_in_delta;
        swap_result.amount_out = swap_result.amount_out + amount_out_delta;
        swap_result.fee_amount = swap_result.fee_amount + fee_amount_delta;
        swap_result.protocol_fee_amount = swap_result.protocol_fee_amount + protocol_fee_delta;
        swap_result.gauge_fee_amount = swap_result.gauge_fee_amount + gauge_fee_delta;
        swap_result.ref_fee_amount = swap_result.ref_fee_amount + ref_fee_delta;
        swap_result.steps = swap_result.steps + 1;
    }

    /// Updates the fee rate for unstaked liquidity positions in the pool.
    /// This function can only be called by an account with pool manager role.
    /// 
    /// # Arguments
    /// * `global_config` - Reference to the global configuration for version checking and role verification
    /// * `pool` - Mutable reference to the pool to update
    /// * `new_fee_rate` - New fee rate to set for unstaked liquidity
    /// * `ctx` - Mutable reference to the transaction context for sender verification
    /// 
    /// # Aborts
    /// * If the pool is paused (error code: 13)
    /// * If the new fee rate is invalid (error code: 9)
    /// * If the new fee rate equals the current fee rate (error code: 9)
    /// * If the caller does not have pool manager role
    /// * If the package version check fails
    /// 
    /// # Events
    /// Emits an UpdateUnstakedLiquidityFeeRateEvent containing:
    /// * The pool ID
    /// * The old fee rate
    /// * The new fee rate
    public fun update_unstaked_liquidity_fee_rate<CoinTypeA, CoinTypeB>(
        global_config: &clmm_pool::config::GlobalConfig,
        pool: &mut Pool<CoinTypeA, CoinTypeB>, 
        new_fee_rate: u64,
        ctx: &mut sui::tx_context::TxContext
    ) {
        clmm_pool::config::checked_package_version(global_config);
        assert!(!pool.is_pause, 13);
        assert!(
            new_fee_rate == clmm_pool::config::default_unstaked_fee_rate() || 
            new_fee_rate <= clmm_pool::config::max_unstaked_liquidity_fee_rate(),
            9
        );
        assert!(new_fee_rate != pool.unstaked_liquidity_fee_rate, 9);
        clmm_pool::config::check_pool_manager_role(global_config, sui::tx_context::sender(ctx));
        pool.unstaked_liquidity_fee_rate = new_fee_rate;
        let event = UpdateUnstakedLiquidityFeeRateEvent {
            pool: sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool),
            old_fee_rate: pool.unstaked_liquidity_fee_rate,
            new_fee_rate: new_fee_rate,
        };
        sui::event::emit<UpdateUnstakedLiquidityFeeRateEvent>(event);
    }

    /// Returns the URL associated with the pool position.
    /// 
    /// # Arguments
    /// * `pool` - Reference to the pool
    /// 
    /// # Returns
    /// The URL string associated with the pool position
    public fun url<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>): std::string::String {
        pool.url
    }

    /// Validates that a position belongs to this pool by checking the pool ID.
    /// 
    /// # Arguments
    /// * `pool` - Reference to the pool
    /// * `position` - Reference to the position to validate
    /// 
    /// # Aborts
    /// * If the position's pool ID does not match this pool's ID (error code: 9223373806381301759)
    fun validate_pool_position<CoinTypeA, CoinTypeB>(pool: &Pool<CoinTypeA, CoinTypeB>, position: &clmm_pool::position::Position) {
        assert!(sui::object::id<Pool<CoinTypeA, CoinTypeB>>(pool) == clmm_pool::position::pool_id(position), 9223373806381301759);
    }

    #[test_only]
    public fun test_init(pool: POOL, ctx: &mut sui::tx_context::TxContext) {
        sui::transfer::public_transfer<sui::package::Publisher>(
            sui::package::claim<POOL>(pool, ctx),
            sui::tx_context::sender(ctx)
        );
    }

    #[test_only]
    public fun flash_swap_internal_test<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        global_config: &clmm_pool::config::GlobalConfig,
        partner_id: sui::object::ID,
        ref_fee_rate: u64,
        a2b: bool,
        by_amount_in: bool,
        amount: u64,
        sqrt_price_limit: u128,
        stats: &mut clmm_pool::stats::Stats,
        price_provider: &price_provider::price_provider::PriceProvider,
        clock: &sui::clock::Clock
    ): (sui::balance::Balance<CoinTypeA>, sui::balance::Balance<CoinTypeB>, FlashSwapReceipt<CoinTypeA, CoinTypeB>) {
        flash_swap_internal(pool, global_config, partner_id, ref_fee_rate, a2b, by_amount_in, amount, sqrt_price_limit, stats, price_provider, clock)
    }

    #[test_only]
    public fun swap_in_pool_test<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        a2b: bool,
        by_amount_in: bool,
        sqrt_price_limit: u128,
        amount: u64,
        unstaked_fee_rate: u64,
        protocol_fee_rate: u64,
        ref_fee_rate: u64,
        clock: &sui::clock::Clock
    ): SwapResult {
        swap_in_pool(pool, a2b, by_amount_in, sqrt_price_limit, amount, unstaked_fee_rate, protocol_fee_rate, ref_fee_rate, clock)
    }

    #[test_only]
    public fun update_fullsail_distribution_growth_global_internal_test<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        clock: &sui::clock::Clock
    ): u64 {
        update_fullsail_distribution_growth_global_internal(pool, clock)
    }

    #[test_only]
    public fun update_fullsail_distribution_internal_test<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        liquidity_delta: integer_mate::i128::I128,
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32,
        clock: &sui::clock::Clock
    ) {
        update_fullsail_distribution_internal(pool, liquidity_delta, tick_lower, tick_upper, clock)
    }
    
    #[test_only]
    public fun update_swap_result_test(
        swap_result: &mut SwapResult,
        amount_in_delta: u64,
        amount_out_delta: u64,
        fee_amount_delta: u64,
        protocol_fee_delta: u64,
        ref_fee_delta: u64,
        gauge_fee_delta: u64
    ) {
        update_swap_result(swap_result, amount_in_delta, amount_out_delta, fee_amount_delta, protocol_fee_delta, ref_fee_delta, gauge_fee_delta)
    }

    #[test_only]
    public fun add_liquidity_internal_test<CoinTypeA, CoinTypeB>(
        pool: &mut Pool<CoinTypeA, CoinTypeB>,
        position: &mut clmm_pool::position::Position,
        is_fix_amount: bool,
        liquidity_delta: u128,
        amount_in: u64,
        is_fix_amount_a: bool,
        timestamp: u64
    ): AddLiquidityReceipt<CoinTypeA, CoinTypeB> {
        add_liquidity_internal(pool, position, is_fix_amount, liquidity_delta, amount_in, is_fix_amount_a, timestamp)
    }

    #[test_only]
    public fun destroy_flash_swap_receipt<CoinTypeA, CoinTypeB>(receipt: FlashSwapReceipt<CoinTypeA, CoinTypeB>) {
        let FlashSwapReceipt { pool_id, a2b, partner_id, pay_amount, fee_amount, protocol_fee_amount, ref_fee_amount, gauge_fee_amount } = receipt;
    }

    #[test_only]
    public fun destroy_receipt<CoinTypeA, CoinTypeB>(receipt: AddLiquidityReceipt<CoinTypeA, CoinTypeB>) {
        let AddLiquidityReceipt { pool_id, amount_a, amount_b } = receipt;
    }

    #[test_only]
    public fun create_swap_result_test(
        amount_in: u64,
        amount_out: u64,
        fee_amount: u64,
        protocol_fee_amount: u64,
        ref_fee_amount: u64,
        gauge_fee_amount: u64,
        steps: u64
    ): SwapResult {
        SwapResult {
            amount_in: amount_in,
            amount_out: amount_out,
            fee_amount: fee_amount,
            protocol_fee_amount: protocol_fee_amount,
            ref_fee_amount: ref_fee_amount,
            gauge_fee_amount: gauge_fee_amount,
            steps: steps,
        }
    }

    #[test_only]
    public fun get_swap_result_test(
        swap_result: &SwapResult
    ): (u64, u64, u64, u64, u64, u64, u64) {
        (
            swap_result.amount_in,
            swap_result.amount_out,
            swap_result.fee_amount,
            swap_result.protocol_fee_amount,
            swap_result.ref_fee_amount,
            swap_result.gauge_fee_amount,
            swap_result.steps
        )
    }
}

