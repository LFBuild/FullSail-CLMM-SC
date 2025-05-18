/// Factory module for the CLMM (Concentrated Liquidity Market Maker) pool system.
/// This module provides functionality for:
/// * Creating and managing liquidity pools
/// * Managing pool parameters and settings
/// * Handling pool initialization and configuration
/// * Managing pool ownership and permissions
/// 
/// The module implements:
/// * Pool creation and initialization
/// * Pool parameter management
/// * Pool ownership control
/// * Pool configuration updates
/// 
/// # Key Concepts
/// * Pool Creation - Process of initializing a new liquidity pool with specific parameters
/// * Pool Parameters - Settings that define pool behavior (fee rates, tick spacing, etc.)
/// * Pool Ownership - Control over pool management and configuration
/// * Pool Configuration - Settings that affect pool operation and behavior
/// 
/// # Events
/// * Pool creation events
/// * Pool parameter update events
/// * Pool ownership transfer events
/// * Pool configuration change events
module clmm_pool::factory {

    /// Error codes for the factory module
    const EPoolAlreadyExists: u64 = 924369306373425236;
    const EInvalidSqrtPrice: u64 = 923692497321135234;
    const ESameCoinTypes: u64 = 923969347438330212;
    const EExceededMaxAmountB: u64 = 995379293462347203;
    const EExceededMaxAmountA: u64 = 921263237432321235;
    const EInvalidCoinOrder: u64 = 923702346234613273;
    const EInvalidBytesLength: u64 = 913468309285702395;

    /// Represents the factory state for pool management.
    /// This structure is used to maintain factory-level state and settings.
    /// 
    /// # Fields
    /// * `dummy_field` - Placeholder field for future use
    public struct FACTORY has drop {
        dummy_field: bool,
    }

    /// Contains basic information about a liquidity pool.
    /// Used for quick lookup and identification of pools.
    /// 
    /// # Fields
    /// * `pool_id` - Unique identifier of the pool
    /// * `pool_key` - Key used for pool lookup and identification
    /// * `coin_type_a` - Type of the first token in the pool
    /// * `coin_type_b` - Type of the second token in the pool
    /// * `tick_spacing` - Minimum distance between initialized ticks
    public struct PoolSimpleInfo has copy, drop, store {
        pool_id: sui::object::ID,
        pool_key: sui::object::ID,
        coin_type_a: std::type_name::TypeName,
        coin_type_b: std::type_name::TypeName,
        tick_spacing: u32,
    }

    /// Main storage structure for all pools in the factory.
    /// Maintains a linked list of pool information and a counter for pool indexing.
    /// 
    /// # Fields
    /// * `id` - Unique identifier for the pools collection
    /// * `list` - Linked table containing pool information indexed by pool keys
    /// * `index` - Counter for generating unique pool indices
    public struct Pools has store, key {
        id: sui::object::UID,
        list: move_stl::linked_table::LinkedTable<sui::object::ID, PoolSimpleInfo>,
        index: u64,
    }

    /// Event emitted when the factory is initialized.
    /// Contains the ID of the created pools collection.
    /// 
    /// # Fields
    /// * `pools_id` - ID of the created pools collection
    public struct InitFactoryEvent has copy, drop {
        pools_id: sui::object::ID,
    }

    /// Event emitted when a new pool is created.
    /// Contains information about the created pool.
    /// 
    /// # Fields
    /// * `pool_id` - ID of the created pool
    /// * `coin_type_a` - String representation of the first token type
    /// * `coin_type_b` - String representation of the second token type
    /// * `tick_spacing` - Minimum distance between initialized ticks
    public struct CreatePoolEvent has copy, drop {
        pool_id: sui::object::ID,
        coin_type_a: std::string::String,
        coin_type_b: std::string::String,
        tick_spacing: u32,
    }

    /// Returns the coin types used in a pool.
    /// 
    /// # Arguments
    /// * `pool_info` - Reference to the pool information structure
    /// 
    /// # Returns
    /// Tuple containing the types of both coins in the pool
    public fun coin_types(pool_info: &PoolSimpleInfo): (std::type_name::TypeName, std::type_name::TypeName) {
        (pool_info.coin_type_a, pool_info.coin_type_b)
    }
    
