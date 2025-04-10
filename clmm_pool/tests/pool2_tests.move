
    // TODO
    // #[test]
    // fun test_flash_swap_internal_basic() {
    //     let admin = @0x1;
    //     let mut scenario = test_scenario::begin(admin);
        
    //     // Initialize factory and config
    //     {
    //         factory::test_init(scenario.ctx());
    //         config::test_init(scenario.ctx());
    //         stats::init_test(scenario.ctx());
    //         price_provider::new(scenario.ctx());
    //     };
        
    //     // Add fee tier
    //     scenario.next_tx(admin);
    //     {
    //         let admin_cap = scenario.take_from_sender<config::AdminCap>();
    //         let mut global_config = scenario.take_shared<config::GlobalConfig>();
    //         config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
    //         test_scenario::return_shared(global_config);
    //         transfer::public_transfer(admin_cap, admin);
    //     };
        
    //     scenario.next_tx(admin);
    //     {
    //         let mut pools = scenario.take_shared<Pools>();
    //         let global_config = scenario.take_shared<config::GlobalConfig>();
    //         let mut stats = scenario.take_shared<stats::Stats>();
    //         let price_provider = scenario.take_shared<price_provider::PriceProvider>();
    //         let clock = clock::create_for_testing(scenario.ctx());
            
    //         // Create a new pool with current_sqrt_price = 1.0025 (corresponds to tick = 25)
    //         let mut pool = pool::new<TestCoinB, TestCoinA>(
    //             1, // tick_spacing
    //             (79228162514264337593543950336 >> 32) + 250000000000000u128, // current_sqrt_price (1.0025)
    //             1000, // fee_rate
    //             std::string::utf8(b""), // url
    //             0, // pool_index
    //             @0x2, // feed_id_coin_a
    //             @0x3, // feed_id_coin_b
    //             true, // auto_calculation_volumes
    //             &clock,
    //             scenario.ctx()
    //         );

    //         // Create a new position with tick_lower = 0 and tick_upper = 50
    //         let mut position = pool::open_position<TestCoinB, TestCoinA>(
    //             &global_config,
    //             &mut pool,
    //             0,  // tick_lower
    //             50,  // tick_upper
    //             scenario.ctx()
    //         );

    //         // Add liquidity to the position
    //         let receipt = pool::add_liquidity_internal_test<TestCoinB, TestCoinA>(
    //             &mut pool,
    //             &mut position,
    //             true,  // is_fix_amount
    //             1000000000000000000,  // liquidity_delta (1e18 in <<64 scale)
    //             100000,   // amount_in
    //             true,  // is_fix_amount_a
    //             clock::timestamp_ms(&clock)
    //         );

    //         // Verify the receipt
    //         let (amount_a, amount_b) = pool::add_liquidity_pay_amount<TestCoinB, TestCoinA>(&receipt);
    //         assert!(amount_a == 100000, 1);
    //         assert!(amount_b > 0, 2);

    //         pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);

    //         // Perform flash swap
    //         let (balance_a, balance_b, swap_receipt) = pool::flash_swap_internal_test<TestCoinB, TestCoinA>(
    //             &mut pool,
    //             &global_config,
    //             sui::object::id_from_address(@0x0), // partner_id
    //             0, // ref_fee_rate
    //             true, // a2b - swap A->B
    //             true, // by_amount_in
    //             50, // amount (reduced from 500)
    //             tick_math::min_sqrt_price(), // sqrt_price_limit (changed to min price)
    //             &mut stats,
    //             &price_provider,
    //             &clock
    //         );

    //         // Verify swap receipt
    //         let (fee_amount, ref_fee_amount, protocol_fee_amount, gauge_fee_amount) = pool::fees_amount(&swap_receipt);
    //         assert!(fee_amount > 0, 3);
    //         assert!(ref_fee_amount > 0, 4);
    //         assert!(protocol_fee_amount > 0, 5);
    //         assert!(gauge_fee_amount > 0, 6);

    //         // Clean up
    //         pool::destroy_flash_swap_receipt<TestCoinB, TestCoinA>(swap_receipt);
            
    //         // Return objects to scenario
    //         sui::balance::destroy_zero(balance_a);
    //         sui::balance::destroy_zero(balance_b);
    //         transfer::public_transfer(pool, admin);
    //         transfer::public_transfer(position, admin);
    //         test_scenario::return_shared(pools);
    //         test_scenario::return_shared(global_config);
    //         test_scenario::return_shared(stats);
    //         test_scenario::return_shared(price_provider);
    //         clock::destroy_for_testing(clock);
    //     };
        
    //     test_scenario::end(scenario);
    // }

    // TODO
    // #[test]
    // fun test_flash_swap_internal_borrow_b() {
    //     let admin = @0x1;
    //     let mut scenario = test_scenario::begin(admin);
        
    //     // Initialize factory and config
    //     {
    //         factory::test_init(scenario.ctx());
    //         config::test_init(scenario.ctx());
    //         stats::init_test(scenario.ctx());
    //         price_provider::new(scenario.ctx());
    //     };
        
    //     // Add fee tier
    //     scenario.next_tx(admin);
    //     {
    //         let admin_cap = scenario.take_from_sender<config::AdminCap>();
    //         let mut global_config = scenario.take_shared<config::GlobalConfig>();
    //         config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
    //         test_scenario::return_shared(global_config);
    //         transfer::public_transfer(admin_cap, admin);
    //     };
        
    //     scenario.next_tx(admin);
    //     {
    //         let mut pools = scenario.take_shared<Pools>();
    //         let global_config = scenario.take_shared<config::GlobalConfig>();
    //         let mut stats = scenario.take_shared<stats::Stats>();
    //         let price_provider = scenario.take_shared<price_provider::PriceProvider>();
    //         let clock = clock::create_for_testing(scenario.ctx());
            
    //         // Create a new pool with current_sqrt_price = 1.0 (changed from 1.0025)
    //         let mut pool = pool::new<TestCoinB, TestCoinA>(
    //             1, // tick_spacing
    //             79228162514264337593543950336 >> 32, // current_sqrt_price (1.0)
    //             1000, // fee_rate
    //             std::string::utf8(b""), // url
    //             0, // pool_index
    //             @0x2, // feed_id_coin_a
    //             @0x3, // feed_id_coin_b
    //             true, // auto_calculation_volumes
    //             &clock,
    //             scenario.ctx()
    //         );

    //         // Create a new position with tick_lower = -50 and tick_upper = 50 (changed range)
    //         let mut position = pool::open_position<TestCoinB, TestCoinA>(
    //             &global_config,
    //             &mut pool,
    //             4294967246,  // tick_lower (-50)
    //             50,  // tick_upper
    //             scenario.ctx()
    //         );

    //         // Add liquidity to the position
    //         let receipt = pool::add_liquidity_internal_test<TestCoinB, TestCoinA>(
    //             &mut pool,
    //             &mut position,
    //             true,  // is_fix_amount
    //             1000000000000000000,  // liquidity_delta (1e18 in <<64 scale)
    //             100000000,   // amount_in (increased from 10000000)
    //             true,  // is_fix_amount_a
    //             clock::timestamp_ms(&clock)
    //         );

    //         // Verify the receipt
    //         let (amount_a, amount_b) = pool::add_liquidity_pay_amount<TestCoinB, TestCoinA>(&receipt);
    //         assert!(amount_a == 100000000, 1);
    //         assert!(amount_b > 0, 2);

    //         pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);

    //         // Perform flash swap (borrow coin B)
    //         let (balance_a, balance_b, swap_receipt) = pool::flash_swap_internal_test<TestCoinB, TestCoinA>(
    //             &mut pool,
    //             &global_config,
    //             sui::object::id_from_address(@0x0), // partner_id
    //             0, // ref_fee_rate
    //             false, // a2b (borrow coin B)
    //             true, // by_amount_in
    //             10000, // amount (increased from 1000)
    //             tick_math::max_sqrt_price(), // sqrt_price_limit (using max price)
    //             &mut stats,
    //             &price_provider,
    //             &clock
    //         );

    //         // Verify swap receipt
    //         let (fee_amount, ref_fee_amount, protocol_fee_amount, gauge_fee_amount) = pool::fees_amount(&swap_receipt);
    //         assert!(fee_amount > 0, 3);
    //         assert!(ref_fee_amount > 0, 4);
    //         assert!(protocol_fee_amount > 0, 5);
    //         assert!(gauge_fee_amount > 0, 6);

    //         // Clean up
    //         pool::destroy_flash_swap_receipt<TestCoinB, TestCoinA>(swap_receipt);
            
    //         // Return objects to scenario
    //         sui::balance::destroy_zero(balance_a);
    //         sui::balance::destroy_zero(balance_b);
    //         transfer::public_transfer(pool, admin);
    //         transfer::public_transfer(position, admin);
    //         test_scenario::return_shared(pools);
    //         test_scenario::return_shared(global_config);
    //         test_scenario::return_shared(stats);
    //         test_scenario::return_shared(price_provider);
    //         clock::destroy_for_testing(clock);
    //     };
        
    //     test_scenario::end(scenario);
    // }
    // TODO
    // #[test]
    // fun test_flash_swap_internal_with_partner() {
    //     let admin = @0x1;
    //     let mut scenario = test_scenario::begin(admin);
        
    //     // Initialize factory and config
    //     {
    //         factory::test_init(scenario.ctx());
    //         config::test_init(scenario.ctx());
    //         stats::init_test(scenario.ctx());
    //         price_provider::new(scenario.ctx());
    //     };
        
    //     // Add fee tier
    //     scenario.next_tx(admin);
    //     {
    //         let admin_cap = scenario.take_from_sender<config::AdminCap>();
    //         let mut global_config = scenario.take_shared<config::GlobalConfig>();
    //         config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
    //         test_scenario::return_shared(global_config);
    //         transfer::public_transfer(admin_cap, admin);
    //     };
        
    //     scenario.next_tx(admin);
    //     {
    //         let mut pools = scenario.take_shared<Pools>();
    //         let global_config = scenario.take_shared<config::GlobalConfig>();
    //         let mut stats = scenario.take_shared<stats::Stats>();
    //         let price_provider = scenario.take_shared<price_provider::PriceProvider>();
    //         let clock = clock::create_for_testing(scenario.ctx());
            
    //         // Create a new pool with current_sqrt_price = 1.0025 (corresponds to tick = 25)
    //         let mut pool = pool::new<TestCoinB, TestCoinA>(
    //             1, // tick_spacing
    //             (79228162514264337593543950336 >> 32) + 250000000000000u128, // current_sqrt_price (1.0025)
    //             1000, // fee_rate
    //             std::string::utf8(b""), // url
    //             0, // pool_index
    //             @0x2, // feed_id_coin_a
    //             @0x3, // feed_id_coin_b
    //             true, // auto_calculation_volumes
    //             &clock,
    //             scenario.ctx()
    //         );

    //         // Create a new position with tick_lower = 0 and tick_upper = 50
    //         let mut position = pool::open_position<TestCoinB, TestCoinA>(
    //             &global_config,
    //             &mut pool,
    //             0,  // tick_lower
    //             50,  // tick_upper
    //             scenario.ctx()
    //         );

    //         // Add liquidity to the position
    //         let receipt = pool::add_liquidity_internal_test<TestCoinB, TestCoinA>(
    //             &mut pool,
    //             &mut position,
    //             true,  // is_fix_amount
    //             1000,  // liquidity_delta
    //             100,   // amount_in
    //             true,  // is_fix_amount_a
    //             clock::timestamp_ms(&clock)
    //         );

    //         // Verify the receipt
    //         let (amount_a, amount_b) = pool::add_liquidity_pay_amount<TestCoinB, TestCoinA>(&receipt);
    //         assert!(amount_a == 100, 1);
    //         assert!(amount_b == 0, 2);

    //         pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);

    //         // Test flash swap with partner fee
    //         let (balance_a, balance_b, swap_receipt) = pool::flash_swap_internal_test<TestCoinB, TestCoinA>(
    //             &mut pool,
    //             &global_config,
    //             sui::object::id_from_address(@0x4), // partner_id
    //             100, // ref_fee_rate (1%)
    //             true, // a2b
    //             true, // by_amount_in
    //             50, // amount
    //             tick_math::min_sqrt_price(), // sqrt_price_limit
    //             &mut stats,
    //             &price_provider,
    //             &clock
    //         );

    //         // Verify swap receipt
    //         let (fee_amount, ref_fee_amount, protocol_fee_amount, gauge_fee_amount) = pool::fees_amount(&swap_receipt);
    //         assert!(fee_amount > 0, 3);
    //         assert!(ref_fee_amount > 0, 4);
    //         assert!(protocol_fee_amount > 0, 5);
    //         assert!(gauge_fee_amount > 0, 6);

    //         // Clean up
    //         pool::destroy_flash_swap_receipt<TestCoinB, TestCoinA>(swap_receipt);
            
    //         // Return objects to scenario
    //         sui::balance::destroy_zero(balance_a);
    //         sui::balance::destroy_zero(balance_b);
    //         transfer::public_transfer(pool, admin);
    //         transfer::public_transfer(position, admin);
    //         test_scenario::return_shared(pools);
    //         test_scenario::return_shared(global_config);
    //         test_scenario::return_shared(stats);
    //         test_scenario::return_shared(price_provider);
    //         clock::destroy_for_testing(clock);
    //     };
        
    //     test_scenario::end(scenario);
    // }

    // TODO
    // #[test]
    // #[expected_failure(abort_code = 3)]
    // fun test_flash_swap_internal_zero_amount() {
    //     let admin = @0x1;
    //     let mut scenario = test_scenario::begin(admin);
        
    //     // Initialize factory and config
    //     {
    //         factory::test_init(scenario.ctx());
    //         config::test_init(scenario.ctx());
    //         stats::init_test(scenario.ctx());
    //         price_provider::new(scenario.ctx());
    //     };
        
    //     // Add fee tier
    //     scenario.next_tx(admin);
    //     {
    //         let admin_cap = scenario.take_from_sender<config::AdminCap>();
    //         let mut global_config = scenario.take_shared<config::GlobalConfig>();
    //         config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
    //         test_scenario::return_shared(global_config);
    //         transfer::public_transfer(admin_cap, admin);
    //     };
        
    //     scenario.next_tx(admin);
    //     {
    //         let mut pools = scenario.take_shared<Pools>();
    //         let global_config = scenario.take_shared<config::GlobalConfig>();
    //         let mut stats = scenario.take_shared<stats::Stats>();
    //         let price_provider = scenario.take_shared<price_provider::PriceProvider>();
    //         let clock = clock::create_for_testing(scenario.ctx());
            
    //         // Create a new pool with current_sqrt_price = 1.0025 (corresponds to tick = 25)
    //         let mut pool = pool::new<TestCoinB, TestCoinA>(
    //             1, // tick_spacing
    //             (79228162514264337593543950336 >> 32) + 250000000000000u128, // current_sqrt_price (1.0025)
    //             1000, // fee_rate
    //             std::string::utf8(b""), // url
    //             0, // pool_index
    //             @0x2, // feed_id_coin_a
    //             @0x3, // feed_id_coin_b
    //             true, // auto_calculation_volumes
    //             &clock,
    //             scenario.ctx()
    //         );

    //         // Create a new position with tick_lower = 0 and tick_upper = 50
    //         let mut position = pool::open_position<TestCoinB, TestCoinA>(
    //             &global_config,
    //             &mut pool,
    //             0,  // tick_lower
    //             50,  // tick_upper
    //             scenario.ctx()
    //         );

    //         // Add liquidity to the position
    //         let receipt = pool::add_liquidity_internal_test<TestCoinB, TestCoinA>(
    //             &mut pool,
    //             &mut position,
    //             true,  // is_fix_amount
    //             1000,  // liquidity_delta
    //             100,   // amount_in
    //             true,  // is_fix_amount_a
    //             clock::timestamp_ms(&clock)
    //         );

    //         // Test flash swap with zero amount (should fail)
    //         let (balance_a, balance_b, swap_receipt) = pool::flash_swap_internal_test<TestCoinB, TestCoinA>(
    //             &mut pool,
    //             &global_config,
    //             sui::object::id_from_address(@0x0), // partner_id
    //             0, // ref_fee_rate
    //             true, // a2b
    //             true, // by_amount_in
    //             0, // amount
    //             tick_math::min_sqrt_price(), // sqrt_price_limit
    //             &mut stats,
    //             &price_provider,
    //             &clock
    //         );
            
    //         // Clean up
    //         pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
    //         sui::balance::destroy_zero(balance_a);
    //         sui::balance::destroy_zero(balance_b);
    //         pool::destroy_flash_swap_receipt<TestCoinB, TestCoinA>(swap_receipt);
            
    //         // Return objects to scenario
    //         transfer::public_transfer(pool, admin);
    //         transfer::public_transfer(position, admin);
    //         test_scenario::return_shared(pools);
    //         test_scenario::return_shared(global_config);
    //         test_scenario::return_shared(stats);
    //         test_scenario::return_shared(price_provider);
    //         clock::destroy_for_testing(clock);
    //     };
        
    //     test_scenario::end(scenario);
    // }
