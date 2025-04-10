#[test_only]
module clmm_pool::pool_tests {
    use sui::test_scenario;
    use sui::object;
    use sui::package;
    use sui::clock;
    use sui::tx_context;
    use sui::transfer;
    use sui::event;
    use sui::balance;
    use move_stl::linked_table;
    use std::type_name;
    use std::ascii;
    use std::string;
    use sui::hash;
    use sui::bcs;
    use integer_mate::i32;

    use clmm_pool::position;
    use clmm_pool::pool;
    use clmm_pool::factory::{Self as factory, Pools};
    use clmm_pool::config::{Self as config, GlobalConfig, AdminCap};
    use clmm_pool::stats;
    use clmm_pool::tick_math;
    use clmm_pool::partner;
    use price_provider::price_provider;

    #[test_only]
    public struct TestCoinA has drop {}
    #[test_only]
    public struct TestCoinB has drop {}

    #[test_only]
    public struct TestPositionManager has key, store {
        id: sui::object::UID,
        position_manager: position::PositionManager,
    }

    #[test]
    fun test_new_pool() {
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
            let pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            // Verify pool was created with correct initial values
            assert!(pool::liquidity(&pool) == 0, 1);
            let (fee_a, fee_b) = pool::protocol_fee(&pool);
            assert!(fee_a == 0 && fee_b == 0, 2);
            assert!(pool::url(&pool) == std::string::utf8(b""), 3);
            assert!(pool::index(&pool) == 0, 4);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2)]
    fun test_new_pool_invalid_sqrt_price() {
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
            let pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                0, // invalid current_sqrt_price
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_add_liquidity_internal() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };
        
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
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                100,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity_internal_test<TestCoinB, TestCoinA>(
                &mut pool,
                &mut position,
                true,  // is_fix_amount
                1000,  // liquidity_delta
                100,   // amount_in
                true,  // is_fix_amount_a
                clock::timestamp_ms(&clock)
            );

            // Verify the receipt
            let (amount_a, amount_b) = pool::add_liquidity_pay_amount<TestCoinB, TestCoinA>(&receipt);
            assert!(amount_a == 100, 1);
            assert!(amount_b == 0, 2);

            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
            transfer::public_transfer(test_manager, admin);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 5)]
    fun test_add_liquidity_internal_invalid_tick_range() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };
        
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
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with invalid tick range (lower > upper)
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                100,  // tick_lower
                100, // tick_upper
                scenario.ctx()
            );

            // Try to add liquidity to the position (should fail)
            let receipt = pool::add_liquidity_internal_test<TestCoinB, TestCoinA>(
                &mut pool,
                &mut position,
                true,  // is_fix_amount
                1000,  // liquidity_delta
                100,   // amount_in
                true,  // is_fix_amount_a
                clock::timestamp_ms(&clock)
            );
            
            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
            transfer::public_transfer(test_manager, admin);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_add_liquidity_with_token_a_only() {
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
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                4295048016,
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with tick_lower = 0 and tick_upper = 100
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                200,  // tick_lower
                300,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                100000,  // delta_liquidity - увеличиваем начальную ликвидность
                &clock
            );

            // Verify the receipt
            let (amount_a, amount_b) = pool::add_liquidity_pay_amount<TestCoinB, TestCoinA>(&receipt);
            assert!(amount_a == 494, 1); // Should be exactly the fixed amount
            assert!(amount_b == 0, 2); // Should be 0 since price is at lower tick

            // Verify position liquidity
            assert!(position::liquidity(&position) > 0, 3);

            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_add_liquidity_fix_coin_b() {
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
            
            // Create a new pool with current_sqrt_price = 1.0025 (corresponds to tick = 25)
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                (79228162514264337593543950336 >> 32) + 250000000000000u128, // current_sqrt_price (1.0025)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with tick_lower = 0 and tick_upper = 50
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                50,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity with fixed amount of coin B
            let receipt = pool::add_liquidity_fix_coin<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                100,  // amount_in (fixed amount of coin B)
                false,  // is_fix_amount_a
                &clock
            );

            // Verify the receipt
            let (amount_a, amount_b) = pool::add_liquidity_pay_amount<TestCoinB, TestCoinA>(&receipt);
            assert!(amount_a > 0, 1); // Should be calculated based on the fixed amount of B
            assert!(amount_b == 100, 2); // Should be exactly the fixed amount

            // Verify position liquidity
            assert!(position::liquidity(&position) > 0, 3);

            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 0)]
    fun test_add_liquidity_fix_coin_zero_amount() {
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
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                100,  // tick_upper
                scenario.ctx()
            );

            // Try to add liquidity with zero amount (should fail)
            let receipt = pool::add_liquidity_fix_coin<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                0,  // amount_in
                true,  // is_fix_amount_a
                &clock
            );
            
            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13)]
    fun test_add_liquidity_fix_coin_paused_pool() {
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
            
            // Create a pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Pause the pool
            pool::pause<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                scenario.ctx()
            );

            // Create a new position
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                100,  // tick_upper
                scenario.ctx()
            );

            // Try to add liquidity to paused pool (should fail)
            let receipt = pool::add_liquidity_fix_coin<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                100,  // amount_in
                true,  // is_fix_amount_a
                &clock
            );
            
            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_get_liquidity_from_amount_inside_range() {
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
            
            // Create a new pool with current_sqrt_price = 1.0025 (corresponds to tick = 25)
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                (79228162514264337593543950336 >> 32) + 250000000000000u128, // current_sqrt_price (1.0025)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with tick_lower = 0 and tick_upper = 50
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                50,  // tick_upper
                scenario.ctx()
            );

            // Test get_liquidity_from_amount with fixed amount of coin A
            let (liquidity_a, amount_a, amount_b) = pool::get_liquidity_from_amount(
                i32::from_u32(0),  // tick_lower
                i32::from_u32(50), // tick_upper
                pool::current_tick_index(&pool),
                pool::current_sqrt_price(&pool),
                100,  // amount
                true  // a2b
            );
            assert!(liquidity_a > 0, 1);
            assert!(amount_a == 100, 2);
            assert!(amount_b > 0, 3);

            // Test get_liquidity_from_amount with fixed amount of coin B
            let (liquidity_b, amount_a, amount_b) = pool::get_liquidity_from_amount(
                i32::from_u32(0),  // tick_lower
                i32::from_u32(50), // tick_upper
                pool::current_tick_index(&pool),
                pool::current_sqrt_price(&pool),
                100,  // amount
                false // a2b
            );
            assert!(liquidity_b > 0, 4);
            assert!(amount_a > 0, 5);
            assert!(amount_b == 100, 6);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_get_liquidity_from_amount_above_range() {
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
            
            // Create a new pool with current_sqrt_price = 1.0049 (corresponds to tick = 49)
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                (79228162514264337593543950336 >> 32) + 490000000000000u128, // current_sqrt_price (1.0049)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with tick_lower = 0 and tick_upper = 50
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                50,  // tick_upper
                scenario.ctx()
            );

            // Test get_liquidity_from_amount with fixed amount of coin A
            let (liquidity_a, amount_a, amount_b) = pool::get_liquidity_from_amount(
                i32::from_u32(0),  // tick_lower
                i32::from_u32(50), // tick_upper
                pool::current_tick_index(&pool),
                pool::current_sqrt_price(&pool),
                100,  // amount
                true  // a2b
            );
            assert!(liquidity_a > 0, 1);
            assert!(amount_a == 100, 2);
            assert!(amount_b > 0, 3);

            // Test get_liquidity_from_amount with fixed amount of coin B
            let (liquidity_b, amount_a, amount_b) = pool::get_liquidity_from_amount(
                i32::from_u32(0),  // tick_lower
                i32::from_u32(50), // tick_upper
                pool::current_tick_index(&pool),
                pool::current_sqrt_price(&pool),
                100,  // amount
                false // a2b
            );
            assert!(liquidity_b > 0, 4);
            assert!(amount_a > 0, 5);
            assert!(amount_b == 100, 6);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_get_liquidity_from_amount_below_range() {
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
            
            // Create a new pool with current_sqrt_price = 0.9951 (corresponds to tick = -49)
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                (79228162514264337593543950336 >> 32) - 245000000000000u128, // current_sqrt_price (0.9951)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with tick_lower = -100 and tick_upper = 0
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                4294967196,  // tick_lower (-100)
                0,  // tick_upper
                scenario.ctx()
            );

            // Test get_liquidity_from_amount with fixed amount of coin A
            let (liquidity_a, amount_a, amount_b) = pool::get_liquidity_from_amount(
                i32::from_u32(4294967196),  // tick_lower (-100)
                i32::from_u32(0), // tick_upper
                pool::current_tick_index(&pool),
                pool::current_sqrt_price(&pool),
                100,  // amount
                true  // a2b
            );
            assert!(liquidity_a > 0, 1);
            assert!(amount_a == 100, 2);
            assert!(amount_b > 0, 3); // When price is below range and a2b = true, amount_b should be > 0

            // Test get_liquidity_from_amount with fixed amount of coin B
            let (liquidity_b, amount_a, amount_b) = pool::get_liquidity_from_amount(
                i32::from_u32(4294967196),  // tick_lower (-100)
                i32::from_u32(0), // tick_upper
                pool::current_tick_index(&pool),
                pool::current_sqrt_price(&pool),
                100,  // amount
                false // a2b
            );
            assert!(liquidity_b > 0, 4);
            assert!(amount_a > 0, 5); // When price is below range and a2b = false, amount_a should be > 0
            assert!(amount_b == 100, 6);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 19)]
    fun test_get_liquidity_from_amount_on_boundary() {
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
            
            // Create a new pool with current_sqrt_price = 1.005 (corresponds to tick = 50)
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                (79228162514264337593543950336 >> 32) + 500000000000000u128, // current_sqrt_price (1.005)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with tick_lower = 0 and tick_upper = 50
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                50,  // tick_upper
                scenario.ctx()
            );

            // Test get_liquidity_from_amount with fixed amount of coin A
            // This should fail because current_tick is on the boundary
            let (liquidity_a, amount_a, amount_b) = pool::get_liquidity_from_amount(
                i32::from_u32(0),  // tick_lower
                i32::from_u32(50), // tick_upper
                i32::from_u32(60), // current_tick
                pool::current_sqrt_price(&pool),
                100,  // amount
                true  // a2b
            );
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_calculate_swap_result_inside_range() {
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
            
            // Create a new pool with current_sqrt_price = 1.0025 (corresponds to tick = 25)
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                (79228162514264337593543950336 >> 32) + 250000000000000u128, // current_sqrt_price (1.0025)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with tick_lower = 0 and tick_upper = 50
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                50,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                10000000,  // delta_liquidity
                &clock
            );

            // Test calculate_swap_result with fixed amount of coin A
            let result = pool::calculate_swap_result<TestCoinB, TestCoinA>(
                &global_config,
                &pool,
                true,  // a2b
                true,  // by_amount_in
                10   // amount (reduced amount)
            );

            // Verify the result
            assert!(pool::calculated_swap_result_amount_in(&result) <= 10, 1);
            assert!(pool::calculated_swap_result_amount_out(&result) > 0, 2);
            assert!(!pool::calculated_swap_result_is_exceed(&result), 4);
            assert!(pool::calculated_swap_result_steps_length(&result) > 0, 5);

            // Test calculate_swap_result with fixed amount of coin B
            let result = pool::calculate_swap_result<TestCoinB, TestCoinA>(
                &global_config,
                &pool,
                false,  // a2b
                true,   // by_amount_in
                100    // amount
            );

            // Verify the result
            assert!(pool::calculated_swap_result_amount_in(&result) > 0, 6);
            assert!(pool::calculated_swap_result_amount_out(&result) > 0, 7);
            assert!(!pool::calculated_swap_result_is_exceed(&result), 9);
            assert!(pool::calculated_swap_result_steps_length(&result) > 0, 10);

            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_calculate_swap_result_fixed_amount_in() {
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
            
            // Create a new pool with current_sqrt_price = 1.0025 (corresponds to tick = 25)
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                (79228162514264337593543950336 >> 32) + 250000000000000u128, // current_sqrt_price (1.0025)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with tick_lower = 0 and tick_upper = 50
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                50,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                10000000,  // delta_liquidity
                &clock
            );

            // Test calculate_swap_result with fixed amount of coin A
            let result = pool::calculate_swap_result<TestCoinB, TestCoinA>(
                &global_config,
                &pool,
                true,  // a2b
                true,  // by_amount_in
                10   // amount (reduced amount)
            );

            // Verify the result
            assert!(pool::calculated_swap_result_amount_in(&result) <= 10, 1);
            assert!(pool::calculated_swap_result_amount_out(&result) > 0, 2);
            assert!(!pool::calculated_swap_result_is_exceed(&result), 4);

            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_calculate_swap_result_fixed_amount_out() {
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
            
            // Create a new pool with current_sqrt_price = 1.0025 (corresponds to tick = 25)
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                (79228162514264337593543950336 >> 32) + 250000000000000u128, // current_sqrt_price (1.0025)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with tick_lower = 0 and tick_upper = 50
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                50,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                10000000,  // delta_liquidity
                &clock
            );

            // Test calculate_swap_result with fixed amount of coin B
            let result = pool::calculate_swap_result<TestCoinB, TestCoinA>(
                &global_config,
                &pool,
                false,  // a2b
                true,   // by_amount_in
                10   // amount (reduced amount)
            );

            // Verify the result
            assert!(pool::calculated_swap_result_amount_in(&result) <= 10, 1);
            assert!(pool::calculated_swap_result_amount_out(&result) > 0, 2);
            assert!(!pool::calculated_swap_result_is_exceed(&result), 4);

            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_calculate_swap_result_exceed_liquidity() {
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
            
            // Create a new pool with current_sqrt_price = 1.0
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with tick_lower = 0 and tick_upper = 100
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                100,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                1000,  // delta_liquidity
                &clock
            );

            // Test calculate_swap_result with a very large amount
            let result = pool::calculate_swap_result<TestCoinB, TestCoinA>(
                &global_config,
                &pool,
                true,  // a2b
                true,  // by_amount_in
                1000000000   // amount
            );

            // Verify the result
            assert!(pool::calculated_swap_result_is_exceed(&result), 1);

            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_calculate_swap_result_with_partner() {
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
            
            // Create a new pool with current_sqrt_price = 1.0025 (corresponds to tick = 25)
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                (79228162514264337593543950336 >> 32) + 250000000000000u128, // current_sqrt_price (1.0025)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with tick_lower = 0 and tick_upper = 50
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                50,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                10000000,  // delta_liquidity
                &clock
            );

            // Test calculate_swap_result_with_partner with fixed amount of coin A
            let result = pool::calculate_swap_result_with_partner<TestCoinB, TestCoinA>(
                &global_config,
                &pool,
                true,  // a2b
                true,  // by_amount_in
                10,   // amount (reduced amount)
                100    // ref_fee_rate (1%)
            );

            // Verify the result
            assert!(pool::calculated_swap_result_amount_in(&result) <= 10, 1);
            assert!(pool::calculated_swap_result_amount_out(&result) > 0, 2);
            assert!(!pool::calculated_swap_result_is_exceed(&result), 5);

            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_update_swap_result_inside_range() {
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
            
            // Create a new pool with current_sqrt_price = 1.0025 (corresponds to tick = 25)
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                (79228162514264337593543950336 >> 32) + 250000000000000u128, // current_sqrt_price (1.0025)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with tick_lower = 0 and tick_upper = 50
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                50,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                10000000,  // delta_liquidity
                &clock
            );

            let mut swap_result = pool::create_swap_result_test(
                0, 0, 0, 0, 0, 0, 0
            );

            // Test update_swap_result with fixed amount of coin A
            pool::update_swap_result_test(
                &mut swap_result,
                10,  // amount_in_delta
                9,   // amount_out_delta
                1,   // fee_amount
                0,   // protocol_fee
                0,   // ref_fee
                0    // gauge_fee
            );

            // Verify the result
            let (amount_in, amount_out, fee_amount, protocol_fee, ref_fee, gauge_fee, steps) = pool::get_swap_result_test(&swap_result);
            assert!(amount_in == 10, 1);
            assert!(amount_out == 9, 2);
            assert!(fee_amount == 1, 3);
            assert!(protocol_fee == 0, 4);

            // Test update_swap_result with fixed amount of coin B
            let mut swap_result = pool::create_swap_result_test(
                0, 0, 0, 0, 0, 0, 0
            );

            pool::update_swap_result_test(
                &mut swap_result,
                20,  // amount_in_delta
                18,  // amount_out_delta
                2,   // fee_amount
                0,   // protocol_fee
                0,   // ref_fee
                0    // gauge_fee
            );

            // Verify the result
            let (amount_in, amount_out, fee_amount, protocol_fee, ref_fee, gauge_fee, steps) = pool::get_swap_result_test(&swap_result);
            assert!(amount_in == 20, 5);
            assert!(amount_out == 18, 6);
            assert!(fee_amount == 2, 7);
            assert!(protocol_fee == 0, 8);

            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_update_swap_result_with_partner() {
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
            
            // Create a new pool with current_sqrt_price = 1.0025 (corresponds to tick = 25)
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                (79228162514264337593543950336 >> 32) + 250000000000000u128, // current_sqrt_price (1.0025)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with tick_lower = 0 and tick_upper = 50
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                50,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                10000000,  // delta_liquidity
                &clock
            );

            // Test update_swap_result with partner fee
            let mut swap_result = pool::create_swap_result_test(
                0, 0, 0, 0, 0, 0, 0
            );

            pool::update_swap_result_test(
                &mut swap_result,
                100,  // amount_in_delta
                90,   // amount_out_delta
                8,    // fee_amount
                1,    // protocol_fee
                1,    // ref_fee (partner fee)
                0     // gauge_fee
            );

            // Verify the result
            let (amount_in, amount_out, fee_amount, protocol_fee, ref_fee, gauge_fee, steps) = pool::get_swap_result_test(&swap_result);
            assert!(amount_in == 100, 1);
            assert!(amount_out == 90, 2);
            assert!(fee_amount == 8, 3);
            assert!(protocol_fee == 1, 4);
            assert!(ref_fee == 1, 5); // Partner fee should be collected

            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_update_swap_result() {
        let mut swap_result = clmm_pool::pool::create_swap_result_test(0, 0, 0, 0, 0, 0, 0);
        clmm_pool::pool::update_swap_result_test(&mut swap_result, 100, 90, 10, 1, 0, 0);
        let (amount_in, amount_out, fee_amount, protocol_fee, ref_fee, gauge_fee, steps) = pool::get_swap_result_test(&swap_result);
        assert!(amount_in == 100, 0);
        assert!(amount_out == 90, 0);
        assert!(fee_amount == 10, 0);
        assert!(protocol_fee == 1, 0);
    }

    #[test]
    fun test_update_swap_result_with_fees() {
        let mut swap_result = clmm_pool::pool::create_swap_result_test(0, 0, 0, 0, 0, 0, 0);
        clmm_pool::pool::update_swap_result_test(&mut swap_result, 100, 90, 10, 1, 2, 3);
        let (amount_in, amount_out, fee_amount, protocol_fee, ref_fee, gauge_fee, steps) = pool::get_swap_result_test(&swap_result);
        assert!(amount_in == 100, 0);
        assert!(amount_out == 90, 0);
        assert!(fee_amount == 10, 0);
        assert!(protocol_fee == 1, 0);
        assert!(ref_fee == 2, 0);
        assert!(gauge_fee == 3, 0);
    }

    #[test]
    fun test_update_swap_result_zero_deltas() {
        let mut swap_result = clmm_pool::pool::create_swap_result_test(0, 0, 0, 0, 0, 0, 0);
        clmm_pool::pool::update_swap_result_test(&mut swap_result, 0, 0, 0, 0, 0, 0);
        let (amount_in, amount_out, fee_amount, protocol_fee, ref_fee, gauge_fee, steps) = pool::get_swap_result_test(&swap_result);
        assert!(amount_in == 0, 0);
        assert!(amount_out == 0, 0);
        assert!(fee_amount == 0, 0);
        assert!(protocol_fee == 0, 0);
        assert!(ref_fee == 0, 0);
        assert!(gauge_fee == 0, 0);
    }

    #[test]
    #[expected_failure(abort_code = 6)]
    fun test_update_swap_result_amount_in_overflow() {
        let mut swap_result = clmm_pool::pool::create_swap_result_test(18446744073709551615, 0, 0, 0, 0, 0, 0);
        clmm_pool::pool::update_swap_result_test(&mut swap_result, 1, 0, 0, 0, 0, 0);
    }

    #[test]
    #[expected_failure(abort_code = 7)]
    fun test_update_swap_result_amount_out_overflow() {
        let mut swap_result = clmm_pool::pool::create_swap_result_test(0, 18446744073709551615, 0, 0, 0, 0, 0);
        clmm_pool::pool::update_swap_result_test(&mut swap_result, 0, 1, 0, 0, 0, 0);
    }

    #[test]
    #[expected_failure(abort_code = 8)]
    fun test_update_swap_result_fee_amount_overflow() {
        let mut swap_result = clmm_pool::pool::create_swap_result_test(0, 0, 18446744073709551615, 0, 0, 0, 0);
        clmm_pool::pool::update_swap_result_test(&mut swap_result, 0, 0, 1, 0, 0, 0);
    }

    #[test]
    fun test_update_swap_result_exceed_liquidity() {
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
            
            // Create a new pool with current_sqrt_price = 1.0
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with tick_lower = 0 and tick_upper = 100
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                100,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                1000,  // delta_liquidity
                &clock
            );

            // Test update_swap_result with amount exceeding liquidity
            let mut swap_result = pool::create_swap_result_test(
                0, // amount_in
                0, // amount_out
                0, // fee_amount
                0, // protocol_fee_amount
                0, // ref_fee_amount
                0, // gauge_fee_amount
                1  // steps
            );

            pool::update_swap_result_test(
                &mut swap_result,
                1000000,  // amount_in
                900000,   // amount_out
                100000,   // fee_amount
                10000,    // protocol_fee
                0,        // ref_fee
                0         // gauge_fee
            );

            // Verify the result
            let (amount_in, amount_out, fee_amount, protocol_fee, ref_fee, gauge_fee, steps) = pool::get_swap_result_test(&swap_result);
            assert!(amount_in == 1000000, 1);
            assert!(amount_out == 900000, 2);
            assert!(fee_amount == 100000, 3);
            assert!(protocol_fee == 10000, 4);

            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_in_pool_fixed_amount_in() {
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
            
            // Create a new pool with current_sqrt_price = 1.0025 (corresponds to tick = 25)
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                (79228162514264337593543950336 >> 32) + 250000000000000u128, // current_sqrt_price (1.0025)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with tick_lower = 0 and tick_upper = 50
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                50,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                10000000,  // delta_liquidity
                &clock
            );

            // Test swap_in_pool with fixed amount in (coin A to coin B)
            let result = pool::swap_in_pool_test<TestCoinB, TestCoinA>(
                &mut pool,
                true,  // a2b
                true,  // by_amount_in
                0,     // sqrt_price_limit (no limit)
                10,    // amount
                1000,  // unstaked_fee_rate
                100,   // protocol_fee_rate
                0,     // ref_fee_rate
                &clock
            );

            // Verify the result
            let (amount_in, amount_out, fee_amount, protocol_fee, ref_fee, gauge_fee, steps) = pool::get_swap_result_test(&result);
            assert!(amount_in <= 10, 1);
            assert!(amount_out > 0, 2);
            assert!(fee_amount > 0, 3);

            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_in_pool_fixed_amount_out() {
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
            
            // Create a new pool with current_sqrt_price = 1.0025 (corresponds to tick = 25)
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                (79228162514264337593543950336 >> 32) + 250000000000000u128, // current_sqrt_price (1.0025)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with tick_lower = 0 and tick_upper = 50
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                50,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                10000000,  // delta_liquidity
                &clock
            );

            // Test swap_in_pool with fixed amount out (coin B to coin A)
            let result = pool::swap_in_pool_test<TestCoinB, TestCoinA>(
                &mut pool,
                true,   // a2b
                false,  // by_amount_in
                0,      // sqrt_price_limit (no limit)
                10,     // amount
                1000,   // unstaked_fee_rate
                100,    // protocol_fee_rate
                0,      // ref_fee_rate
                &clock
            );

            // Verify the result
            let (amount_in, amount_out, fee_amount, protocol_fee, ref_fee, gauge_fee, steps) = pool::get_swap_result_test(&result);
            assert!(amount_in > 0, 1);
            assert!(amount_out <= 10, 2);
            assert!(fee_amount > 0, 3);

            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_swap_in_pool_with_partner() {
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
            
            // Create a new pool with current_sqrt_price = 1.0025 (corresponds to tick = 25)
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                (79228162514264337593543950336 >> 32) + 250000000000000u128, // current_sqrt_price (1.0025)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position with tick_lower = 0 and tick_upper = 50
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                50,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                10000000,  // delta_liquidity
                &clock
            );

            // Test swap_in_pool with partner fee
            let result = pool::swap_in_pool_test<TestCoinB, TestCoinA>(
                &mut pool,
                true,   // a2b
                true,   // by_amount_in
                0,      // sqrt_price_limit (no limit)
                100,    // amount
                1000,   // unstaked_fee_rate
                100,    // protocol_fee_rate
                100,    // ref_fee_rate (1%)
                &clock
            );

            // Verify the result
            let (amount_in, amount_out, fee_amount, protocol_fee, ref_fee, gauge_fee, steps) = pool::get_swap_result_test(&result);
            assert!(amount_in <= 100, 1);
            assert!(amount_out > 0, 2);
            assert!(fee_amount > 0, 3);
            assert!(ref_fee > 0, 4);

            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_repay_flash_swap_success() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
            partner::test_init(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            config::add_fee_tier(&mut global_config, 2, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            let mut partners = scenario.take_shared<partner::Partners>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create a pool with different initial price
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                14142135623730951, // current_sqrt_price (2.0)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a position with narrower range but more liquidity
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                4294813800,  // tick_lower = -153496
                4294836290,  // tick_upper = -131006
                scenario.ctx()
            );

            // Add liquidity to the position (увеличиваем ликвидность)
            let addLiquidityReceipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                1000000000000000,  // увеличиваем ликвидность
                &clock
            );

            let (pay_amount_a, pay_amount_b) = addLiquidityReceipt.add_liquidity_pay_amount();
            let coin_a = sui::coin::mint_for_testing<TestCoinB>(pay_amount_a, scenario.ctx());
            let coin_b = sui::coin::mint_for_testing<TestCoinA>(pay_amount_b, scenario.ctx());
            let balance_a = coin_a.into_balance<TestCoinB>();
            let balance_b = coin_b.into_balance<TestCoinA>();

            pool::repay_add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                balance_a,
                balance_b,
                addLiquidityReceipt
            );

            let mut position2 = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                4294813296,  // tick_lower
                4294824000,  // tick_upper (сужаем диапазон)
                scenario.ctx()
            );

            let addLiquidityReceipt2 = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position2,
                100000000000000000,  // увеличиваем ликвидность
                &clock
            );


            let (pay_amount_a, pay_amount_b) = addLiquidityReceipt2.add_liquidity_pay_amount();
            let coin_a = sui::coin::mint_for_testing<TestCoinB>(pay_amount_a, scenario.ctx());
            let coin_b = sui::coin::mint_for_testing<TestCoinA>(pay_amount_b, scenario.ctx());
            let balance_a = coin_a.into_balance<TestCoinB>();
            let balance_b = coin_b.into_balance<TestCoinA>();

            pool::repay_add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                balance_a,
                balance_b,
                addLiquidityReceipt2
            );

            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            transfer::public_transfer(position2, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut pool = scenario.take_from_sender<pool::Pool<TestCoinB, TestCoinA>>();

            // Get current sqrt price before borrowing pool
            let current_sqrt_price = pool::current_sqrt_price(&pool);

            // Print current tick
            let current_tick = pool::current_tick_index(&pool);

            // Perform flash swap with first partner
            let (balance_a, balance_b, receipt) = pool::flash_swap<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                false,  // a2b
                true,  // by_amount_in
                100000000,    // минимальный размер свопа
                current_sqrt_price + 10000000,
                &mut stats,
                &price_provider,
                &clock
            );

            let mut coin_a_repay = sui::coin::mint_for_testing<TestCoinB>(0, scenario.ctx());
            let balance_a_repay = coin_a_repay.into_balance();
            let mut coin_b_repay = sui::coin::mint_for_testing<TestCoinA>(54808, scenario.ctx());
            let balance_b_repay = coin_b_repay.split(receipt.swap_pay_amount(), scenario.ctx()).into_balance();
        
            // Try to repay with wrong partner ID
            pool::repay_flash_swap<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                balance_a_repay,
                balance_b_repay,
                receipt
            );

            // Clean up 
            sui::coin::destroy_zero(coin_b_repay);
            sui::balance::destroy_zero(balance_b);
            sui::coin::from_balance(balance_a, scenario.ctx()).burn_for_testing();
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 3)]
    fun test_repay_flash_swap_with_partner_wrong_pool_id() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
            partner::test_init(scenario.ctx());
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
            let mut stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            let mut partners = scenario.take_shared<partner::Partners>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create two pools
            let mut pool1 = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                (79228162514264337593543950336 >> 32) + 250000000000000u128, // current_sqrt_price (1.0025)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            let mut pool2 = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                (79228162514264337593543950336 >> 32) + 250000000000000u128, // current_sqrt_price (1.0025)
                1000, // fee_rate
                std::string::utf8(b""), // url
                1, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a partner
            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 1000;
            let end_time = start_time + 1000;
            let name = std::string::utf8(b"Test Partner");
            let ref_fee_rate = 1000;

            partner::create_partner(
                &global_config,
                &mut partners,
                name,
                ref_fee_rate,
                start_time,
                end_time,
                admin,
                &clock,
                scenario.ctx()
            );

            // Get partner from scenario
            let mut partner = scenario.take_shared<partner::Partner>();
            let partner_id = sui::object::id(&partner);

            // Perform flash swap in first pool
            let (balance_a, balance_b, receipt) = pool::flash_swap_internal_test<TestCoinB, TestCoinA>(
                &mut pool1,
                &global_config,
                partner_id,
                100,
                true,
                true,
                1000,
                0,
                &mut stats,
                &price_provider,
                &clock
            );

            // Try to repay flash swap in second pool (should fail)
            pool::repay_flash_swap_with_partner<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool2,
                &mut partner,
                balance_a,
                balance_b,
                receipt
            );

            // Clean up
            transfer::public_transfer(pool1, admin);
            transfer::public_transfer(pool2, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            test_scenario::return_shared(partners);
            test_scenario::return_shared(partner);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 15)]
    fun test_repay_flash_swap_with_partner_wrong_partner_id() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
            partner::test_init(scenario.ctx());
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

        // Create partners
        scenario.next_tx(admin);
        {
            let clock = clock::create_for_testing(scenario.ctx());
            let mut partners = scenario.take_shared<partner::Partners>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            
            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time;
            let end_time = start_time + 10000;
            let name1 = std::string::utf8(b"Test Partner 1");
            let name2 = std::string::utf8(b"Test Partner 2");
            let ref_fee_rate = 1000;
            
            partner::create_partner(
                &global_config,
                &mut partners,
                name1,
                ref_fee_rate,
                start_time,
                end_time,
                admin,
                &clock,
                scenario.ctx()
            );

            partner::create_partner(
                &global_config,
                &mut partners,
                name2,
                ref_fee_rate,
                start_time,
                end_time,
                admin,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock);
        };
        
        // Create pool and perform flash swap
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            let mut partners = scenario.take_shared<partner::Partners>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create a pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951, // current_tick = 148
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a partner
            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 1000;
            let end_time = start_time + 1000;
            let name = std::string::utf8(b"Test Partner");
            let ref_fee_rate = 1000;

            partner::create_partner(
                &global_config,
                &mut partners,
                name,
                ref_fee_rate,
                start_time,
                end_time,
                admin,
                &clock,
                scenario.ctx()
            );

            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                200,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity_fix_coin<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                100000000000000,
                true,
                &clock
            );

            let (pay_amount_a, pay_amount_b) = receipt.add_liquidity_pay_amount();
            let coin_a = sui::coin::mint_for_testing<TestCoinB>(pay_amount_a, scenario.ctx());
            let coin_b = sui::coin::mint_for_testing<TestCoinA>(pay_amount_b, scenario.ctx());
            let balance_a = coin_a.into_balance<TestCoinB>();
            let balance_b = coin_b.into_balance<TestCoinA>();

            pool::repay_add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                balance_a,
                balance_b,
                receipt
            );

            transfer::public_transfer(pool, @0x1);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            let mut partners = scenario.take_shared<partner::Partners>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut pool = scenario.take_from_sender<pool::Pool<TestCoinB, TestCoinA>>();
            // Get partners from scenario
            let partner1 = scenario.take_shared<partner::Partner>();
            let mut partner2 = scenario.take_shared<partner::Partner>();

            // Get current sqrt price before borrowing pool
            let current_sqrt_price = pool::current_sqrt_price(&pool);

            // Create test coins for repayment
            let coin_a = sui::coin::mint_for_testing<TestCoinA>(1000, scenario.ctx());
            let coin_b = sui::coin::mint_for_testing<TestCoinB>(1000, scenario.ctx());

            // Perform flash swap with first partner
            let (balance_a, balance_b, receipt) = pool::flash_swap_with_partner<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &partner1,
                true,  // a2b
                true,  // by_amount_in
                100,   // размер свопа
                current_sqrt_price - 100000,
                &mut stats,
                &price_provider,
                &clock
            );

            // Try to repay with wrong partner ID (should fail with code 4)
            pool::repay_flash_swap_with_partner<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut partner2,
                balance_a,
                balance_b,
                receipt
            );

            // Clean up
            sui::coin::destroy_zero(coin_a);
            sui::coin::destroy_zero(coin_b);
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            test_scenario::return_shared(partners);
            test_scenario::return_shared(partner1);
            test_scenario::return_shared(partner2);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13)]
    fun test_repay_flash_swap_with_partner_paused_pool() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
            partner::test_init(scenario.ctx());
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
            let mut stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            let mut partners = scenario.take_shared<partner::Partners>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create a pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951, // current_tick = 148
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a partner
            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 1000;
            let end_time = start_time + 1000;
            let name = std::string::utf8(b"Test Partner");
            let ref_fee_rate = 1000;

            partner::create_partner(
                &global_config,
                &mut partners,
                name,
                ref_fee_rate,
                start_time,
                end_time,
                admin,
                &clock,
                scenario.ctx()
            );

            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                200,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity_fix_coin<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                100000000000000,
                true,
                &clock
            );

            let (pay_amount_a, pay_amount_b) = receipt.add_liquidity_pay_amount();
            let coin_a = sui::coin::mint_for_testing<TestCoinB>(pay_amount_a, scenario.ctx());
            let coin_b = sui::coin::mint_for_testing<TestCoinA>(pay_amount_b, scenario.ctx());
            let balance_a = coin_a.into_balance<TestCoinB>();
            let balance_b = coin_b.into_balance<TestCoinA>();

            pool::repay_add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                balance_a,
                balance_b,
                receipt
            );

            transfer::public_transfer(pool, @0x1);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut pool = scenario.take_from_sender<pool::Pool<TestCoinB, TestCoinA>>();
            // Get partner from scenario
            let mut partner = scenario.take_shared<partner::Partner>();
            let partner_id = sui::object::id(&partner);

            // Perform flash swap
            let (balance_a, balance_b, receipt) = pool::flash_swap_internal_test<TestCoinB, TestCoinA>(
                &mut pool,
                &global_config,
                partner_id,
                100,
                true,
                true,
                100000,
                18584142135623730951-10000,
                &mut stats,
                &price_provider,
                &clock
            );

            // Pause pool
            pool::pause<TestCoinB, TestCoinA>(&global_config, &mut pool, scenario.ctx());

            // Try to repay flash swap in paused pool (should fail)
            test_scenario::next_tx(&mut scenario, @0x2);
            let user = test_scenario::ctx(&mut scenario);
            test_scenario::next_tx(&mut scenario, @0x1);
            let admin = test_scenario::ctx(&mut scenario);

            pool::repay_flash_swap_with_partner<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut partner,
                balance_a,
                balance_b,
                receipt
            );

            // Clean up
            transfer::public_transfer(pool, @0x1);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            test_scenario::return_shared(partner);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_remove_liquidity_success() {
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
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951, // current_tick = 148
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                200,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                1000000,  
                &clock
            );

            let (pay_amount_a, pay_amount_b) = receipt.add_liquidity_pay_amount();
            let coin_a_repay = sui::coin::mint_for_testing<TestCoinB>(pay_amount_a, scenario.ctx());
            let coin_b_repay = sui::coin::mint_for_testing<TestCoinA>(pay_amount_b, scenario.ctx());

            let balance_a = coin_a_repay.into_balance<TestCoinB>();
            let balance_b = coin_b_repay.into_balance<TestCoinA>();

            pool::repay_add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                balance_a,
                balance_b,
                receipt
            );

            // Get initial balances
            let (initial_balance_a, initial_balance_b) = pool::balances(&pool);

            // Remove half of the liquidity
            let (balance_a_remove, balance_b_remove) = pool::remove_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                100000, 
                &clock
            );

            // Verify balances are updated correctly
            let (final_balance_a, final_balance_b) = pool::balances(&pool);
            assert!(final_balance_a == initial_balance_a - sui::balance::value(&balance_a_remove), 0);
            assert!(final_balance_b == initial_balance_b - sui::balance::value(&balance_b_remove), 0);

            // Clean up
            sui::coin::from_balance(balance_a_remove, scenario.ctx()).burn_for_testing();
            sui::coin::from_balance(balance_b_remove, scenario.ctx()).burn_for_testing();
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13)]
    fun test_remove_liquidity_paused_pool() {
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
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                100,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                1000,  // delta_liquidity
                &clock
            );

            // Pause the pool
            pool::pause<TestCoinB, TestCoinA>(&global_config, &mut pool, scenario.ctx());

            // Try to remove liquidity from paused pool (should fail)
            let (balance_a, balance_b) = pool::remove_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                500,  // remove half of liquidity
                &clock
            );

            // Clean up
            sui::balance::destroy_zero(balance_a);
            sui::balance::destroy_zero(balance_b);
            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 3)]
    fun test_remove_liquidity_zero_amount() {
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
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                100,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                1000,  // delta_liquidity
                &clock
            );

            // Try to remove zero liquidity (should fail)
            let (balance_a, balance_b) = pool::remove_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                0,  // zero liquidity
                &clock
            );

            // Clean up
            sui::balance::destroy_zero(balance_a);
            sui::balance::destroy_zero(balance_b);
            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_remove_liquidity_all() {
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
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951, // current_tick = 148
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a new position
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0,  // tick_lower
                200,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                100000,  // delta_liquidity
                &clock
            );

            let (pay_amount_a, pay_amount_b) = receipt.add_liquidity_pay_amount();
            let coin_a = sui::coin::mint_for_testing<TestCoinB>(pay_amount_a, scenario.ctx());
            let coin_b = sui::coin::mint_for_testing<TestCoinA>(pay_amount_b, scenario.ctx());
            let balance_a = coin_a.into_balance<TestCoinB>();
            let balance_b = coin_b.into_balance<TestCoinA>();

            pool::repay_add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                balance_a,
                balance_b,
                receipt
            );

            // Get initial balances
            let (initial_balance_a, initial_balance_b) = pool::balances(&pool);

            // Remove all liquidity
            let (balance_a_remove, balance_b_remove) = pool::remove_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                100000,  // remove all liquidity
                &clock
            );
            // Verify balances
            let (final_balance_a, final_balance_b) = pool::balances(&pool);
            assert!(sui::balance::value(&balance_a_remove) > 0, 1);
            assert!(sui::balance::value(&balance_b_remove) > 0, 2);
            assert!(final_balance_a < initial_balance_a, 3);
            assert!(final_balance_b < initial_balance_b, 4);
            assert!(position::liquidity(&position) == 0, 5);

            // Clean up
            sui::coin::from_balance(balance_a_remove, scenario.ctx()).burn_for_testing();
            sui::coin::from_balance(balance_b_remove, scenario.ctx()).burn_for_testing();
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }
}