    /// Creates a new liquidity pool with specified parameters and makes it publicly accessible.
    /// 
    /// # Arguments
    /// * `pools` - Mutable reference to the pools collection
    /// * `global_config` - Reference to the global configuration
    /// * `tick_spacing` - Minimum distance between initialized ticks
    /// * `current_sqrt_price` - Initial square root price for the pool
    /// * `url` - URL for pool metadata
    /// * `feed_id_coin_a` - Price feed ID for the first token
    /// * `feed_id_coin_b` - Price feed ID for the second token
    /// * `auto_calculation_volumes` - Whether to automatically calculate volumes
    /// * `clock` - Reference to the Sui clock
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Abort Conditions
    /// * If the package version check fails
    /// * If the current square root price is out of valid range
    /// * If both coin types are the same
    /// * If a pool with the same key already exists
    public fun create_pool<CoinTypeA, CoinTypeB>(
        pools: &mut Pools,
        global_config: &clmm_pool::config::GlobalConfig,
        tick_spacing: u32,
        current_sqrt_price: u128,
        url: std::string::String,
        feed_id_coin_a: address,
        feed_id_coin_b: address,
        auto_calculation_volumes: bool,
        clock: &sui::clock::Clock,
        ctx: &mut sui::tx_context::TxContext
    ) {
        clmm_pool::config::checked_package_version(global_config);
        let pool = create_pool_internal<CoinTypeA, CoinTypeB>(
            pools,
            global_config,
            tick_spacing,
            current_sqrt_price,
            url,
            feed_id_coin_a,
            feed_id_coin_b,
            auto_calculation_volumes,
            clock,
            ctx
        );
        sui::transfer::public_share_object<clmm_pool::pool::Pool<CoinTypeA, CoinTypeB>>(pool);
    }

    /// Creates a new liquidity pool with specified parameters and returns it without making it public.
    /// This is an internal version of pool creation that returns the pool object directly.
    /// 
    /// # Arguments
    /// * `pools` - Mutable reference to the pools collection
    /// * `global_config` - Reference to the global configuration
    /// * `tick_spacing` - Minimum distance between initialized ticks
    /// * `current_sqrt_price` - Initial square root price for the pool
    /// * `url` - URL for pool metadata
    /// * `feed_id_coin_a` - Price feed ID for the first token
    /// * `feed_id_coin_b` - Price feed ID for the second token
    /// * `auto_calculation_volumes` - Whether to automatically calculate volumes
    /// * `clock` - Reference to the Sui clock
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Returns
    /// The newly created pool object
    /// 
    /// # Abort Conditions
    /// * If the package version check fails
    /// * If the current square root price is out of valid range
    /// * If both coin types are the same
    /// * If a pool with the same key already exists
    public fun create_pool_<CoinTypeA, CoinTypeB>(
        pools: &mut Pools,
        global_config: &clmm_pool::config::GlobalConfig,
        tick_spacing: u32,
        current_sqrt_price: u128,
        url: std::string::String,
        feed_id_coin_a: address,
        feed_id_coin_b: address,
        auto_calculation_volumes: bool,
        clock: &sui::clock::Clock,
        ctx: &mut sui::tx_context::TxContext
    ): clmm_pool::pool::Pool<CoinTypeA, CoinTypeB> {
        clmm_pool::config::checked_package_version(global_config);
        create_pool_internal<CoinTypeA, CoinTypeB>(
            pools,
            global_config,
            tick_spacing,
            current_sqrt_price,
            url,
            feed_id_coin_a,
            feed_id_coin_b,
            auto_calculation_volumes,
            clock,
            ctx
        )
    }

