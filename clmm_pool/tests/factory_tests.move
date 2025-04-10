#[test_only]
module clmm_pool::factory_tests {
    use sui::test_scenario;
    use sui::object;
    use clmm_pool::config;
    use sui::package;
    use sui::clock;
    use sui::tx_context;
    use sui::transfer;
    use sui::event;
    use move_stl::linked_table;
    use std::type_name;
    use std::ascii;
    use std::string;
    use sui::hash;
    use sui::bcs;

    use clmm_pool::factory::{Self as factory, FACTORY, Pools, PoolSimpleInfo};

    public struct TestCoinA has drop {}
    public struct TestCoinB has drop {}

    #[test]
    fun test_new_pool_key_same_coin_types() {
        let mut scenario = test_scenario::begin(@0x1);
        let ctx = test_scenario::ctx(&mut scenario);
        
        // Should generate same key for same coin types
        let key1 = factory::new_pool_key<TestCoinA, TestCoinA>(1);
        let key2 = factory::new_pool_key<TestCoinA, TestCoinA>(1);
        
        // Keys should be the same
        assert!(key1 == key2, 1);
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_new_pool_key_different_coin_types() {
        let mut scenario = test_scenario::begin(@0x1);
        let ctx = test_scenario::ctx(&mut scenario);
        
        // Should succeed with different coin types in correct order
        let key1 = factory::new_pool_key<TestCoinB, TestCoinA>(1);
        let key2 = factory::new_pool_key<TestCoinB, TestCoinA>(1);
        
        // Keys should be the same for same coin type order
        assert!(key1 == key2, 1);
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_new_pool_key_different_tick_spacing() {
        let mut scenario = test_scenario::begin(@0x1);
        let ctx = test_scenario::ctx(&mut scenario);
        
        // Should generate different keys for different tick spacing
        let key1 = factory::new_pool_key<TestCoinB, TestCoinA>(1);
        let key2 = factory::new_pool_key<TestCoinB, TestCoinA>(2);
        
        assert!(key1 != key2, 1);
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 6)]
    fun test_new_pool_key_wrong_order() {
        let mut scenario = test_scenario::begin(@0x1);
        let ctx = test_scenario::ctx(&mut scenario);
        
        factory::new_pool_key<TestCoinA, TestCoinB>(1);
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_create_pool() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create a new pool with TestCoinB and TestCoinA
            let pool = factory::create_pool_<TestCoinB, TestCoinA>(
                &mut pools,
                &global_config,
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                std::string::utf8(b""), // url
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            // Verify pool was created and shared
            assert!(sui::object::id(&pool) != sui::object::id(&pools), 1);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_create_pool_internal_success() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create a new pool with TestCoinB and TestCoinA
            let pool = factory::create_pool_internal_test<TestCoinB, TestCoinA>(
                &mut pools,
                &global_config,
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                std::string::utf8(b""), // url
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            // Verify pool was created
            assert!(sui::object::id(&pool) != sui::object::id(&pools), 1);

            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(admin);
        {
            let pools = scenario.take_shared<Pools>();
            let pool_key = factory::new_pool_key<TestCoinB, TestCoinA>(1);
            let pool_info = pools.pool_simple_info(pool_key);
            let (coin_type_a, coin_type_b) = pool_info.coin_types();
            assert!(coin_type_a == type_name::get<TestCoinB>(), 1);
            assert!(coin_type_b == type_name::get<TestCoinA>(), 1);

            assert!(pool_info.pool_key() == pool_key, 1);

            assert!(pool_info.tick_spacing() == 1, 1);

            test_scenario::return_shared(pools);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2)]
    fun test_create_pool_internal_invalid_sqrt_price() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Try to create pool with invalid sqrt price
            let pool = factory::create_pool_internal_test<TestCoinB, TestCoinA>(
                &mut pools,
                &global_config,
                1, // tick_spacing
                0, // invalid current_sqrt_price
                std::string::utf8(b""), // url
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 3)]
    fun test_create_pool_internal_same_coin_types() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Try to create pool with same coin types
            let pool = factory::create_pool_internal_test<TestCoinA, TestCoinA>(
                &mut pools,
                &global_config,
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                std::string::utf8(b""), // url
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)]
    fun test_create_pool_internal_duplicate_pool() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create first pool
            let pool = factory::create_pool_internal_test<TestCoinB, TestCoinA>(
                &mut pools,
                &global_config,
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                std::string::utf8(b""), // url
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            // Try to create duplicate pool
            let pool2 = factory::create_pool_internal_test<TestCoinB, TestCoinA>(
                &mut pools,
                &global_config,
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                std::string::utf8(b""), // url
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            transfer::public_transfer(pool, admin);
            transfer::public_transfer(pool2, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_create_pool_public() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create a new pool with TestCoinB and TestCoinA
            factory::create_pool<TestCoinB, TestCoinA>(
                &mut pools,
                &global_config,
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                std::string::utf8(b""), // url
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            // Verify pool was created and shared
            let pool_key = factory::new_pool_key<TestCoinB, TestCoinA>(1);
            let pool_info = pools.pool_simple_info(pool_key);
            assert!(pool_info.tick_spacing() == 1, 1);
            
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_create_pool_private() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create a new pool with TestCoinB and TestCoinA
            let pool = factory::create_pool_<TestCoinB, TestCoinA>(
                &mut pools,
                &global_config,
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                std::string::utf8(b""), // url
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            // Verify pool was created but not shared
            let pool_key = factory::new_pool_key<TestCoinB, TestCoinA>(1);
            let pool_info = pools.pool_simple_info(pool_key);
            assert!(pool_info.tick_spacing() == 1, 1);
            assert!(sui::object::id(&pool) == pool_info.pool_id(), 2);
            
            // Make pool public
            sui::transfer::public_share_object(pool);
            
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2)]
    fun test_create_pool_invalid_sqrt_price() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Try to create pool with invalid sqrt price
            factory::create_pool<TestCoinB, TestCoinA>(
                &mut pools,
                &global_config,
                1, // tick_spacing
                0, // invalid current_sqrt_price
                std::string::utf8(b""), // url
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 3)]
    fun test_create_pool_same_coin_types() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Try to create pool with same coin types
            factory::create_pool<TestCoinA, TestCoinA>(
                &mut pools,
                &global_config,
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                std::string::utf8(b""), // url
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)]
    fun test_create_pool_duplicate() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create first pool
            factory::create_pool<TestCoinB, TestCoinA>(
                &mut pools,
                &global_config,
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                std::string::utf8(b""), // url
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            // Try to create duplicate pool
            factory::create_pool<TestCoinB, TestCoinA>(
                &mut pools,
                &global_config,
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                std::string::utf8(b""), // url
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_create_pool_with_liquidity_success() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create test coins
            let coin_a = sui::coin::mint_for_testing<TestCoinB>(1000000, scenario.ctx());
            let coin_b = sui::coin::mint_for_testing<TestCoinA>(1000000, scenario.ctx());
            
            // Create pool with initial liquidity
            let (position, remaining_coin_a, remaining_coin_b) = factory::create_pool_with_liquidity<TestCoinB, TestCoinA>(
                &mut pools,
                &global_config,
                1, // tick_spacing
                79228162514264337593543950336 >> 33, // current_sqrt_price (0.5)
                std::string::utf8(b""), // url
                0, // tick_lower
                100, // tick_upper
                coin_a, // coin_a_input
                coin_b, // coin_b_input
                100000, // liquidity_amount_a
                100000, // liquidity_amount_b
                true, // fix_amount_a (true means we fix the amount of coin A)
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            // Verify position was created
            assert!(sui::object::id(&position) != sui::object::id(&pools), 1);
            
            // Verify remaining coins
            let remaining_a_value = sui::coin::value(&remaining_coin_a);
            let remaining_b_value = sui::coin::value(&remaining_coin_b);
            
            // Calculate expected remaining values
            let expected_remaining_a = 1000000 - 100000; // Initial amount - used amount (only coin A is used)
            let expected_remaining_b = 1000000; // Initial amount (coin B is not used when fix_amount_a is true)
            
            assert!(remaining_a_value == expected_remaining_a, 2);
            assert!(remaining_b_value == expected_remaining_b, 3);
            assert!(remaining_a_value > 0, 4);
            assert!(remaining_b_value > 0, 5);
            
            // Return objects to scenario
            transfer::public_transfer(position, admin);
            transfer::public_transfer(remaining_coin_a, admin);
            transfer::public_transfer(remaining_coin_b, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 3020)]
    fun test_create_pool_with_liquidity_exceed_amount_b() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create test coins with insufficient amount of coin B
            let coin_b = sui::coin::mint_for_testing<TestCoinA>(1, scenario.ctx()); // Minimal amount
            let coin_a = sui::coin::mint_for_testing<TestCoinB>(1000000, scenario.ctx());
            
            // Try to create pool with liquidity that exceeds available coin B
            let (position, remaining_coin_a, remaining_coin_b) = factory::create_pool_with_liquidity<TestCoinB, TestCoinA>(
                &mut pools,
                &global_config,
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                std::string::utf8(b""), // url
                0, // tick_lower
                100, // tick_upper
                coin_a, // coin_a_input
                coin_b, // coin_b_input
                100000, // liquidity_amount_a
                100000, // liquidity_amount_b
                false, // fix_amount_b
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            // Return objects to scenario
            transfer::public_transfer(position, admin);
            transfer::public_transfer(remaining_coin_a, admin);
            transfer::public_transfer(remaining_coin_b, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 3020)]
    fun test_create_pool_with_liquidity_exceed_amount_a() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create test coins with insufficient amount of coin A
            let coin_b = sui::coin::mint_for_testing<TestCoinA>(1000, scenario.ctx());
            let coin_a = sui::coin::mint_for_testing<TestCoinB>(1000, scenario.ctx());
            
            // Try to create pool with liquidity that exceeds available coin A
            let (position, remaining_coin_a, remaining_coin_b) = factory::create_pool_with_liquidity<TestCoinB, TestCoinA>(
                &mut pools,
                &global_config,
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                std::string::utf8(b""), // url
                0, // tick_lower
                100, // tick_upper
                coin_a, // coin_a_input
                coin_b, // coin_b_input
                100000, // liquidity_amount_a
                100000, // liquidity_amount_b
                false, // fix_amount_b
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            // Return objects to scenario
            transfer::public_transfer(position, admin);
            transfer::public_transfer(remaining_coin_a, admin);
            transfer::public_transfer(remaining_coin_b, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2)]
    fun test_create_pool_with_liquidity_invalid_sqrt_price() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create test coins
            let coin_b = sui::coin::mint_for_testing<TestCoinA>(1000000, scenario.ctx());
            let coin_a = sui::coin::mint_for_testing<TestCoinB>(1000000, scenario.ctx());
            
            // Try to create pool with invalid sqrt price
            let (position, remaining_coin_a, remaining_coin_b) = factory::create_pool_with_liquidity<TestCoinB, TestCoinA>(
                &mut pools,
                &global_config,
                1, // tick_spacing
                0, // invalid current_sqrt_price
                std::string::utf8(b""), // url
                0, // tick_lower
                100, // tick_upper
                coin_a, // coin_a_input
                coin_b, // coin_b_input
                100000, // liquidity_amount_a
                100000, // liquidity_amount_b
                true, // fix_amount_a
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            // Return objects to scenario
            transfer::public_transfer(position, admin);
            transfer::public_transfer(remaining_coin_a, admin);
            transfer::public_transfer(remaining_coin_b, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_fetch_pools_empty() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
        };
        
        scenario.next_tx(admin);
        {
            let pools = scenario.take_shared<Pools>();
            
            // Test fetching pools with empty pool_ids and limit 0
            let result = factory::fetch_pools(&pools, std::vector::empty<sui::object::ID>(), 0);
            assert!(std::vector::length(&result) == 0, 1);
            
            test_scenario::return_shared(pools);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_fetch_pools_with_limit() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
        };
        
        // Add fee tiers and create pools in one transaction
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            config::add_fee_tier(&mut global_config, 2, 2000, scenario.ctx());
            
            let mut pools = scenario.take_shared<Pools>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create first pool
            let pool1 = factory::create_pool_<TestCoinB, TestCoinA>(
                &mut pools,
                &global_config,
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                std::string::utf8(b""), // url
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            // Create second pool
            let pool2 = factory::create_pool_<TestCoinB, TestCoinA>(
                &mut pools,
                &global_config,
                2, // different tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                std::string::utf8(b""), // url
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            transfer::public_transfer(pool2, admin);
            transfer::public_transfer(pool1, admin);
            transfer::public_transfer(admin_cap, admin);
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(pools);
        };
        
        scenario.next_tx(admin);
        {
            let pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Test fetching pools with limit
            let result = factory::fetch_pools(&pools, std::vector::empty<sui::object::ID>(), 1);
            assert!(std::vector::length(&result) == 1, 1);
            
            let result = factory::fetch_pools(&pools, std::vector::empty<sui::object::ID>(), 2);
            assert!(std::vector::length(&result) == 2, 2);
            
            // Get pool keys from the table
            let pool1_key = factory::new_pool_key<TestCoinB, TestCoinA>(1);
            let pool2_key = factory::new_pool_key<TestCoinB, TestCoinA>(2);
            
            // Get pool1 info directly from the table
            let pool1_info = pools.pool_simple_info(pool1_key);
            
            // Test fetching with specific pool key
            let mut pool_keys = std::vector::empty<sui::object::ID>();
            std::vector::push_back(&mut pool_keys, pool1_key);
            
            let result = factory::fetch_pools(&pools, pool_keys, 1);
            assert!(std::vector::length(&result) == 1, 3);
            
            // Verify that returned info matches pool1 info
            let returned_info = std::vector::borrow<PoolSimpleInfo>(&result, 0);
            assert!(returned_info.pool_id() == pool1_info.pool_id(), 4);
            assert!(returned_info.pool_key() == pool1_info.pool_key(), 5);
            assert!(returned_info.tick_spacing() == pool1_info.tick_spacing(), 6);
            let (returned_coin_a, returned_coin_b) = returned_info.coin_types();
            let (pool1_coin_a, pool1_coin_b) = pool1_info.coin_types();
            assert!(returned_coin_a == pool1_coin_a, 7);
            assert!(returned_coin_b == pool1_coin_b, 8);
            
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)]
    fun test_fetch_pools_invalid_pool_id() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
        };
        
        scenario.next_tx(admin);
        {
            let pools = scenario.take_shared<Pools>();
            
            // Test fetching pools with invalid pool_id
            let mut pool_ids = std::vector::empty<sui::object::ID>();
            // Use a completely different ID that doesn't exist
            let invalid_pool_id = sui::object::id_from_address(@0x1234567890abcdef);
            std::vector::push_back(&mut pool_ids, invalid_pool_id);
            let result = factory::fetch_pools(&pools, pool_ids, 1);
            assert!(std::vector::length(&result) == 0, 1);
            
            test_scenario::return_shared(pools);
        };
        
        test_scenario::end(scenario);
    }
}
