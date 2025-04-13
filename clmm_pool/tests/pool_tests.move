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
    use clmm_pool::rewarder;

    use clmm_pool::position;
    use clmm_pool::pool;
    use clmm_pool::factory::{Self as factory, Pools};
    use clmm_pool::config::{Self as config, GlobalConfig, AdminCap};
    use clmm_pool::stats;
    use clmm_pool::tick_math;
    use clmm_pool::partner;
    use clmm_pool::acl;
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
    #[expected_failure(abort_code = position::EInvalidTickRange)]
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
                14142135623730951,
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

            let position_info = pool::borrow_position_info(&pool, sui::object::id<clmm_pool::position::Position>(&position));
            let liquidity = position_info.info_liquidity();
            assert!(liquidity == 1000000000000000, 1);

            let positions_info = pool::fetch_positions(&pool, vector[sui::object::id<clmm_pool::position::Position>(&position), sui::object::id<clmm_pool::position::Position>(&position2)], 1000);
            assert!(positions_info.length() == 2, 2);
            let position_info1 = positions_info[0];
            let liquidity1 = position_info1.info_liquidity();
            assert!(liquidity1 == 1000000000000000, 1);

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

    #[test]
    fun test_flash_swap_internal_basic() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            config::update_unstaked_liquidity_fee_rate(&mut global_config, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create a new pool with current_sqrt_price = 1.0025 (corresponds to tick = 25)
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

            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                100,  // tick_lower
                200,  // tick_upper
                scenario.ctx()
            );

              // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                10000000000,  // delta_liquidity
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

            // Perform flash swap
            let (balance_a, balance_b, swap_receipt) = pool::flash_swap_internal_test<TestCoinB, TestCoinA>(
                &mut pool,
                &global_config,
                sui::object::id_from_address(@0x4), // partner_id
                0, // ref_fee_rate
                true, // a2b - swap A->B
                true, // by_amount_in
                500000, 
                tick_math::min_sqrt_price(), // sqrt_price_limit (changed to min price)
                &mut stats,
                &price_provider,
                &clock
            );

            // Verify swap receipt
            let (fee_amount, ref_fee_amount, protocol_fee_amount, gauge_fee_amount) = pool::fees_amount(&swap_receipt);
            assert!(fee_amount == 500, 3);
            assert!(ref_fee_amount == 0, 4);
            assert!(protocol_fee_amount == 100, 5);
            assert!(gauge_fee_amount == 40, 6);

            // Clean up
            pool::destroy_flash_swap_receipt<TestCoinB, TestCoinA>(swap_receipt);
            
            // Return objects to scenario
            sui::balance::destroy_zero(balance_a);
            sui::coin::from_balance(balance_b, scenario.ctx()).burn_for_testing();
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_flash_swap_internal_borrow_b() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            config::update_unstaked_liquidity_fee_rate(&mut global_config, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create a new pool with current_sqrt_price = 1.0 (changed from 1.0025)
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

            // Create a new position with tick_lower = 0 and tick_upper = 50
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                100,  // tick_lower
                200,  // tick_upper
                scenario.ctx()
            );

              // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                10000000000,  // delta_liquidity
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


            // Perform flash swap (borrow coin B)
            let (balance_a, balance_b, swap_receipt) = pool::flash_swap_internal_test<TestCoinB, TestCoinA>(
                &mut pool,
                &global_config,
                sui::object::id_from_address(@0x0), // partner_id
                0, // ref_fee_rate
                false, // a2b (borrow coin B)
                true, // by_amount_in
                500000,
                tick_math::max_sqrt_price(), // sqrt_price_limit (using max price)
                &mut stats,
                &price_provider,
                &clock
            );

            // Verify swap receipt
            let (fee_amount, ref_fee_amount, protocol_fee_amount, gauge_fee_amount) = pool::fees_amount(&swap_receipt);
            assert!(fee_amount == 500, 3);
            assert!(ref_fee_amount == 0, 4);
            assert!(protocol_fee_amount == 100, 5);
            assert!(gauge_fee_amount == 40, 6);

            // Clean up
            pool::destroy_flash_swap_receipt<TestCoinB, TestCoinA>(swap_receipt);
            
            // Return objects to scenario
            sui::coin::from_balance(balance_a, scenario.ctx()).burn_for_testing();
            sui::balance::destroy_zero(balance_b);
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 0)]
    fun test_flash_swap_internal_zero_amount() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
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
            let clock = clock::create_for_testing(scenario.ctx());
            
            // Create a new pool with current_sqrt_price = 1.0025 (corresponds to tick = 25)
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

            // Test flash swap with zero amount (should fail)
            let (balance_a, balance_b, swap_receipt) = pool::flash_swap_internal_test<TestCoinB, TestCoinA>(
                &mut pool,
                &global_config,
                sui::object::id_from_address(@0x0), // partner_id
                0, // ref_fee_rate
                true, // a2b
                true, // by_amount_in
                0, // amount
                tick_math::min_sqrt_price(), // sqrt_price_limit
                &mut stats,
                &price_provider,
                &clock
            );
            
            // Clean up
            sui::balance::destroy_zero(balance_a);
            sui::balance::destroy_zero(balance_b);
            pool::destroy_flash_swap_receipt<TestCoinB, TestCoinA>(swap_receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_get_amount_by_liquidity_below_range() {
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

            // Calculate expected values
            let tick_lower = i32::from_u32(0);
            let tick_upper = i32::from_u32(50);
            let current_tick = i32::from_u32(4294967196); // -100
            let liquidity = 1000000000000000000;
            let round_up = false;

            // Get sqrt prices for ticks
            let sqrt_price_lower = clmm_pool::tick_math::get_sqrt_price_at_tick(tick_lower);
            let sqrt_price_upper = clmm_pool::tick_math::get_sqrt_price_at_tick(tick_upper);
            
            // Calculate expected amount_a using get_delta_a formula
            let expected_amount_a = clmm_pool::clmm_math::get_delta_a(
                sqrt_price_lower,
                sqrt_price_upper,
                liquidity,
                round_up
            );

            // Test get_amount_by_liquidity when current tick is below range
            let (amount_a, amount_b) = pool::get_amount_by_liquidity(
                tick_lower,
                tick_upper,
                current_tick,
                pool::current_sqrt_price(&pool),
                liquidity,
                round_up
            );

            // Verify results
            assert!(amount_a == expected_amount_a, 1);
            assert!(amount_b == 0, 2);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_get_amount_by_liquidity_in_range() {
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

            // Calculate expected values
            let tick_lower = i32::from_u32(0);
            let tick_upper = i32::from_u32(50);
            let current_tick = pool::current_tick_index(&pool); // 25
            let current_sqrt_price = pool::current_sqrt_price(&pool);
            let liquidity = 1000000000000000000;
            let round_up = false;

            // Get sqrt prices for ticks
            let sqrt_price_lower = clmm_pool::tick_math::get_sqrt_price_at_tick(tick_lower);
            let sqrt_price_upper = clmm_pool::tick_math::get_sqrt_price_at_tick(tick_upper);
            
            // Calculate expected amount_a using get_delta_a formula
            let expected_amount_a = clmm_pool::clmm_math::get_delta_a(
                current_sqrt_price,
                sqrt_price_upper,
                liquidity,
                round_up
            );

            // Calculate expected amount_b using get_delta_b formula
            let expected_amount_b = clmm_pool::clmm_math::get_delta_b(
                sqrt_price_lower,
                current_sqrt_price,
                liquidity,
                round_up
            );

            // Test get_amount_by_liquidity when current tick is in range
            let (amount_a, amount_b) = pool::get_amount_by_liquidity(
                tick_lower,
                tick_upper,
                current_tick,
                current_sqrt_price,
                liquidity,
                round_up
            );

            // Verify results
            assert!(amount_a == expected_amount_a, 1);
            assert!(amount_b == expected_amount_b, 2);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_get_amount_by_liquidity_above_range() {
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

            // Calculate expected values
            let tick_lower = i32::from_u32(0);
            let tick_upper = i32::from_u32(50);
            let current_tick = i32::from_u32(100); // 100
            let current_sqrt_price = pool::current_sqrt_price(&pool);
            let liquidity = 1000000000000000000;
            let round_up = false;

            // Get sqrt prices for ticks
            let sqrt_price_lower = clmm_pool::tick_math::get_sqrt_price_at_tick(tick_lower);
            let sqrt_price_upper = clmm_pool::tick_math::get_sqrt_price_at_tick(tick_upper);
            
            // Calculate expected amount_b using get_delta_b formula
            let expected_amount_b = clmm_pool::clmm_math::get_delta_b(
                sqrt_price_lower,
                sqrt_price_upper,
                liquidity,
                round_up
            );

            // Test get_amount_by_liquidity when current tick is above range
            let (amount_a, amount_b) = pool::get_amount_by_liquidity(
                tick_lower,
                tick_upper,
                current_tick,
                current_sqrt_price,
                liquidity,
                round_up
            );

            // Verify results
            assert!(amount_a == 0, 1);
            assert!(amount_b == expected_amount_b, 2);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_get_amount_by_liquidity_zero_liquidity() {
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

            // Test get_amount_by_liquidity with zero liquidity
            let (amount_a, amount_b) = pool::get_amount_by_liquidity(
                i32::from_u32(0),  // tick_lower
                i32::from_u32(50), // tick_upper
                pool::current_tick_index(&pool), // current_tick
                pool::current_sqrt_price(&pool),
                0, // liquidity
                false // round_up
            );
            assert!(amount_a == 0, 1);
            assert!(amount_b == 0, 2);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_close_position_success() {
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

            // Open a new position
            let position = pool::open_position(
                &global_config,
                &mut pool,
                0, // tick_lower
                50, // tick_upper
                scenario.ctx()
            );

            // Verify position exists
            let position_id = sui::object::id<clmm_pool::position::Position>(&position);
            assert!(pool::is_position_exist(&pool, position_id), 1);

            // Close the position
            pool::close_position(&global_config, &mut pool, position);

            // Verify position no longer exists
            assert!(!pool::is_position_exist(&pool, position_id), 2);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 7)]
    fun test_close_position_with_liquidity() {
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

            // Open a new position
            let mut position = pool::open_position(
                &global_config,
                &mut pool,
                0, // tick_lower
                50, // tick_upper
                scenario.ctx()
            );

            // Add liquidity to make the position non-empty
            let liquidity_delta = 1000;
            
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                liquidity_delta,  // delta_liquidity
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


            // Attempt to close the non-empty position
            // This should abort with error code 7
            pool::close_position(&global_config, &mut pool, position);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13)]
    fun test_close_position_paused_pool() {
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

            // Open a new position
            let position = pool::open_position(
                &global_config,
                &mut pool,
                0, // tick_lower
                50, // tick_upper
                scenario.ctx()
            );

            // Pause the pool
            pool::pause<TestCoinB, TestCoinA>(&global_config, &mut pool, scenario.ctx());

            // Attempt to close position in paused pool
            // This should abort with error code 13
            pool::close_position(&global_config, &mut pool, position);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_update_emission_success() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            rewarder::test_init(scenario.ctx());
        };
        
        // Add fee tier and set rewarder manager role
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            // config::set_rewarder_manager_role(&mut global_config, admin, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = scenario.take_shared<Pools>();
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut rewarderGlobalVault = scenario.take_shared<rewarder::RewarderGlobalVault>();

            // Add sufficient coins to vault
            let coin = sui::coin::mint_for_testing<TestCoinA>(100000000, scenario.ctx());
            let balance = sui::coin::into_balance(coin);
            rewarder::deposit_reward(&global_config, &mut rewarderGlobalVault, balance);
            
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

            // Initialize rewarder
            pool::initialize_rewarder<TestCoinB, TestCoinA, TestCoinA>(
                &global_config,
                &mut pool,
                scenario.ctx()
            );

            // Update emission rate
            let new_emission_rate = 1000;
            pool::update_emission<TestCoinB, TestCoinA, TestCoinA>(
                &global_config,
                &mut pool,
                &rewarderGlobalVault,
                new_emission_rate,
                &clock,
                scenario.ctx()
            );
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(rewarderGlobalVault);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13)]
    fun test_update_emission_paused_pool() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            rewarder::test_init(scenario.ctx());
        };
        
        // Add fee tier and set rewarder manager role
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
            let rewarderGlobalVault = scenario.take_shared<rewarder::RewarderGlobalVault>();

            
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

            // Initialize rewarder
            pool::initialize_rewarder<TestCoinB, TestCoinA, TestCoinA>(
                &global_config,
                &mut pool,
                scenario.ctx()
            );
       
            // Pause the pool
            pool::pause<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                scenario.ctx()
            );

            // Try to update emission in paused pool (should fail)
            pool::update_emission<TestCoinB, TestCoinA, TestCoinA>(
                &global_config,
                &mut pool,
                &rewarderGlobalVault,
                1000,
                &clock,
                scenario.ctx()
            );
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(rewarderGlobalVault);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 8)]
    fun test_update_emission_not_rewarder_manager() {
        let admin = @0x1;
        let not_rewarder_manager = @0x2;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            rewarder::test_init(scenario.ctx());
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
            let rewarderGlobalVault = scenario.take_shared<rewarder::RewarderGlobalVault>();

            
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

            // Initialize rewarder
            pool::initialize_rewarder<TestCoinB, TestCoinA, TestCoinA>(
                &global_config,
                &mut pool,
                scenario.ctx()
            );
            
            // Switch to non-rewarder manager account
            scenario.next_tx(not_rewarder_manager);
            
            // Try to update emission without rewarder manager role (should fail)
            pool::update_emission<TestCoinB, TestCoinA, TestCoinA>(
                &global_config,
                &mut pool,
                &rewarderGlobalVault,
                1000,
                &clock,
                scenario.ctx()
            );
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(rewarderGlobalVault);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_calculate_and_update_fee_success() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
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
            let mut stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951, 
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Open a new position
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                100,  // tick_lower
                200,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                1000000000000,  // delta_liquidity
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

            let (balance_a, balance_b, swap_receipt) = pool::flash_swap_internal_test<TestCoinB, TestCoinA>(
                &mut pool,
                &global_config,
                sui::object::id_from_address(@0x0), // partner_id
                0, // ref_fee_rate
                true, // a2b
                true, // by_amount_in
                100000, // amount
                tick_math::min_sqrt_price(), // sqrt_price_limit
                &mut stats,
                &price_provider,
                &clock
            );

            let (balance2_a, balance2_b, swap_receipt2) = pool::flash_swap_internal_test<TestCoinB, TestCoinA>(
                &mut pool,
                &global_config,
                sui::object::id_from_address(@0x0), // partner_id
                0, // ref_fee_rate
                false, // a2b
                true, // by_amount_in
                100000, // amount
                tick_math::max_sqrt_price(), // sqrt_price_limit
                &mut stats,
                &price_provider,
                &clock
            );

            // Calculate and update fees
            let position_id = sui::object::id(&position);
            let (fee_a, fee_b) = pool::calculate_and_update_fee<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                position_id
            );

            // Verify fees are non-zero
            assert!(fee_a == 79, 1);
            assert!(fee_b == 79, 1);

            // Clean up
            sui::balance::destroy_zero(balance_a);
            sui::coin::from_balance(balance_b, scenario.ctx()).burn_for_testing();
            sui::coin::from_balance(balance2_a, scenario.ctx()).burn_for_testing();
            sui::balance::destroy_zero(balance2_b);
            // Return objects to scenario
            pool::destroy_flash_swap_receipt<TestCoinB, TestCoinA>(swap_receipt);
            pool::destroy_flash_swap_receipt<TestCoinB, TestCoinA>(swap_receipt2);
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13)]
    fun test_calculate_and_update_fee_paused_pool() {
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

            // Open a new position
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
            pool::pause<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                scenario.ctx()
            );

            // Try to calculate and update fees in paused pool (should fail)
            let position_id = sui::object::id(&position);
            pool::calculate_and_update_fee<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                position_id
            );
            
            // Return objects to scenario
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
    fun test_calculate_and_update_fullsail_distribution_success() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
            gauge_cap::gauge_cap::init_test(scenario.ctx());
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
            let mut clock = clock::create_for_testing(scenario.ctx());
            let mut stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::gauge_cap::CreateCap>();
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951, // current_sqrt_price (1.0)
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create gauge cap
            let gauge_cap = gauge_cap::gauge_cap::create_gauge_cap(
                &create_gauge_cap,
                sui::object::id(&pool), // gauge_id
                sui::object::id(&pool),
                scenario.ctx()
            );

            // Initialize fullsail distribution gauge
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);

            // Open a new position
             let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                100,  // tick_lower
                200,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                100000000,  // delta_liquidity
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

            let (balance_a, balance_b, swap_receipt) = pool::flash_swap_internal_test<TestCoinB, TestCoinA>(
                &mut pool,
                &global_config,
                sui::object::id_from_address(@0x0), // partner_id
                0, // ref_fee_rate
                true, // a2b
                true, // by_amount_in
                100000, // amount
                tick_math::min_sqrt_price(), // sqrt_price_limit
                &mut stats,
                &price_provider,
                &clock
            );

            let (balance_a2, balance_b2, swap_receipt2) = pool::flash_swap_internal_test<TestCoinB, TestCoinA>(
                &mut pool,
                &global_config,
                sui::object::id_from_address(@0x0), // partner_id
                0, // ref_fee_rate
                false, // a2b
                true, // by_amount_in
                100000, // amount
                tick_math::max_sqrt_price(), // sqrt_price_limit
                &mut stats,
                &price_provider,
                &clock
            );

            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                1000,  // liquidity
                integer_mate::i32::from(100),  // tick_lower
                integer_mate::i32::from(200),  // tick_upper
                &clock
            );

            pool::sync_fullsail_distribution_reward<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                1000<<64,
                1000,
                100
            );

            clock::increment_for_testing(&mut clock, 10000);

            // Update fullsail distribution growth global
            pool::update_fullsail_distribution_growth_global<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                &clock
            );

            let (fee_growth_a, fee_growth_b, reward_growth, points_growth, fullsail_distribution_growth) = pool::get_all_growths_in_tick_range(
                &pool,
                integer_mate::i32::from(100),
                integer_mate::i32::from(200)
            );

            assert!(fee_growth_a == 14757395258967, 11);
            assert!(fee_growth_b == 14757395258967, 12);
            assert!(reward_growth.length() == 0, 13);
            assert!(points_growth == 0, 14);
            assert!(fullsail_distribution_growth == 18446744073709551616, 15);

            // Calculate and update fullsail distribution
            let position_id = sui::object::id(&position);
            let fullsail_amount = pool::calculate_and_update_fullsail_distribution<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                position_id
            );

            // Verify fullsail amount is non-zero
            assert!(fullsail_amount == 100000000, 1);
            
            // Return objects to scenario
            pool::destroy_flash_swap_receipt<TestCoinB, TestCoinA>(swap_receipt);
            pool::destroy_flash_swap_receipt<TestCoinB, TestCoinA>(swap_receipt2);
            sui::balance::destroy_zero(balance_a);
            sui::balance::destroy_zero(balance_b2);
            sui::coin::from_balance(balance_b, scenario.ctx()).burn_for_testing();
            sui::coin::from_balance(balance_a2, scenario.ctx()).burn_for_testing();
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            transfer::public_transfer(gauge_cap, admin);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13)]
    fun test_calculate_and_update_fullsail_distribution_paused_pool() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
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

            // Open a new position
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
            pool::pause<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                scenario.ctx()
            );

            // Try to calculate and update fullsail distribution in paused pool (should fail)
            let position_id = sui::object::id(&position);
            pool::calculate_and_update_fullsail_distribution<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                position_id
            );
            
            // Return objects to scenario
            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_update_fullsail_distribution_growth_global_success() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
            gauge_cap::gauge_cap::init_test(scenario.ctx());
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
            let mut clock = clock::create_for_testing(scenario.ctx());
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::gauge_cap::CreateCap>();
            let stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951,
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create gauge cap
            let gauge_cap = gauge_cap::gauge_cap::create_gauge_cap(
                &create_gauge_cap,
                sui::object::id(&pool), // gauge_id
                sui::object::id(&pool),
                scenario.ctx()
            );

            // Initialize fullsail distribution gauge
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);

            // Add liquidity to the pool to create staked liquidity
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
                1000000000,  // delta_liquidity
                &clock
            );

            // Stake liquidity for fullsail distribution
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                1000,  // liquidity
                integer_mate::i32::from(100),  // tick_lower
                integer_mate::i32::from(200),  // tick_upper
                &clock
            );

            pool::sync_fullsail_distribution_reward<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                1000<<64,
                100000,
                100
            );

            clock::increment_for_testing(&mut clock, 1000000);

            // Update fullsail distribution growth global
            pool::update_fullsail_distribution_growth_global<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                &clock
            );

            // Verify that growth global was updated
            let growth_global = pool::get_fullsail_distribution_growth_global<TestCoinB, TestCoinA>(&pool);
            assert!((growth_global>>64) == 100, 1);
            
            // Return objects to scenario
            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            transfer::public_transfer(gauge_cap, admin);
            test_scenario::return_shared(pools);
             transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13)]
    fun test_update_fullsail_distribution_growth_global_paused_pool() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
            gauge_cap::gauge_cap::init_test(scenario.ctx());
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
            let mut clock = clock::create_for_testing(scenario.ctx());
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::gauge_cap::CreateCap>();
            let stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951,
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create gauge cap
            let gauge_cap = gauge_cap::gauge_cap::create_gauge_cap(
                &create_gauge_cap,
                sui::object::id(&pool), // gauge_id
                sui::object::id(&pool),
                scenario.ctx()
            );

            // Initialize fullsail distribution gauge
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);


            pool::pause<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                scenario.ctx()
            );
            
            // Update fullsail distribution growth global
            pool::update_fullsail_distribution_growth_global<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                &clock
            );
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(gauge_cap, admin);
            test_scenario::return_shared(pools);
            // test_scenario::return_shared(create_gauge_cap);
             transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_unstake_from_fullsail_distribution_success() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
            gauge_cap::gauge_cap::init_test(scenario.ctx());
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
            let mut clock = clock::create_for_testing(scenario.ctx());
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::gauge_cap::CreateCap>();
            let stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951,
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create gauge cap
            let gauge_cap = gauge_cap::gauge_cap::create_gauge_cap(
                &create_gauge_cap,
                sui::object::id(&pool), // gauge_id
                sui::object::id(&pool),
                scenario.ctx()
            );

            // Initialize fullsail distribution gauge
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);

            // Add liquidity to the pool to create staked liquidity
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
                1000000000,  // delta_liquidity
                &clock
            );

            // Stake liquidity for fullsail distribution
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                1000,  // liquidity
                i32::from(100),  // tick_lower
                i32::from(200),  // tick_upper
                &clock
            );

            // Verify initial staked liquidity
            let initial_staked_liquidity = pool::get_fullsail_distribution_staked_liquidity<TestCoinB, TestCoinA>(&pool);
            assert!(initial_staked_liquidity == 1000, 1);

            // Unstake liquidity
            pool::unstake_from_fullsail_distribution<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                500,  // liquidity to unstake
                i32::from(100),  // tick_lower
                i32::from(200),  // tick_upper
                &clock
            );

            // Verify staked liquidity was reduced
            let final_staked_liquidity = pool::get_fullsail_distribution_staked_liquidity<TestCoinB, TestCoinA>(&pool);
            assert!(final_staked_liquidity == 500, 2);
            
            // Return objects to scenario
            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            transfer::public_transfer(gauge_cap, admin);
            test_scenario::return_shared(pools);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13)]
    fun test_unstake_from_fullsail_distribution_paused_pool() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
            gauge_cap::gauge_cap::init_test(scenario.ctx());
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
            let mut clock = clock::create_for_testing(scenario.ctx());
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::gauge_cap::CreateCap>();
            let stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951,
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create gauge cap
            let gauge_cap = gauge_cap::gauge_cap::create_gauge_cap(
                &create_gauge_cap,
                sui::object::id(&pool), // gauge_id
                sui::object::id(&pool),
                scenario.ctx()
            );

            // Initialize fullsail distribution gauge
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);

            // Add liquidity to the pool to create staked liquidity
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

            // Stake liquidity for fullsail distribution
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                1000,  // liquidity
                i32::from(100),  // tick_lower
                i32::from(200),  // tick_upper
                &clock
            );

            // Pause the pool
            pool::pause<TestCoinB, TestCoinA>(&global_config, &mut pool, scenario.ctx());

            // Try to unstake liquidity from paused pool (should fail)
            pool::unstake_from_fullsail_distribution<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                500,  // liquidity to unstake
                i32::from(100),  // tick_lower
                i32::from(200),  // tick_upper
                &clock
            );

            // Verify staked liquidity was reduced
            let final_staked_liquidity = pool::get_fullsail_distribution_staked_liquidity<TestCoinB, TestCoinA>(&pool);
            assert!(final_staked_liquidity == 500, 2);
            
            // Return objects to scenario
            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            transfer::public_transfer(gauge_cap, admin);
            test_scenario::return_shared(pools);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_update_fee_rate_success() {
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

            // Update fee rate
            pool::update_fee_rate<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                2000, // new fee rate
                scenario.ctx()
            );

            // Verify fee rate was updated
            assert!(pool::fee_rate<TestCoinB, TestCoinA>(&pool) == 2000, 1);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13)]
    fun test_update_fee_rate_paused_pool() {
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

            // Pause the pool
            pool::pause<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                scenario.ctx()
            );

            // Try to update fee rate on paused pool
            pool::update_fee_rate<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                2000, // new fee rate
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
    #[expected_failure(abort_code = 9)]
    fun test_update_fee_rate_exceeds_max() {
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

            // Try to update fee rate with value exceeding max
            pool::update_fee_rate<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                config::max_fee_rate() + 1, // fee rate exceeding max
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
    /// Test update_position_url function
    /// Verifies that:
    /// 1. URL can be updated successfully for an active pool
    fun test_update_position_url_success() {
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
                std::string::utf8(b"https://old-url.com"), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Update URL
            let new_url = std::string::utf8(b"https://new-url.com");
            pool::update_position_url<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                new_url,
                scenario.ctx()
            );

            // Verify URL was updated
            assert!(pool::url<TestCoinB, TestCoinA>(&pool) == new_url, 1);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    /// Test update_position_url function with paused pool
    /// Verifies that:
    /// 1. URL cannot be updated for a paused pool
    #[expected_failure(abort_code = 13)]
    fun test_update_position_url_paused_pool() {
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
                std::string::utf8(b"https://old-url.com"), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Pause the pool
            pool::pause<TestCoinB, TestCoinA>(&global_config, &mut pool, scenario.ctx());

            // Try to update URL - should fail with abort code 13
            let new_url = std::string::utf8(b"https://new-url.com");
            pool::update_position_url<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                new_url,
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
    fun test_update_unstaked_liquidity_fee_rate_success() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
        };
        
        // Add fee tier and create pool
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        // Update unstaked liquidity fee rate
        scenario.next_tx(admin);
        {
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
                1000, // fee_rate
                std::string::utf8(b"https://old-url.com"), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );            
            pool::update_unstaked_liquidity_fee_rate(&global_config, &mut pool, 3000, scenario.ctx());
            assert!(pool::unstaked_liquidity_fee_rate<TestCoinB, TestCoinA>(&pool) == 3000, 1);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
            transfer::public_transfer(pool, admin);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 13)]
    fun test_update_unstaked_liquidity_fee_rate_paused_pool() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
        };
        
        // Add fee tier and create pool
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        // Try to update unstaked liquidity fee rate on paused pool
        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
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
            pool::pause<TestCoinB, TestCoinA>(&global_config, &mut pool, scenario.ctx());

            pool::update_unstaked_liquidity_fee_rate(&global_config, &mut pool, 2000, scenario.ctx());
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);

            transfer::public_transfer(pool, admin);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 9)]
    fun test_update_unstaked_liquidity_fee_rate_exceeds_max() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
        };
        
        // Add fee tier and create pool
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
            
            pool::update_unstaked_liquidity_fee_rate(&global_config, &mut pool, 100000, scenario.ctx()); // Max is 10000
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
            transfer::public_transfer(pool, admin);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 9)]
    fun test_update_unstaked_liquidity_fee_rate_below_min() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
        };
        
        // Add fee tier and create pool
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
            pool::update_unstaked_liquidity_fee_rate(&global_config, &mut pool, 72057594037927935, scenario.ctx());
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
            transfer::public_transfer(pool, admin);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 9)]
    fun test_update_unstaked_liquidity_fee_rate_same_value() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
        };
        
        // Add fee tier and create pool
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
            let current_fee_rate = pool::unstaked_liquidity_fee_rate<TestCoinB, TestCoinA>(&pool);
            pool::update_unstaked_liquidity_fee_rate(&global_config, &mut pool, current_fee_rate, scenario.ctx());
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
            transfer::public_transfer(pool, admin);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    /// Test successful points calculation and update
    /// Verifies that:
    /// 1. Points are calculated and updated correctly for a position
    /// 2. Points growth is updated in the pool
    /// 3. Points are accumulated in the position
    fun test_calculate_and_update_points_success() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            gauge_cap::gauge_cap::init_test(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            let mut global_config = test_scenario::take_shared<GlobalConfig>(&scenario);
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let pools = test_scenario::take_shared<Pools>(&scenario);
            let global_config = test_scenario::take_shared<GlobalConfig>(&scenario);
            let mut clock = clock::create_for_testing(scenario.ctx());
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::gauge_cap::CreateCap>();
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951,
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            let gauge_cap = gauge_cap::gauge_cap::create_gauge_cap(
                &create_gauge_cap,
                sui::object::id(&pool), // gauge_id
                sui::object::id(&pool),
                scenario.ctx()
            );

            // Initialize fullsail distribution gauge
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);
            
            // Create a position
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                100,  // tick_lower
                300,  // tick_upper
                scenario.ctx()
            );

            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                1<<64,  // delta_liquidity
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

            clock::increment_for_testing(&mut clock, 3600000000000);
            
            // Calculate and update points
            let points = pool::calculate_and_update_points<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                sui::object::id(&position),
                &clock
            );
            
            // Verify points were calculated and updated
            assert!(points == 3600000000000000, 1);

            let pointsInTickRange = pool::get_points_in_tick_range<TestCoinB, TestCoinA>(
                &pool,
                integer_mate::i32::from(100),
                integer_mate::i32::from(200)
            );
            assert!(pointsInTickRange == 3600000000000000, 2);

            let (_, _, _, points_growth, _) = pool::get_all_growths_in_tick_range(
                &pool,
                integer_mate::i32::from(100),
                integer_mate::i32::from(200)
            );
            assert!(points_growth == 3600000000000000, 14);
            
            // Cleanup
            transfer::public_transfer(position, admin);
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            transfer::public_transfer(gauge_cap, admin);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    /// Test points calculation and update for a non-existent position
    /// Verifies that:
    /// 1. Attempting to calculate and update points for a non-existent position fails
    #[expected_failure(abort_code = position::EPositionNotFound)]
    fun test_calculate_and_update_points_nonexistent() {
        let admin = @0x123;
        let mut scenario = sui::test_scenario::begin(admin);
        {
            // Initialize factory and configuration
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
            
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951,
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a fake position ID
            let fake_position_id = sui::object::id_from_address(@0x456);

            // Attempt to calculate and update points for non-existent position
            let _points = pool::calculate_and_update_points<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                fake_position_id,
                &clock
            );

            // Transfer objects
            sui::transfer::public_transfer(pool, admin);
            sui::transfer::public_transfer(global_config, admin);
            clock::destroy_for_testing(clock);
        };
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 13)]
    fun test_calculate_and_update_points_pool_paused() {
        let admin = @0x123;
        let mut scenario = sui::test_scenario::begin(admin);
        {
            // Initialize factory and configuration
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
            
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951,
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

            // Create a fake position ID
            let position_id = sui::object::id_from_address(@0x456);

            // Attempt to calculate and update points for non-existent position
            let _points = pool::calculate_and_update_points<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                position_id,
                &clock
            );

            // Transfer objects
            sui::transfer::public_transfer(pool, admin);
            sui::transfer::public_transfer(global_config, admin);
            clock::destroy_for_testing(clock);
        };
        scenario.end();
    }

    #[test]
    /// Test calculate_and_update_rewards method
    /// Verifies that:
    /// 1. Rewards are calculated and updated correctly for a position
    /// 2. Rewards growth is updated in the pool
    /// 3. Rewards are accumulated in the position
    fun test_calculate_and_update_rewards() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            gauge_cap::gauge_cap::init_test(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
            rewarder::test_init(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = test_scenario::take_from_sender<config::AdminCap>(&scenario);
            let mut global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            config::add_role(&admin_cap, &mut global_config, admin, acl::rewarder_manager_role());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            let mut clock = clock::create_for_testing(scenario.ctx());
            let mut stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::gauge_cap::CreateCap>();
            let mut rewarderGlobalVault = scenario.take_shared<rewarder::RewarderGlobalVault>();

            // Add sufficient coins to vault
            let balance = sui::coin::into_balance(sui::coin::mint_for_testing<TestCoinA>(10000000000, scenario.ctx()));
            rewarder::deposit_reward(&global_config, &mut rewarderGlobalVault, balance);

            let balance_b = sui::coin::into_balance(sui::coin::mint_for_testing<TestCoinB>(10000000000, scenario.ctx()));
            rewarder::deposit_reward(&global_config, &mut rewarderGlobalVault, balance_b);
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951,
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create gauge cap
            let gauge_cap = gauge_cap::gauge_cap::create_gauge_cap(
                &create_gauge_cap,
                sui::object::id(&pool), // gauge_id
                sui::object::id(&pool),
                scenario.ctx()
            );

            // Initialize fullsail distribution gauge
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);

            // Initialize rewarder
            pool::initialize_rewarder<TestCoinB, TestCoinA, TestCoinA>(
                &global_config,
                &mut pool,
                scenario.ctx()
            );
            pool::initialize_rewarder<TestCoinB, TestCoinA, TestCoinB>(
                &global_config,
                &mut pool,
                scenario.ctx()
            );

            // Update emission rate
            let new_emission_rate = 10000000000;
            pool::update_emission<TestCoinB, TestCoinA, TestCoinA>(
                &global_config,
                &mut pool,
                &rewarderGlobalVault,
                new_emission_rate,
                &clock,
                scenario.ctx()
            );

            pool::update_emission<TestCoinB, TestCoinA, TestCoinB>(
                &global_config,
                &mut pool,
                &rewarderGlobalVault,
                new_emission_rate,
                &clock,
                scenario.ctx()
            );

            // Create a position
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                100, // tick_lower
                200, // tick_upper
                scenario.ctx()
            );
            
            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                90<<64, // delta_liquidity
                &clock
            );
            
            // Get balances from receipt
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

            clock::increment_for_testing(&mut clock, 3600000000000000);

            let (balance_a, balance_b, swap_receipt) = pool::flash_swap_internal_test<TestCoinB, TestCoinA>(
                &mut pool,
                &global_config,
                sui::object::id_from_address(@0x0), // partner_id
                0, // ref_fee_rate
                true, // a2b
                true, // by_amount_in
                100000, // amount
                tick_math::min_sqrt_price(), // sqrt_price_limit
                &mut stats,
                &price_provider,
                &clock
            );

            // Cleanup
            pool::destroy_flash_swap_receipt<TestCoinB, TestCoinA>(swap_receipt);
            sui::balance::destroy_zero(balance_a);
            sui::coin::from_balance(balance_b, scenario.ctx()).burn_for_testing();
            transfer::public_transfer(position, admin);
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(global_config);
            transfer::public_transfer(gauge_cap, admin);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(rewarderGlobalVault);
        };

        scenario.next_tx(admin);
        {
            let global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            let mut clock = clock::create_for_testing(scenario.ctx());
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::gauge_cap::CreateCap>();
            let mut pool = scenario.take_from_sender<pool::Pool<TestCoinB, TestCoinA>>();
            let position = scenario.take_from_sender<position::Position>();
            let mut rewarderGlobalVault = scenario.take_shared<rewarder::RewarderGlobalVault>();


            // Increment time to accumulate rewards
            clock::increment_for_testing(&mut clock, 3600000000000000);

            let points = pool::get_points_in_tick_range<TestCoinB, TestCoinA>(
                &pool,
                integer_mate::i32::from(100),
                integer_mate::i32::from(200)
            );
            std::debug::print(&std::string::utf8(b"points"));
            std::debug::print(&points);

            let rewardA = pool::calculate_and_update_reward<TestCoinB, TestCoinA, TestCoinA>(
                &global_config,
                &mut pool,
                sui::object::id(&position),
                &clock
            );
            assert!(&rewardA == 1890, 2);

            let rewardB = pool::calculate_and_update_reward<TestCoinB, TestCoinA, TestCoinB>(
                &global_config,
                &mut pool,
                sui::object::id(&position),
                &clock
            );
            assert!(&rewardB == 1890, 3);
            // Calculate and update rewards
            let rewards = pool::calculate_and_update_rewards<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                sui::object::id(&position),
                &clock
            );
            // Verify rewards were calculated and updated
            assert!(vector::length(&rewards) == 2, 1);
            assert!(&rewards[0] == 1890, 2);
            assert!(&rewards[1] == 1890, 3);

            let rewardA = pool::get_position_reward<TestCoinB, TestCoinA, TestCoinA>(
                &pool,
                sui::object::id(&position)
            );
            assert!(rewardA == 1890, 2);

            let rewardB = pool::get_position_reward<TestCoinB, TestCoinA, TestCoinB>(
                &pool,
                sui::object::id(&position)
            );
            assert!(rewardB == 1890, 3);
            
            let rewards_in_tick_range = pool::get_rewards_in_tick_range<TestCoinB, TestCoinA>(
                &pool,
                integer_mate::i32::from(100),
                integer_mate::i32::from(200)
            );
            assert!(vector::length(&rewards_in_tick_range) == 2, 1);
            assert!(&rewards_in_tick_range[0] == 21, 2);
            assert!(&rewards_in_tick_range[1] == 21, 3);
            
            let (_, _, reward_growth, _, _) = pool::get_all_growths_in_tick_range(
                &pool,
                integer_mate::i32::from(100),
                integer_mate::i32::from(200)
            );

            assert!(vector::length(&reward_growth) == 2, 1);
            assert!(&reward_growth[0] == 21, 2);
            assert!(&reward_growth[1] == 21, 3);

            let rewardBalanceA = pool::collect_reward<TestCoinB, TestCoinA, TestCoinA>(
                &global_config,
                &mut pool,
                &position,
                &mut rewarderGlobalVault,
                true,
                &clock
            );
            assert!(sui::balance::value(&rewardBalanceA) == 1890, 1);

            let rewardBalanceB = pool::collect_reward<TestCoinB, TestCoinA, TestCoinB>(
                &global_config,
                &mut pool,
                &position,
                &mut rewarderGlobalVault,
                true,
                &clock
            );
            assert!(sui::balance::value(&rewardBalanceB) == 1890, 1);
            
            // Cleanup
            sui::coin::from_balance(rewardBalanceA, scenario.ctx()).burn_for_testing();
            sui::coin::from_balance(rewardBalanceB, scenario.ctx()).burn_for_testing();
            transfer::public_transfer(position, admin);
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(global_config);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(price_provider);
            test_scenario::return_shared(rewarderGlobalVault);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    /// Test collect_fee method for unstaked position
    /// Verifies that:
    /// 1. Fees are collected correctly for an unstaked position
    /// 2. Fee amounts are updated when update_fee is true
    /// 3. Fee amounts are reset when update_fee is false
    fun test_collect_fee_unstaked() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = test_scenario::take_from_sender<config::AdminCap>(&scenario);
            let mut global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            let clock = clock::create_for_testing(scenario.ctx());
            let mut stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951,
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );

            // Create a position
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                100, // tick_lower
                200, // tick_upper
                scenario.ctx()
            );
            
            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                90<<64, // delta_liquidity
                &clock
            );
            
            // Get balances from receipt
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

            let (balance_a, balance_b, receipt) = pool::flash_swap<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                false,  // a2b
                true,  // by_amount_in
                100000000,    // минимальный размер свопа
                18584142135623730951 + 10000000,
                &mut stats,
                &price_provider,
                &clock
            );

            let (balance_a2, balance_b2, receipt2) = pool::flash_swap<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                true,  // a2b
                true,  // by_amount_in
                100000000,    // минимальный размер свопа
                18584142135623730951 - 10000000,
                &mut stats,
                &price_provider,
                &clock
            );

            // Collect fees with update_fee = true
            let (fee_a, fee_b) = pool::collect_fee<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &position,
                true
            );

            std::debug::print(&fee_a);
            std::debug::print(&fee_b);
            
            // Verify fees were collected
            assert!(sui::balance::value(&fee_a) == 79920, 1);
            assert!(sui::balance::value(&fee_b) == 79920, 2);
            
            // Cleanup
            pool::destroy_flash_swap_receipt<TestCoinB, TestCoinA>(receipt);
            sui::coin::from_balance(balance_a, scenario.ctx()).burn_for_testing();
            sui::coin::from_balance(balance_b, scenario.ctx()).burn_for_testing();
            pool::destroy_flash_swap_receipt<TestCoinB, TestCoinA>(receipt2);
            sui::coin::from_balance(balance_b2, scenario.ctx()).burn_for_testing();
            sui::coin::from_balance(balance_a2, scenario.ctx()).burn_for_testing();
            sui::coin::from_balance(fee_a, scenario.ctx()).burn_for_testing();
            sui::coin::from_balance(fee_b, scenario.ctx()).burn_for_testing();
            transfer::public_transfer(position, admin);
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    /// Test collect_fee method for staked position
    /// Verifies that:
    /// 1. Fees are not collected for a staked position
    /// 2. Zero balances are returned
    fun test_collect_fee_staked() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            gauge_cap::gauge_cap::init_test(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = test_scenario::take_from_sender<config::AdminCap>(&scenario);
            let mut global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let mut pools = test_scenario::take_shared<factory::Pools>(&scenario);
            let global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            let clock = clock::create_for_testing(scenario.ctx());
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::gauge_cap::CreateCap>();
            
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951,
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            // Create gauge cap
            let gauge_cap = gauge_cap::gauge_cap::create_gauge_cap(
                &create_gauge_cap,
                sui::object::id(&pool), // gauge_id
                sui::object::id(&pool),
                scenario.ctx()
            );

            // Initialize fullsail distribution gauge
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);

            // Create a position
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                0, // tick_lower
                100, // tick_upper
                scenario.ctx()
            );
            
            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                1000000, // delta_liquidity
                &clock
            );
            
            // Get balances from receipt
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

            // Stake the position
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                1000000, // liquidity
                integer_mate::i32::from(0), // tick_lower
                integer_mate::i32::from(100), // tick_upper
                &clock
            );

            // Collect fees
            let (fee_a, fee_b) = pool::collect_fee<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &position,
                true
            );
            
            // Verify fees were not collected (zero balances)
            assert!(sui::balance::value(&fee_a) == 0, 1);
            assert!(sui::balance::value(&fee_b) == 0, 2);
            
            // Cleanup
            sui::balance::destroy_zero(fee_a);
            sui::balance::destroy_zero(fee_b);
            transfer::public_transfer(position, admin);
            transfer::public_transfer(pool, admin);
            test_scenario::return_shared(pools);
            transfer::public_transfer(gauge_cap, admin);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    /// Test collect_fullsail_distribution_gauger_fees method
    /// Verifies that:
    /// 1. Gauge fees are collected correctly with valid gauge cap
    /// 2. Gauge fee accumulators are reset after collection
    /// 3. CollectGaugeFeeEvent is emitted with correct amounts
    fun test_collect_fullsail_distribution_gauger_fees_and_protocol_fee() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            gauge_cap::gauge_cap::init_test(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::new(scenario.ctx());
        };
        
        // Add fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = test_scenario::take_from_sender<config::AdminCap>(&scenario);
            let mut global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            config::add_role(&admin_cap, &mut global_config, admin, 2);
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };
        
        scenario.next_tx(admin);
        {
            let global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            let clock = clock::create_for_testing(scenario.ctx());
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::gauge_cap::CreateCap>();
            let mut stats = scenario.take_shared<stats::Stats>();
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();

            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951,
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            
            // Create gauge cap
            let gauge_cap = gauge_cap::gauge_cap::create_gauge_cap(
                &create_gauge_cap,
                sui::object::id(&pool), // gauge_id
                sui::object::id(&pool),
                scenario.ctx()
            );

            // Initialize fullsail distribution gauge
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);

            // Create a position
            let mut position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                100, // tick_lower
                200, // tick_upper
                scenario.ctx()
            );
            
            // Add liquidity to the position
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                &mut position,
                90<<64, // delta_liquidity
                &clock
            );
            
            // Get balances from receipt
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

            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                90<<64,  // liquidity
                integer_mate::i32::from(100),  // tick_lower
                integer_mate::i32::from(200),  // tick_upper
                &clock
            );

            let (balance_a, balance_b, receipt) = pool::flash_swap<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                false,  // a2b
                true,  // by_amount_in
                100000000, 
                18584142135623730951 + 10000000,
                &mut stats,
                &price_provider,
                &clock
            );

            let (balance_a2, balance_b2, receipt2) = pool::flash_swap<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                true,  // a2b
                true,  // by_amount_in
                100000000, 
                18584142135623730951 - 10000000,
                &mut stats,
                &price_provider,
                &clock
            );

            let gauger_id = pool::get_fullsail_distribution_gauger_id<TestCoinB, TestCoinA>(&pool);
            assert!(gauger_id == gauge_cap::gauge_cap::get_gauge_id(&gauge_cap), 11);

            let (gauger_fee_a, gauger_fee_b) = pool::pool_fee_a_b(&pool::fullsail_distribution_gauger_fee<TestCoinB, TestCoinA>(&pool));
            assert!(gauger_fee_a == 80000, 12);
            assert!(gauger_fee_b == 80000, 13);
           
            // Collect gauge fees
            let (fee_a, fee_b) = pool::collect_fullsail_distribution_gauger_fees<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap
            );
            
            // Verify fees were collected
            assert!(sui::balance::value(&fee_a) == 80000, 21);
            assert!(sui::balance::value(&fee_b) == 80000, 22);

            let (protocol_fee_a, protocol_fee_b) = pool::protocol_fee(&pool);
            assert!(protocol_fee_a == 20000, 23);
            assert!(protocol_fee_b == 20000, 24);

            let (protocol_collect_fee_a, protocol_collect_fee_b) = pool::collect_protocol_fee<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                scenario.ctx()
            );

            assert!(sui::balance::value(&protocol_collect_fee_a) == 20000, 25);
            assert!(sui::balance::value(&protocol_collect_fee_b) == 20000, 26);
            
            // Cleanup
            pool::destroy_flash_swap_receipt<TestCoinB, TestCoinA>(receipt);
            sui::coin::from_balance(balance_a, scenario.ctx()).burn_for_testing();
            sui::coin::from_balance(balance_b, scenario.ctx()).burn_for_testing();
            pool::destroy_flash_swap_receipt<TestCoinB, TestCoinA>(receipt2);
            sui::balance::destroy_zero(balance_a2);
            sui::coin::from_balance(balance_b2, scenario.ctx()).burn_for_testing();
            sui::coin::from_balance(fee_a, scenario.ctx()).burn_for_testing();
            sui::coin::from_balance(fee_b, scenario.ctx()).burn_for_testing();
            sui::coin::from_balance(protocol_collect_fee_a, scenario.ctx()).burn_for_testing();
            sui::coin::from_balance(protocol_collect_fee_b, scenario.ctx()).burn_for_testing();
            transfer::public_transfer(position, admin);
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(gauge_cap, admin);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }
}