    /// Internal function for creating a new liquidity pool.
    /// Handles the core pool creation logic including validation, initialization, and event emission.
    /// 
    /// # Arguments
    /// * `pools` - Mutable reference to the pools collection
    /// * `global_config` - Reference to the global configuration
    /// * `tick_spacing` - Minimum distance between initialized ticks
    /// * `current_sqrt_price` - Initial square root price for the pool
    /// * `url` - URL for pool metadata
    /// * `feed_id_coin_a` - Price feed ID for the first token
    /// * `feed_id_coin_b` - Price feed ID for the second token
    /// * `auto_calculation_volumes` - Whether to automatically calculate volumes
    /// * `clock` - Reference to the Sui clock
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Returns
    /// The newly created pool object
    /// 
    /// # Abort Conditions
    /// * If the current square root price is out of valid range (error code: EInvalidSqrtPrice)
    /// * If both coin types are the same (error code: ESameCoinTypes)
    /// * If a pool with the same key already exists (error code: EPoolAlreadyExists)
    /// 
    /// # Events
    /// * Emits a CreatePoolEvent with pool details
    fun create_pool_internal<CoinTypeA, CoinTypeB>(
        pools: &mut Pools,
        global_config: &clmm_pool::config::GlobalConfig,
        tick_spacing: u32,
        current_sqrt_price: u128,
        url: std::string::String,
        feed_id_coin_a: address,
        feed_id_coin_b: address,
        auto_calculation_volumes: bool,
        clock: &sui::clock::Clock,
        ctx: &mut sui::tx_context::TxContext
    ): clmm_pool::pool::Pool<CoinTypeA, CoinTypeB> {
        assert!(current_sqrt_price >= clmm_pool::tick_math::min_sqrt_price() && current_sqrt_price <= clmm_pool::tick_math::max_sqrt_price(), EInvalidSqrtPrice);
        let coin_type_a = std::type_name::get<CoinTypeA>();
        let coin_type_b = std::type_name::get<CoinTypeB>();
        assert!(coin_type_a != coin_type_b, ESameCoinTypes);
        let pool_key = new_pool_key<CoinTypeA, CoinTypeB>(tick_spacing);
        if (move_stl::linked_table::contains<sui::object::ID, PoolSimpleInfo>(&pools.list, pool_key)) {
            abort EPoolAlreadyExists
        };
        let pool_url = if (std::string::length(&url) == 0) {
            std::string::utf8(b"")
        } else {
            url
        };
        let pool = clmm_pool::pool::new<CoinTypeA, CoinTypeB>(
            tick_spacing,
            current_sqrt_price,
            clmm_pool::config::get_fee_rate(tick_spacing, global_config),
            pool_url,
            pools.index,
            feed_id_coin_a,
            feed_id_coin_b,
            auto_calculation_volumes,
            clock,
            ctx
        );
        pools.index = pools.index + 1;
        let pool_id = sui::object::id<clmm_pool::pool::Pool<CoinTypeA, CoinTypeB>>(&pool);
        let pool_info = PoolSimpleInfo {
            pool_id,
            pool_key,
            coin_type_a,
            coin_type_b,
            tick_spacing,
        };
        move_stl::linked_table::push_back<sui::object::ID, PoolSimpleInfo>(&mut pools.list, pool_key, pool_info);
        let event = CreatePoolEvent {
            pool_id,
            coin_type_a: std::string::from_ascii(std::type_name::into_string(coin_type_a)),
            coin_type_b: std::string::from_ascii(std::type_name::into_string(coin_type_b)), 
            tick_spacing,
        };
        sui::event::emit<CreatePoolEvent>(event);
        pool
    }

    /// Creates a new liquidity pool and initializes it with initial liquidity.
    /// This function combines pool creation, position opening, and initial liquidity addition in one transaction.
    /// 
    /// # Arguments
    /// * `pools` - Mutable reference to the pools collection
    /// * `global_config` - Reference to the global configuration
    /// * `tick_spacing` - Minimum distance between initialized ticks
    /// * `initialize_sqrt_price` - Initial square root price for the pool
    /// * `url` - URL for pool metadata
    /// * `tick_lower` - Lower tick boundary for the position
    /// * `tick_upper` - Upper tick boundary for the position
    /// * `coin_a_input` - Input coin of type A for initial liquidity
    /// * `coin_b_input` - Input coin of type B for initial liquidity
    /// * `liquidity_amount_a` - Maximum amount of token A to add
    /// * `liquidity_amount_b` - Maximum amount of token B to add
    /// * `fix_amount_a` - Whether to fix the amount of token A (true) or B (false)
    /// * `feed_id_coin_a` - Price feed ID for the first token
    /// * `feed_id_coin_b` - Price feed ID for the second token
    /// * `auto_calculation_volumes` - Whether to automatically calculate volumes
    /// * `clock` - Reference to the Sui clock
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Returns
    /// Tuple containing:
    /// * The created position
    /// * Remaining coin A after liquidity addition
    /// * Remaining coin B after liquidity addition
    /// 
    /// # Abort Conditions
    /// * If the package version check fails
    /// * If the current square root price is out of valid range
    /// * If both coin types are the same
    /// * If a pool with the same key already exists
    /// * If the amount of token B exceeds the maximum specified (error code: EExceededMaxAmountB)
    /// * If the amount of token A exceeds the maximum specified (error code: EExceededMaxAmountA)
    public fun create_pool_with_liquidity<CoinTypeA, CoinTypeB>(
        pools: &mut Pools,
        global_config: &clmm_pool::config::GlobalConfig,
        vault: &mut clmm_pool::rewarder::RewarderGlobalVault,
        tick_spacing: u32,
        initialize_sqrt_price: u128,
        url: std::string::String,
        tick_lower: u32,
        tick_upper: u32,
        mut coin_a_input: sui::coin::Coin<CoinTypeA>,
        mut coin_b_input: sui::coin::Coin<CoinTypeB>,
        liquidity_amount_a: u64,
        liquidity_amount_b: u64,
        fix_amount_a: bool,
        feed_id_coin_a: address,
        feed_id_coin_b: address,
        auto_calculation_volumes: bool,
        clock: &sui::clock::Clock,
        ctx: &mut sui::tx_context::TxContext
    ): (clmm_pool::position::Position, sui::coin::Coin<CoinTypeA>, sui::coin::Coin<CoinTypeB>) {
        clmm_pool::config::checked_package_version(global_config);
        let mut pool = create_pool_internal<CoinTypeA, CoinTypeB>(
            pools,
            global_config,
            tick_spacing,
            initialize_sqrt_price,
            url,
            feed_id_coin_a,
            feed_id_coin_b,
            auto_calculation_volumes,
            clock,
            ctx
        );
        let mut position = clmm_pool::pool::open_position<CoinTypeA, CoinTypeB>(
            global_config,
            &mut pool,
            tick_lower,
            tick_upper,
            ctx
        );
        let fix_amount = if (fix_amount_a) {
            liquidity_amount_a
        } else {
            liquidity_amount_b
        };
        let receipt = clmm_pool::pool::add_liquidity_fix_coin<CoinTypeA, CoinTypeB>(
            global_config,
            vault,
            &mut pool,
            &mut position,
            fix_amount,
            fix_amount_a,
            clock
        );
        let (amount_a, amount_b) = clmm_pool::pool::add_liquidity_pay_amount<CoinTypeA, CoinTypeB>(&receipt);
        if (fix_amount_a) {
            assert!(amount_b <= liquidity_amount_b, EExceededMaxAmountB);
        } else {
            assert!(amount_a <= liquidity_amount_a, EExceededMaxAmountA);
        };
        clmm_pool::pool::repay_add_liquidity<CoinTypeA, CoinTypeB>(
            global_config,
            &mut pool,
            sui::coin::into_balance<CoinTypeA>(sui::coin::split<CoinTypeA>(&mut coin_a_input, amount_a, ctx)),
            sui::coin::into_balance<CoinTypeB>(sui::coin::split<CoinTypeB>(&mut coin_b_input, amount_b, ctx)),
            receipt
        );
        sui::transfer::public_share_object<clmm_pool::pool::Pool<CoinTypeA, CoinTypeB>>(pool);
        (position, coin_a_input, coin_b_input)
    }
    
    /// Fetches pool information from the pools table.
    /// 
    /// If `pre_start_pool_id` is None, the method starts from the head of the linked table and returns
    /// information about pools in the order they are stored in the table, up to the specified limit.
    /// 
    /// If `pre_start_pool_id` is Some, the method starts from the next pool after the specified ID and returns
    /// information about pools starting from that point, up to the specified limit.
    /// 
    /// # Parameters
    /// * `pools` - Reference to the Pools object containing the linked table of pools
    /// * `pre_start_pool_id` - Optional pool ID to start fetching after. If None, starts from the beginning of the table.
    /// * `limit` - Maximum number of pools to return
    /// 
    /// # Returns
    /// Vector of PoolSimpleInfo containing information about the requested pools
    public fun fetch_pools(
        pools: &Pools,
        pre_start_pool_id: Option<sui::object::ID>,
        limit: u64
    ): vector<PoolSimpleInfo> {
        let mut result = std::vector::empty<PoolSimpleInfo>();
        let next_id = if (std::option::is_none<sui::object::ID>(&pre_start_pool_id)) {
            move_stl::linked_table::head<sui::object::ID, PoolSimpleInfo>(&pools.list)
        } else {
            move_stl::linked_table::next<sui::object::ID, PoolSimpleInfo>(
                move_stl::linked_table::borrow_node<sui::object::ID, PoolSimpleInfo>(
                    &pools.list,
                    *std::option::borrow<sui::object::ID>(&pre_start_pool_id)
                )
            )
        };
        let mut current_id = next_id;
        let mut count = 0;
        while (std::option::is_some<sui::object::ID>(&current_id) && count < limit) {
            let node = move_stl::linked_table::borrow_node<sui::object::ID, PoolSimpleInfo>(
                &pools.list,
                *std::option::borrow<sui::object::ID>(&current_id)
            );
            current_id = move_stl::linked_table::next<sui::object::ID, PoolSimpleInfo>(node);
            std::vector::push_back<PoolSimpleInfo>(
                &mut result,
                *move_stl::linked_table::borrow_value<sui::object::ID, PoolSimpleInfo>(node)
            );
            count = count + 1;
        };
        result
    }

    /// Returns the current index of the pools collection.
    /// This index is used for generating unique pool IDs.
    /// 
    /// # Arguments
    /// * `pools` - Reference to the pools collection
    /// 
    /// # Returns
    /// The current index value as u64
    public fun index(pools: &Pools): u64 {
        pools.index
    }
    
    /// Initializes the factory and creates the initial pools collection.
    /// This function is called once during factory deployment.
    /// 
    /// # Arguments
    /// * `factory` - The factory instance to initialize
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Events
    /// * Emits InitFactoryEvent with the ID of the created pools collection
    /// 
    /// # Details
    /// * Creates a new Pools structure with empty list and zero index
    /// * Shares the pools collection object
    /// * Claims and keeps the factory object
    fun init(factory: FACTORY, ctx: &mut sui::tx_context::TxContext) {
        let pools = Pools {
            id: sui::object::new(ctx),
            list: move_stl::linked_table::new<sui::object::ID, PoolSimpleInfo>(ctx),
            index: 0,
        };
        let pools_id = sui::object::id<Pools>(&pools);
        sui::transfer::share_object<Pools>(pools);
        let event = InitFactoryEvent { pools_id };
        sui::event::emit<InitFactoryEvent>(event);
        sui::package::claim_and_keep<FACTORY>(factory, ctx);
    }
    
    /// Generates a unique key for a pool based on coin types and tick spacing.
    /// The key is deterministic and ensures consistent ordering of coin types.
    /// 
    /// # Arguments
    /// * `tick_spacing` - Minimum distance between initialized ticks
    /// 
    /// # Returns
    /// A unique ID for the pool
    /// 
    /// # Abort Conditions
    /// * If the coin types are in lexicographical order (error code: EInvalidCoinOrder)
    public fun new_pool_key<CoinTypeA, CoinTypeB>(tick_spacing: u32): sui::object::ID {
        let type_name_a = std::type_name::into_string(std::type_name::get<CoinTypeA>());
        let mut bytes_a = *std::ascii::as_bytes(&type_name_a);
        let bytes_a_len = std::vector::length<u8>(&bytes_a);
        let type_name_b = std::type_name::into_string(std::type_name::get<CoinTypeB>());
        let bytes_b = std::ascii::as_bytes(&type_name_b);
        let mut index = 0;
        let mut swapped = false;
        while (index < std::vector::length<u8>(bytes_b)) {
            let byte_b = *std::vector::borrow<u8>(bytes_b, index);
            let should_compare = !swapped && index < bytes_a_len;
            if (should_compare) {
                let byte_a = *std::vector::borrow<u8>(&bytes_a, index);
                if (byte_a < byte_b) {
                    abort EInvalidCoinOrder
                };
                if (byte_a > byte_b) {
                    swapped = true;
                };
            };
            std::vector::push_back<u8>(&mut bytes_a, byte_b);
            index = index + 1;
            continue;
        };
        if (!swapped) {
            if (bytes_a_len < std::vector::length<u8>(bytes_b)) {
                abort EInvalidBytesLength
            };
        };

        let mut bytes_id = *std::ascii::as_bytes(&type_name_a);
        std::vector::append<u8>(&mut bytes_id, sui::bcs::to_bytes<u32>(&tick_spacing));
        sui::object::id_from_bytes(sui::hash::blake2b256(&bytes_id))
    }

    /// Returns the ID of a pool from its simple info.
    /// 
    /// # Arguments
    /// * `pool_info` - Reference to the pool information structure
    /// 
    /// # Returns
    /// The pool's unique identifier
    public fun pool_id(pool_info: &PoolSimpleInfo): sui::object::ID {
        pool_info.pool_id
    }

    /// Returns the key of a pool from its simple info.
    /// 
    /// # Arguments
    /// * `pool_info` - Reference to the pool information structure
    /// 
    /// # Returns
    /// The pool's lookup key
    public fun pool_key(pool_info: &PoolSimpleInfo): sui::object::ID {
        pool_info.pool_key
    }

    /// Retrieves the simple info for a pool by its key.
    /// 
    /// # Arguments
    /// * `pools` - Reference to the pools collection
    /// * `pool_key` - The key of the pool to look up
    /// 
    /// # Returns
    /// Reference to the pool's simple info structure
    public fun pool_simple_info(pools: &Pools, pool_key: sui::object::ID): &PoolSimpleInfo {
        move_stl::linked_table::borrow<sui::object::ID, PoolSimpleInfo>(&pools.list, pool_key)
    }

    /// Returns the tick spacing of a pool from its simple info.
    /// 
    /// # Arguments
    /// * `pool_info` - Reference to the pool information structure
    /// 
    /// # Returns
    /// The minimum distance between initialized ticks
    public fun tick_spacing(pool_info: &PoolSimpleInfo): u32 {
        pool_info.tick_spacing
    }

    #[test_only]
    /// Test initialization of the position system
    /// Replicates the init function logic for testing purposes
    public fun test_init(ctx: &mut sui::tx_context::TxContext) {
        let pools = Pools {
            id: sui::object::new(ctx),
            list: move_stl::linked_table::new<sui::object::ID, PoolSimpleInfo>(ctx),
            index: 0,
        };

        sui::transfer::share_object<Pools>(pools);
        sui::package::claim_and_keep<FACTORY>(FACTORY { dummy_field: false }, ctx);
    }

    #[test_only]
    fun test_init_fun() {
        let admin = @0x123;
        let mut scenario = sui::test_scenario::begin(admin);
        {
            init(FACTORY { dummy_field: false }, scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            let pools = scenario.take_from_sender<Pools>();
            let publisher = scenario.take_from_sender<sui::package::Publisher>();
            
            assert!(sui::object::id(&pools) != sui::object::id(&publisher), EPoolAlreadyExists);
            assert!(move_stl::linked_table::is_empty(&pools.list), EInvalidSqrtPrice);
            assert!(pools.index == 0, ESameCoinTypes);
            
            scenario.return_to_sender(pools);
            scenario.return_to_sender(publisher);
        };

        scenario.end();
    }

    #[test_only]
    public(package) fun create_pool_internal_test<CoinTypeA, CoinTypeB>(
        pools: &mut Pools,
        global_config: &clmm_pool::config::GlobalConfig,
        tick_spacing: u32,
        current_sqrt_price: u128,
        url: std::string::String,
        feed_id_coin_a: address,
        feed_id_coin_b: address,
        auto_calculation_volumes: bool,
        clock: &sui::clock::Clock,
        ctx: &mut sui::tx_context::TxContext
    ): clmm_pool::pool::Pool<CoinTypeA, CoinTypeB> {
        create_pool_internal<CoinTypeA, CoinTypeB>(pools, global_config, tick_spacing, current_sqrt_price, url, feed_id_coin_a, feed_id_coin_b, auto_calculation_volumes, clock, ctx)
    }
}

