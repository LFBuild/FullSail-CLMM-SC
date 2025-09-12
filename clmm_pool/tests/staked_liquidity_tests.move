module clmm_pool::staked_liquidity_tests {
    #[allow(unused_const)]
    const COPYRIGHT_NOTICE: vector<u8> = b"© 2025 Metabyte Labs, Inc.  All Rights Reserved.";
    #[allow(unused_const)]
    const PATENT_NOTICE: vector<u8> = b"Patent pending - U.S. Patent Application No. 63/861,982";

    use sui::test_scenario;
    use sui::clock;
    use sui::coin;
    use integer_mate::i32;
    use clmm_pool::rewarder;
    use clmm_pool::pool;
    use clmm_pool::factory::{Self as factory};
    use clmm_pool::config::{Self as config};
    use clmm_pool::stats;
    use gauge_cap::gauge_cap;
    use clmm_pool::tick_math;
    use price_provider::price_provider;
    use clmm_pool::position;
    use sui::test_utils;
    use clmm_pool::acl;

    #[test_only]
    public struct TestCoinA has drop, store {}
    #[test_only]
    public struct TestCoinB has drop, store {}

    #[test]
    fun test_stake_in_fullsail_distribution_overlapping_positions_cross_by_swap() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::init_test(scenario.ctx());
            gauge_cap::init_test(scenario.ctx());
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
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::CreateCap>();
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951, // current_tick_index = 148
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
            let gauge_cap = gauge_cap::create_gauge_cap(
                &create_gauge_cap,
                sui::object::id(&pool),
                sui::object::id(&pool),
                scenario.ctx()
            );

            // Initialize fullsail distribution gauge
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);

            transfer::public_share_object(pool);
            transfer::public_transfer(gauge_cap, user);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };
        
        scenario.next_tx(user);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let mut pool = scenario.take_shared<pool::Pool<TestCoinB, TestCoinA>>();
            let gauge_cap = scenario.take_from_sender<gauge_cap::GaugeCap>();

            // base position to not get overflow errors
            let tick_lower_0 = tick_math::min_tick();
            let tick_upper_0 = tick_math::max_tick();
            let liquidity_0 = 1_000_000_000;

            let position0 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                i32::as_u32(tick_lower_0),
                i32::as_u32(tick_upper_0),
                liquidity_0,
                &clock
            );

            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                &position0,
                &clock
            );

            // Create two positions with overlapping ticks
            let tick_lower_1 = 100;
            let tick_upper_1 = 200;
            let tick_lower_2 = 200;
            let tick_upper_2 = 300;
            let liquidity_1 = 200000;
            let liquidity_2 = 100000;

            let position1 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                tick_lower_1,
                tick_upper_1,
                liquidity_1,
                &clock
            );

            let position2 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                tick_lower_2,
                tick_upper_2,
                liquidity_2,
                &clock
            );

            // Stake the second position
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                &position2,
                &clock
            );

            assert!(pool.liquidity() == liquidity_0 + liquidity_1, 1);
            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0, 2);

            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            let mut stats = scenario.take_shared<stats::Stats>();

            // Swap from B to A to increase price and move into position 2
            perform_swap<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                &mut stats,
                &price_provider,
                false,  // a2b
                true,  // by_amount_in
                100_000_000, // amount
                tick_math::get_sqrt_price_at_tick(i32::from(210)), // sqrt_price_limit
                &clock
            );

            // After swap, current tick should be in position 2 range
            let current_tick_index = pool::current_tick_index(&pool);
            assert!(i32::gte(current_tick_index, i32::from(tick_lower_2)), 4);
            assert!(i32::lt(current_tick_index, i32::from(tick_upper_2)), 5);

            // Staked liquidity should now be liquidity_2
            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0 + liquidity_2, 6);

            // Pool liquidity should be from position2
            assert!(pool.liquidity() == liquidity_0 + liquidity_2, 7);

            // Swap from A to B to decrease price back and move it to the position 1
            perform_swap<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                &mut stats,
                &price_provider,
                true,  // a2b
                true,  // by_amount_in
                100_000_000, // amount
                tick_math::get_sqrt_price_at_tick(i32::from(135)), // sqrt_price_limit
                &clock
            );

            // After swap, current tick should be in position 1 range
            let current_tick_index = pool::current_tick_index(&pool);
            assert!(i32::gte(current_tick_index, i32::from(tick_lower_1)), 8);
            assert!(i32::lt(current_tick_index, i32::from(tick_upper_1)), 9);

            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0, 10);
            assert!(pool.liquidity() == liquidity_0 + liquidity_1, 11);

            perform_swap<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                &mut stats,
                &price_provider,
                true,  // a2b
                true,  // by_amount_in
                100_000_000, // amount
                tick_math::get_sqrt_price_at_tick(i32::neg_from(100)), // sqrt_price_limit
                &clock
            );

            // After swap current tick should be below position 1 range
            let current_tick_index = pool::current_tick_index(&pool);
            assert!(i32::lt(current_tick_index, i32::from(tick_lower_1)), 12);

            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0, 13);
            assert!(pool.liquidity() == liquidity_0, 14);

            perform_swap<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                &mut stats,
                &price_provider,
                false,  // a2b
                true,  // by_amount_in
                100_000_000, // amount
                tick_math::get_sqrt_price_at_tick(i32::from(500)), // sqrt_price_limit
                &clock
            );

            let current_tick_index = pool::current_tick_index(&pool);
            assert!(i32::gt(current_tick_index, i32::from(tick_upper_2)), 14);

            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0, 15);
            assert!(pool.liquidity() == liquidity_0, 16);

            // Return objects to scenario
            transfer::public_transfer(position0, user);
            transfer::public_transfer(position1, user);
            transfer::public_transfer(position2, user);
            transfer::public_transfer(gauge_cap, user);
            test_scenario::return_shared(pool);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(vault);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_stake_liquidity_across_multiple_positions_exact_ticks() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::init_test(scenario.ctx());
            gauge_cap::init_test(scenario.ctx());
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
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::CreateCap>();
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951, // current_tick_index = 148
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
            let gauge_cap = gauge_cap::create_gauge_cap(
                &create_gauge_cap,
                sui::object::id(&pool),
                sui::object::id(&pool),
                scenario.ctx()
            );

            // Initialize fullsail distribution gauge
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);

            transfer::public_share_object(pool);
            transfer::public_transfer(gauge_cap, user);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(user);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let mut pool = scenario.take_shared<pool::Pool<TestCoinB, TestCoinA>>();
            let gauge_cap = scenario.take_from_sender<gauge_cap::GaugeCap>();

            // base position to not get overflow errors
            let tick_lower_0 = tick_math::min_tick();
            let tick_upper_0 = tick_math::max_tick();
            let liquidity_0 = 1_000_000_000;

            let position0 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                i32::as_u32(tick_lower_0),
                i32::as_u32(tick_upper_0),
                liquidity_0,
                &clock
            );

            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                &position0,
                &clock
            );

            // Create two positions with overlapping ticks
            let tick_lower_1 = 100;
            let tick_upper_1 = 200;
            let tick_lower_2 = 200;
            let tick_upper_2 = 300;
            let liquidity_1 = 200000;
            let liquidity_2 = 100000;

            let position1 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                tick_lower_1,
                tick_upper_1,
                liquidity_1,
                &clock
            );

            let position2 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                tick_lower_2,
                tick_upper_2,
                liquidity_2,
                &clock
            );

            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                &position2,
                &clock
            );

            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            let mut stats = scenario.take_shared<stats::Stats>();

            // 1. Swap to tick_lower_1
            perform_swap<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                &mut stats,
                &price_provider,
                true,  // a2b
                true,  // by_amount_in
                100_000_000, // amount
                tick_math::get_sqrt_price_at_tick(i32::from(tick_lower_1)) + 1, // sqrt_price_limit
                &clock
            );
            assert!(pool.current_tick_index() == i32::from(tick_lower_1), 1);
            assert!(pool.liquidity() == liquidity_0 + liquidity_1, 1);
            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0, 2);

            // 2. Swap to tick_upper_1
            perform_swap<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                &mut stats,
                &price_provider,
                false,  // a2b
                true,  // by_amount_in
                200_000_000, // amount
                tick_math::get_sqrt_price_at_tick(i32::from(tick_upper_1)), // sqrt_price_limit
                &clock
            );

            assert!(pool.current_tick_index() == i32::from(tick_upper_1), 2);
            assert!(pool.liquidity() == liquidity_0 + liquidity_2, 3);
            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0 + liquidity_2, 4);

            // 3. Swap to tick_upper_2
            perform_swap<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                &mut stats,
                &price_provider,
                false,  // a2b
                true,  // by_amount_in
                100_000_000, // amount
                tick_math::get_sqrt_price_at_tick(i32::from(tick_upper_2)), // sqrt_price_limit
                &clock
            );

            assert!(pool.current_tick_index() == i32::from(tick_upper_2), 3);
            assert!(pool.liquidity() == liquidity_0, 5);
            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0, 6);

            // Return objects to scenario
            transfer::public_transfer(position0, user);
            transfer::public_transfer(position1, user);
            transfer::public_transfer(position2, user);
            transfer::public_transfer(gauge_cap, user);
            test_scenario::return_shared(pool);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(vault);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_stake_in_fullsail_distribution_overlapping_positions_cross_by_swap_stake_pos1() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // Initialize factory and config
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::init_test(scenario.ctx());
            gauge_cap::init_test(scenario.ctx());
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
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::CreateCap>();
            // Create a new pool
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951, // current_tick_index = 148
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
            let gauge_cap = gauge_cap::create_gauge_cap(
                &create_gauge_cap,
                sui::object::id(&pool),
                sui::object::id(&pool),
                scenario.ctx()
            );

            // Initialize fullsail distribution gauge
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);

            transfer::public_share_object(pool);
            transfer::public_transfer(gauge_cap, user);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(user);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let mut pool = scenario.take_shared<pool::Pool<TestCoinB, TestCoinA>>();
            let gauge_cap = scenario.take_from_sender<gauge_cap::GaugeCap>();

            // base position to not get overflow errors
            let tick_lower_0 = tick_math::min_tick();
            let tick_upper_0 = tick_math::max_tick();
            let liquidity_0 = 1_000_000_000;

            let position0 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                i32::as_u32(tick_lower_0),
                i32::as_u32(tick_upper_0),
                liquidity_0,
                &clock
            );

            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                &position0,
                &clock
            );

            // Create two positions with overlapping ticks
            let tick_lower_1 = 100;
            let tick_upper_1 = 200;
            let tick_lower_2 = 200;
            let tick_upper_2 = 300;
            let liquidity_1 = 100000;
            let liquidity_2 = 200000;

            let position1 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                tick_lower_1,
                tick_upper_1,
                liquidity_1,
                &clock
            );

            let position2 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                tick_lower_2,
                tick_upper_2,
                liquidity_2,
                &clock
            );

            // Stake the first position
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(
                &mut pool,
                &gauge_cap,
                &position1,
                &clock
            );

            assert!(pool.liquidity() == liquidity_0 + liquidity_1, 1);
            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0 + liquidity_1, 2);

            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            let mut stats = scenario.take_shared<stats::Stats>();

            // Swap from B to A to increase price and move into position 2
            perform_swap<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                &mut stats,
                &price_provider,
                false,  // a2b
                true,  // by_amount_in
                100_000_000, // amount
                tick_math::get_sqrt_price_at_tick(i32::from(210)), // sqrt_price_limit
                &clock
            );

            // After swap, current tick should be in position 2 range
            let current_tick_index = pool::current_tick_index(&pool);
            assert!(i32::gte(current_tick_index, i32::from(tick_lower_2)), 4);
            assert!(i32::lt(current_tick_index, i32::from(tick_upper_2)), 5);

            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0, 6);
            assert!(pool.liquidity() == liquidity_0 + liquidity_2, 7);

            // Swap from A to B to decrease price back and move it to the position 1
            perform_swap<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                &mut stats,
                &price_provider,
                true,  // a2b
                true,  // by_amount_in
                100_000_000, // amount
                tick_math::get_sqrt_price_at_tick(i32::from(135)), // sqrt_price_limit
                &clock
            );

            // After swap, current tick should be in position 1 range
            let current_tick_index = pool::current_tick_index(&pool);
            assert!(i32::gte(current_tick_index, i32::from(tick_lower_1)), 8);
            assert!(i32::lt(current_tick_index, i32::from(tick_upper_1)), 9);

            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0 + liquidity_1, 10);
            assert!(pool.liquidity() == liquidity_0 + liquidity_1, 11);

            // Return objects to scenario
            transfer::public_transfer(position0, user);
            transfer::public_transfer(position1, user);
            transfer::public_transfer(position2, user);
            transfer::public_transfer(gauge_cap, user);
            test_scenario::return_shared(pool);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(vault);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_stake_liquidity_with_both_positions_staked() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // System initialization
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::init_test(scenario.ctx());
            gauge_cap::init_test(scenario.ctx());
            rewarder::test_init(scenario.ctx());
        };

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
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::CreateCap>();
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, // tick_spacing
                18584142135623730951, // current_tick_index = 148
                1000, // fee_rate
                std::string::utf8(b""), // url
                0, // pool_index
                @0x2, // feed_id_coin_a
                @0x3, // feed_id_coin_b
                true, // auto_calculation_volumes
                &clock,
                scenario.ctx()
            );
            let gauge_cap = gauge_cap::create_gauge_cap(&create_gauge_cap, sui::object::id(&pool), sui::object::id(&pool), scenario.ctx());
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);
            transfer::public_share_object(pool);
            transfer::public_transfer(gauge_cap, user);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(user);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let mut pool = scenario.take_shared<pool::Pool<TestCoinB, TestCoinA>>();
            let gauge_cap = scenario.take_from_sender<gauge_cap::GaugeCap>();

            let tick_lower_0 = tick_math::min_tick();
            let tick_upper_0 = tick_math::max_tick();
            let liquidity_0 = 1_000_000_000;
            let position0 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, i32::as_u32(tick_lower_0), i32::as_u32(tick_upper_0), liquidity_0, &clock);
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position0, &clock);

            let tick_lower_1 = 100;
            let tick_upper_1 = 200;
            let tick_lower_2 = 200;
            let tick_upper_2 = 300;
            let liquidity_1 = 200000;
            let liquidity_2 = 100000;

            let position1 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, tick_lower_1, tick_upper_1, liquidity_1, &clock);
            let position2 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, tick_lower_2, tick_upper_2, liquidity_2, &clock);

            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position2, &clock);

            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            let mut stats = scenario.take_shared<stats::Stats>();

            // Before any swaps, check the shared tick state
            let shared_tick = pool::borrow_tick<TestCoinB, TestCoinA>(&pool, i32::from(tick_lower_2));
            assert!(clmm_pool::tick::liquidity_gross(shared_tick) == liquidity_1 + liquidity_2, 0);
            assert!(clmm_pool::tick::fullsail_distribution_staked_liquidity_net(shared_tick).eq(integer_mate::i128::from(liquidity_2)), 0);


            perform_swap<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                &mut stats,
                &price_provider,
                false,
                true,
                100_000_000,
                tick_math::get_sqrt_price_at_tick(i32::from(500)),
                &clock
            );
            
            // After swapping past all positions, stake position1
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position1, &clock);

            // Check the shared tick state again. Staking position1 should update the staked_liquidity_net
            let shared_tick = pool::borrow_tick<TestCoinB, TestCoinA>(&pool, i32::from(tick_lower_2));
            assert!(clmm_pool::tick::liquidity_gross(shared_tick) == liquidity_1 + liquidity_2, 0);
            assert!(clmm_pool::tick::fullsail_distribution_staked_liquidity_net(shared_tick).eq(
                integer_mate::i128::sub(integer_mate::i128::from(liquidity_2), integer_mate::i128::from(liquidity_1))
            ), 0);
            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0, 1);
            
            perform_swap<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                &mut stats,
                &price_provider,
                true,
                true,
                100_000_000,
                tick_math::get_sqrt_price_at_tick(i32::from(250)),
                &clock
            );

            let current_tick_index = pool::current_tick_index(&pool);
            assert!(i32::gte(current_tick_index, i32::from(tick_lower_2)), 2);
            assert!(i32::lt(current_tick_index, i32::from(tick_upper_2)), 3);

            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0 + liquidity_2, 2);
            assert!(pool.liquidity() == liquidity_0 + liquidity_2, 3);

            // move price into position 1 range
            perform_swap<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                &mut stats,
                &price_provider,
                true,
                true,
                100_000_000,
                tick_math::get_sqrt_price_at_tick(i32::from(150)),
                &clock
            );

            let current_tick_index = pool::current_tick_index(&pool);
            assert!(i32::gte(current_tick_index, i32::from(tick_lower_1)), 4);
            assert!(i32::lt(current_tick_index, i32::from(tick_upper_1)), 5);

            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0 + liquidity_1, 6);
            assert!(pool.liquidity() == liquidity_0 + liquidity_1, 7);

            // unstake position 1 and check that staked liquidity has decreased
            pool::unstake_from_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position1, &clock);
            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0, 8);
            assert!(pool.liquidity() == liquidity_0 + liquidity_1, 9);

            // unstake position 2 and check that staked liqudity is still the same
            pool::unstake_from_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position2, &clock);
            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0, 10);
            assert!(pool.liquidity() == liquidity_0 + liquidity_1, 11);

            // perform a swap to move the price into position 2 range and check that staked liquidity still hasn't decreased
            perform_swap<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                &mut stats,
                &price_provider,
                false,
                true,
                100_000_000,
                tick_math::get_sqrt_price_at_tick(i32::from(250)),
                &clock
            );

            let current_tick_index = pool::current_tick_index(&pool);
            assert!(i32::gte(current_tick_index, i32::from(tick_lower_2)), 12);
            assert!(i32::lt(current_tick_index, i32::from(tick_upper_2)), 13);

            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0, 14);
            assert!(pool.liquidity() == liquidity_0 + liquidity_2, 15);

            // Return objects to scenario
            transfer::public_transfer(position0, user);
            transfer::public_transfer(position1, user);
            transfer::public_transfer(position2, user);
            transfer::public_transfer(gauge_cap, user);
            test_scenario::return_shared(pool);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(vault);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = clmm_pool::pool::EUnstakePositionNotStaked)]
    fun test_unstake_from_fullsail_distribution_not_staked_fails() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // System initialization
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::init_test(scenario.ctx());
            gauge_cap::init_test(scenario.ctx());
            rewarder::test_init(scenario.ctx());
        };

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
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::CreateCap>();
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, 18584142135623730951, 1000, std::string::utf8(b""), 0, @0x2, @0x3, true, &clock, scenario.ctx()
            );
            let gauge_cap = gauge_cap::create_gauge_cap(&create_gauge_cap, sui::object::id(&pool), sui::object::id(&pool), scenario.ctx());
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);
            transfer::public_share_object(pool);
            transfer::public_transfer(gauge_cap, user);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(user);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let mut pool = scenario.take_shared<pool::Pool<TestCoinB, TestCoinA>>();
            let gauge_cap = scenario.take_from_sender<gauge_cap::GaugeCap>();

            let position = open_position_and_add_liquidity<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                100,
                200,
                100000,
                &clock
            );

            // Attempt to unstake a position that was not staked
            pool::unstake_from_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position, &clock);

            // Return objects to scenario
            transfer::public_transfer(position, user);
            transfer::public_transfer(gauge_cap, user);
            test_scenario::return_shared(pool);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(vault);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = clmm_pool::pool::EUnstakePositionNotStaked)]
    fun test_double_unstake_from_fullsail_distribution_fails() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // System initialization
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::init_test(scenario.ctx());
            gauge_cap::init_test(scenario.ctx());
            rewarder::test_init(scenario.ctx());
        };

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
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::CreateCap>();
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, 18584142135623730951, 1000, std::string::utf8(b""), 0, @0x2, @0x3, true, &clock, scenario.ctx()
            );
            let gauge_cap = gauge_cap::create_gauge_cap(&create_gauge_cap, sui::object::id(&pool), sui::object::id(&pool), scenario.ctx());
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);
            transfer::public_share_object(pool);
            transfer::public_transfer(gauge_cap, user);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(user);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let mut pool = scenario.take_shared<pool::Pool<TestCoinB, TestCoinA>>();
            let gauge_cap = scenario.take_from_sender<gauge_cap::GaugeCap>();

            let position = open_position_and_add_liquidity<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                100,
                200,
                100000,
                &clock
            );
            
            // Stake the position
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position, &clock);
            
            // Unstake the position
            pool::unstake_from_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position, &clock);

            // Attempt to unstake again, should fail
            pool::unstake_from_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position, &clock);

            // Return objects to scenario
            transfer::public_transfer(position, user);
            transfer::public_transfer(gauge_cap, user);
            test_scenario::return_shared(pool);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(vault);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = clmm_pool::pool::EStakePositionAlreadyStaked)]
    fun test_double_stake_from_fullsail_distribution_fails() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // System initialization
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::init_test(scenario.ctx());
            gauge_cap::init_test(scenario.ctx());
            rewarder::test_init(scenario.ctx());
        };

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
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::CreateCap>();
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, 18584142135623730951, 1000, std::string::utf8(b""), 0, @0x2, @0x3, true, &clock, scenario.ctx()
            );
            let gauge_cap = gauge_cap::create_gauge_cap(&create_gauge_cap, sui::object::id(&pool), sui::object::id(&pool), scenario.ctx());
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);
            transfer::public_share_object(pool);
            transfer::public_transfer(gauge_cap, user);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(user);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let mut pool = scenario.take_shared<pool::Pool<TestCoinB, TestCoinA>>();
            let gauge_cap = scenario.take_from_sender<gauge_cap::GaugeCap>();

            let position = open_position_and_add_liquidity<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                100,
                200,
                100000,
                &clock
            );
            
            // Stake the position
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position, &clock);
            
            // Attempt to stake again, should fail
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position, &clock);

            // Return objects to scenario
            transfer::public_transfer(position, user);
            transfer::public_transfer(gauge_cap, user);
            test_scenario::return_shared(pool);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(vault);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = clmm_pool::pool::EPositionIsStaked)]
    fun test_remove_liquidity_from_staked_position_fails() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // System initialization
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::init_test(scenario.ctx());
            gauge_cap::init_test(scenario.ctx());
            rewarder::test_init(scenario.ctx());
        };

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
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::CreateCap>();
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, 18584142135623730951, 1000, std::string::utf8(b""), 0, @0x2, @0x3, true, &clock, scenario.ctx()
            );
            let gauge_cap = gauge_cap::create_gauge_cap(&create_gauge_cap, sui::object::id(&pool), sui::object::id(&pool), scenario.ctx());
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);
            transfer::public_share_object(pool);
            transfer::public_transfer(gauge_cap, user);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(user);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let mut pool = scenario.take_shared<pool::Pool<TestCoinB, TestCoinA>>();
            let gauge_cap = scenario.take_from_sender<gauge_cap::GaugeCap>();

            let mut position = open_position_and_add_liquidity<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                100,
                200,
                100000,
                &clock
            );
            
            // Stake the position
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position, &clock);
            
            // Attempt to remove liquidity from a staked position, should fail
            let (balance_a, balance_b) = pool::remove_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut vault,
                &mut pool,
                &mut position,
                50000,
                &clock
            );

            // Return objects to scenario
            test_utils::destroy(balance_a);
            test_utils::destroy(balance_b);
            transfer::public_transfer(position, user);
            transfer::public_transfer(gauge_cap, user);
            test_scenario::return_shared(pool);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(vault);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = clmm_pool::pool::EPositionIsStaked)]
    fun test_add_liquidity_to_staked_position_fails() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // System initialization
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::init_test(scenario.ctx());
            gauge_cap::init_test(scenario.ctx());
            rewarder::test_init(scenario.ctx());
        };

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
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::CreateCap>();
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, 18584142135623730951, 1000, std::string::utf8(b""), 0, @0x2, @0x3, true, &clock, scenario.ctx()
            );
            let gauge_cap = gauge_cap::create_gauge_cap(&create_gauge_cap, sui::object::id(&pool), sui::object::id(&pool), scenario.ctx());
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);
            transfer::public_share_object(pool);
            transfer::public_transfer(gauge_cap, user);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(user);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let mut pool = scenario.take_shared<pool::Pool<TestCoinB, TestCoinA>>();
            let gauge_cap = scenario.take_from_sender<gauge_cap::GaugeCap>();

            let mut position = open_position_and_add_liquidity<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                100,
                200,
                100000,
                &clock
            );
            
            // Stake the position
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position, &clock);
            
            // Attempt to add liquidity to the staked position, should fail
            let receipt = pool::add_liquidity<TestCoinB, TestCoinA>(
                &global_config,
                &mut vault,
                &mut pool,
                &mut position,
                50000,
                &clock
            );
            pool::destroy_receipt(receipt);

            // Return objects to scenario
            transfer::public_transfer(position, user);
            transfer::public_transfer(gauge_cap, user);
            test_scenario::return_shared(pool);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(vault);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = clmm_pool::pool::EZeroLiquidity)]
    fun test_stake_zero_liquidity_position_fails() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // System initialization
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::init_test(scenario.ctx());
            gauge_cap::init_test(scenario.ctx());
            rewarder::test_init(scenario.ctx());
        };

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
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::CreateCap>();
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, 18584142135623730951, 1000, std::string::utf8(b""), 0, @0x2, @0x3, true, &clock, scenario.ctx()
            );
            let gauge_cap = gauge_cap::create_gauge_cap(&create_gauge_cap, sui::object::id(&pool), sui::object::id(&pool), scenario.ctx());
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);
            transfer::public_share_object(pool);
            transfer::public_transfer(gauge_cap, user);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(user);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut pool = scenario.take_shared<pool::Pool<TestCoinB, TestCoinA>>();
            let gauge_cap = scenario.take_from_sender<gauge_cap::GaugeCap>();

            let position = pool::open_position<TestCoinB, TestCoinA>(
                &global_config,
                &mut pool,
                100,
                200,
                scenario.ctx()
            );

            // Attempt to stake a position with zero liquidity, should fail
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position, &clock);

            // Return objects to scenario
            transfer::public_transfer(gauge_cap, user);
            test_utils::destroy(position);
            test_scenario::return_shared(pool);
            test_scenario::return_shared(global_config);
            let vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            test_scenario::return_shared(vault);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    fun open_position_and_add_liquidity<CoinTypeA: store, CoinTypeB: store>(
        scenario: &mut test_scenario::Scenario,
        global_config: &config::GlobalConfig,
        vault: &mut rewarder::RewarderGlobalVault,
        pool: &mut pool::Pool<CoinTypeA, CoinTypeB>,
        tick_lower: u32,
        tick_upper: u32,
        liquidity: u128,
        clock: &clock::Clock,
    ): position::Position {
        let mut position = pool::open_position<CoinTypeA, CoinTypeB>(
            global_config,
            pool,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        let receipt = pool::add_liquidity<CoinTypeA, CoinTypeB>(
            global_config,
            vault,
            pool,
            &mut position,
            liquidity,
            clock
        );

        let (pay_amount_a, pay_amount_b) = pool::add_liquidity_pay_amount(&receipt);
        let coin_a = coin::mint_for_testing<CoinTypeA>(pay_amount_a, scenario.ctx());
        let coin_b = coin::mint_for_testing<CoinTypeB>(pay_amount_b, scenario.ctx());
        let balance_a = coin_a.into_balance();
        let balance_b = coin_b.into_balance();
        pool::repay_add_liquidity<CoinTypeA, CoinTypeB>(
            global_config,
            pool,
            balance_a,
            balance_b,
            receipt
        );
        position
    }

    fun perform_swap<CoinTypeA: store, CoinTypeB: store>(
        scenario: &mut test_scenario::Scenario,
        global_config: &config::GlobalConfig,
        vault: &mut rewarder::RewarderGlobalVault,
        pool: &mut pool::Pool<CoinTypeA, CoinTypeB>,
        stats: &mut stats::Stats,
        price_provider: &price_provider::PriceProvider,
        a2b: bool,
        by_amount_in: bool,
        amount: u64,
        sqrt_price_limit: u128,
        clock: &clock::Clock,
    ) {
        let (out_balance_a, out_balance_b, receipt) = pool::flash_swap<CoinTypeA, CoinTypeB>(
            global_config,
            vault,
            pool,
            a2b,
            by_amount_in,
            amount,
            sqrt_price_limit,
            stats,
            price_provider,
            clock
        );

        let pay_amount = pool::swap_pay_amount(&receipt);
        
        if (a2b) { // A -> B
            let in_coin_a = coin::mint_for_testing<CoinTypeA>(pay_amount, scenario.ctx());
             pool::repay_flash_swap(
                global_config,
                pool,
                coin::into_balance(in_coin_a),
                coin::into_balance(coin::zero<CoinTypeB>(scenario.ctx())),
                receipt
            );
            sui::balance::destroy_zero(out_balance_a);
            coin::from_balance(out_balance_b, scenario.ctx()).burn_for_testing();
        } else { // B -> A
             let in_coin_b = coin::mint_for_testing<CoinTypeB>(pay_amount, scenario.ctx());
             pool::repay_flash_swap(
                global_config,
                pool,
                coin::into_balance(coin::zero<CoinTypeA>(scenario.ctx())),
                coin::into_balance(in_coin_b),
                receipt
            );
            coin::from_balance(out_balance_a, scenario.ctx()).burn_for_testing();
            sui::balance::destroy_zero(out_balance_b);
        };
    }

    #[test]
    fun test_calc_current_liquidity_matches_pool_liquidity() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // System initialization
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::init_test(scenario.ctx());
            gauge_cap::init_test(scenario.ctx());
            rewarder::test_init(scenario.ctx());
        };

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
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::CreateCap>();
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, 18584142135623730951, 1000, std::string::utf8(b""), 0, @0x2, @0x3, true, &clock, scenario.ctx()
            );
            let gauge_cap = gauge_cap::create_gauge_cap(&create_gauge_cap, sui::object::id(&pool), sui::object::id(&pool), scenario.ctx());
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);
            transfer::public_share_object(pool);
            transfer::public_transfer(gauge_cap, user);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(user);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let mut pool = scenario.take_shared<pool::Pool<TestCoinB, TestCoinA>>();
            let gauge_cap = scenario.take_from_sender<gauge_cap::GaugeCap>();

            // Position 0: Full range, staked
            let tick_lower_0 = tick_math::min_tick();
            let tick_upper_0 = tick_math::max_tick();
            let liquidity_0 = 1_000_000_000;
            let position0 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, i32::as_u32(tick_lower_0), i32::as_u32(tick_upper_0), liquidity_0, &clock);
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position0, &clock);
            
            // Position 1: In-range, staked
            let tick_lower_1 = 100;
            let tick_upper_1 = 200;
            let liquidity_1 = 200_000;
            let position1 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, tick_lower_1, tick_upper_1, liquidity_1, &clock);
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position1, &clock);

            // Position 2: In-range, not staked
            let tick_lower_2 = 120;
            let tick_upper_2 = 180;
            let liquidity_2 = 300_000;
            let position2 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, tick_lower_2, tick_upper_2, liquidity_2, &clock);

            // Position 3: Out-of-range (above), staked
            let tick_lower_3 = 300;
            let tick_upper_3 = 400;
            let liquidity_3 = 400_000;
            let position3 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, tick_lower_3, tick_upper_3, liquidity_3, &clock);
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position3, &clock);

            // Position 4: Out-of-range (below), not staked
            let tick_lower_4 = 0;
            let tick_upper_4 = 50;
            let liquidity_4 = 500_000;
            let position4 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, tick_lower_4, tick_upper_4, liquidity_4, &clock);

            // Check initial state
            let expected_liquidity = liquidity_0 + liquidity_1 + liquidity_2;
            let expected_staked_liquidity = liquidity_0 + liquidity_1;
            assert!(pool.liquidity() == expected_liquidity, 1);
            assert!(pool.get_fullsail_distribution_staked_liquidity() == expected_staked_liquidity, 2);

            // Calculate liquidity using the tick method
            let tick_manager = pool::tick_manager<TestCoinB, TestCoinA>(&pool);
            let (calculated_liquidity, calculated_staked_liquidity) = clmm_pool::tick::calc_current_liquidity(tick_manager, pool.current_tick_index());

            // Compare with pool values
            assert!(calculated_liquidity == pool.liquidity(), 3);
            assert!(calculated_staked_liquidity == pool.get_fullsail_distribution_staked_liquidity(), 4);

            // Return objects to scenario
            transfer::public_transfer(position0, user);
            transfer::public_transfer(position1, user);
            transfer::public_transfer(position2, user);
            transfer::public_transfer(position3, user);
            transfer::public_transfer(position4, user);
            transfer::public_transfer(gauge_cap, user);
            test_scenario::return_shared(pool);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(vault);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_calc_current_liquidity_at_tick_boundary() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // System initialization
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::init_test(scenario.ctx());
            gauge_cap::init_test(scenario.ctx());
            rewarder::test_init(scenario.ctx());
        };

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
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::CreateCap>();
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, 
                tick_math::get_sqrt_price_at_tick(i32::from(100)), // Price is exactly at tick 100
                1000, 
                std::string::utf8(b""), 
                0, 
                @0x2, 
                @0x3, 
                true, 
                &clock, 
                scenario.ctx()
            );
            let gauge_cap = gauge_cap::create_gauge_cap(&create_gauge_cap, sui::object::id(&pool), sui::object::id(&pool), scenario.ctx());
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);
            transfer::public_share_object(pool);
            transfer::public_transfer(gauge_cap, user);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(user);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let mut pool = scenario.take_shared<pool::Pool<TestCoinB, TestCoinA>>();
            let gauge_cap = scenario.take_from_sender<gauge_cap::GaugeCap>();

            // Position 0: Full range, staked
            let tick_lower_0 = tick_math::min_tick();
            let tick_upper_0 = tick_math::max_tick();
            let liquidity_0 = 1_000_000_000;
            let position0 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, i32::as_u32(tick_lower_0), i32::as_u32(tick_upper_0), liquidity_0, &clock);
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position0, &clock);
            
            // Position 1: In-range, staked
            let tick_lower_1 = 100;
            let tick_upper_1 = 200;
            let liquidity_1 = 200_000;
            let position1 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, tick_lower_1, tick_upper_1, liquidity_1, &clock);
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position1, &clock);

            // Position 2: Out of range, not staked
            let tick_lower_2 = 120;
            let tick_upper_2 = 180;
            let liquidity_2 = 300_000;
            let position2 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, tick_lower_2, tick_upper_2, liquidity_2, &clock);
            
            let tick_manager = pool::tick_manager<TestCoinB, TestCoinA>(&pool);
            let (calculated_liquidity, calculated_staked_liquidity) = clmm_pool::tick::calc_current_liquidity(tick_manager, pool.current_tick_index());

            // Since price is at tick_lower_1, the liquidity should include position 0
            let expected_liquidity = liquidity_0 + liquidity_1;
            let expected_staked_liquidity = liquidity_0 + liquidity_1;
            
            assert!(pool.liquidity() == expected_liquidity, 1);
            assert!(pool.get_fullsail_distribution_staked_liquidity() == expected_staked_liquidity, 2);
            assert!(calculated_liquidity == pool.liquidity(), 3);
            assert!(calculated_staked_liquidity == pool.get_fullsail_distribution_staked_liquidity(), 4);

            // Return objects to scenario
            transfer::public_transfer(position0, user);
            transfer::public_transfer(position1, user);
            transfer::public_transfer(position2, user);
            transfer::public_transfer(gauge_cap, user);
            test_scenario::return_shared(pool);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(vault);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_calc_current_liquidity_with_single_full_range_position() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // System initialization
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::init_test(scenario.ctx());
            gauge_cap::init_test(scenario.ctx());
            rewarder::test_init(scenario.ctx());
        };

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
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::CreateCap>();
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, 18584142135623730951, 1000, std::string::utf8(b""), 0, @0x2, @0x3, true, &clock, scenario.ctx()
            );
            let gauge_cap = gauge_cap::create_gauge_cap(&create_gauge_cap, sui::object::id(&pool), sui::object::id(&pool), scenario.ctx());
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);
            transfer::public_share_object(pool);
            transfer::public_transfer(gauge_cap, user);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(user);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let mut pool = scenario.take_shared<pool::Pool<TestCoinB, TestCoinA>>();
            let gauge_cap = scenario.take_from_sender<gauge_cap::GaugeCap>();

            // Position 0: Full range, staked
            let tick_lower_0 = tick_math::min_tick();
            let tick_upper_0 = tick_math::max_tick();
            let liquidity_0 = 1_000_000_000;
            let position0 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, i32::as_u32(tick_lower_0), i32::as_u32(tick_upper_0), liquidity_0, &clock);
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position0, &clock);
            
            // Check initial state
            assert!(pool.liquidity() == liquidity_0, 1);
            assert!(pool.get_fullsail_distribution_staked_liquidity() == liquidity_0, 2);

            // Calculate liquidity using the tick method
            let tick_manager = pool::tick_manager<TestCoinB, TestCoinA>(&pool);
            let (calculated_liquidity, calculated_staked_liquidity) = clmm_pool::tick::calc_current_liquidity(tick_manager, pool.current_tick_index());

            // Compare with pool values
            assert!(calculated_liquidity == pool.liquidity(), 3);
            assert!(calculated_staked_liquidity == pool.get_fullsail_distribution_staked_liquidity(), 4);

            // Return objects to scenario
            transfer::public_transfer(position0, user);
            transfer::public_transfer(gauge_cap, user);
            test_scenario::return_shared(pool);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(vault);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_calc_current_liquidity_all_positions_out_of_range() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // System initialization
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::init_test(scenario.ctx());
            gauge_cap::init_test(scenario.ctx());
            rewarder::test_init(scenario.ctx());
        };

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
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::CreateCap>();
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, 18584142135623730951, 1000, std::string::utf8(b""), 0, @0x2, @0x3, true, &clock, scenario.ctx()
            );
            let gauge_cap = gauge_cap::create_gauge_cap(&create_gauge_cap, sui::object::id(&pool), sui::object::id(&pool), scenario.ctx());
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);
            transfer::public_share_object(pool);
            transfer::public_transfer(gauge_cap, user);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(user);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let mut pool = scenario.take_shared<pool::Pool<TestCoinB, TestCoinA>>();
            let gauge_cap = scenario.take_from_sender<gauge_cap::GaugeCap>();

            // Position 1: Out-of-range (below), staked
            let position1 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, 0, 50, 200_000, &clock);
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position1, &clock);

            // Position 2: Out-of-range (below), not staked
            let position2 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, 60, 100, 300_000, &clock);

            // Position 3: Out-of-range (above), staked
            let position3 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, 200, 250, 400_000, &clock);
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position3, &clock);

            // Position 4: Out-of-range (above), not staked
            let position4 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, 300, 400, 500_000, &clock);

            // Check initial state: all liquidity should be out of range
            assert!(pool.liquidity() == 0, 1);
            assert!(pool.get_fullsail_distribution_staked_liquidity() == 0, 2);

            // Calculate liquidity using the tick method
            let tick_manager = pool::tick_manager<TestCoinB, TestCoinA>(&pool);
            let (calculated_liquidity, calculated_staked_liquidity) = clmm_pool::tick::calc_current_liquidity(tick_manager, pool.current_tick_index());

            // Compare with pool values
            assert!(calculated_liquidity == pool.liquidity(), 3);
            assert!(calculated_staked_liquidity == pool.get_fullsail_distribution_staked_liquidity(), 4);

            // Return objects to scenario
            transfer::public_transfer(position1, user);
            transfer::public_transfer(position2, user);
            transfer::public_transfer(position3, user);
            transfer::public_transfer(position4, user);
            transfer::public_transfer(gauge_cap, user);
            test_scenario::return_shared(pool);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(vault);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_calc_current_liquidity_swap_into_out_of_range() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // System initialization
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::init_test(scenario.ctx());
            gauge_cap::init_test(scenario.ctx());
            rewarder::test_init(scenario.ctx());
        };

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
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::CreateCap>();
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, 18584142135623730951, 1000, std::string::utf8(b""), 0, @0x2, @0x3, true, &clock, scenario.ctx()
            );
            let gauge_cap = gauge_cap::create_gauge_cap(&create_gauge_cap, sui::object::id(&pool), sui::object::id(&pool), scenario.ctx());
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);
            transfer::public_share_object(pool);
            transfer::public_transfer(gauge_cap, user);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(user);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let mut pool = scenario.take_shared<pool::Pool<TestCoinB, TestCoinA>>();
            let gauge_cap = scenario.take_from_sender<gauge_cap::GaugeCap>();

            // All positions are initially out of range (current_tick_index = 148)
            let position1 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, 200, 250, 200_000, &clock);
            let position2 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, 300, 400, 500_000, &clock);
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position1, &clock);
            
            assert!(pool.liquidity() == 0, 1);
            assert!(pool.get_fullsail_distribution_staked_liquidity() == 0, 2);
            
            let price_provider = scenario.take_shared<price_provider::PriceProvider>();
            let mut stats = scenario.take_shared<stats::Stats>();

            // Swap to move price into position1's range
            perform_swap<TestCoinB, TestCoinA>(
                &mut scenario,
                &global_config,
                &mut vault,
                &mut pool,
                &mut stats,
                &price_provider,
                false,
                true,
                100_000_000,
                tick_math::get_sqrt_price_at_tick(i32::from(210)),
                &clock
            );

            // Now position1 is in range
            assert!(pool.liquidity() == 200_000, 3);
            assert!(pool.get_fullsail_distribution_staked_liquidity() == 200_000, 4);

            let tick_manager = pool::tick_manager<TestCoinB, TestCoinA>(&pool);
            let (calculated_liquidity, calculated_staked_liquidity) = clmm_pool::tick::calc_current_liquidity(tick_manager, pool.current_tick_index());

            assert!(calculated_liquidity == pool.liquidity(), 5);
            assert!(calculated_staked_liquidity == pool.get_fullsail_distribution_staked_liquidity(), 6);
            
            // Return objects to scenario
            transfer::public_transfer(position1, user);
            transfer::public_transfer(position2, user);
            transfer::public_transfer(gauge_cap, user);
            test_scenario::return_shared(pool);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(vault);
            test_scenario::return_shared(stats);
            test_scenario::return_shared(price_provider);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_restore_staked_liquidity_no_change() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // System initialization
        {
            factory::test_init(scenario.ctx());
            config::test_init(scenario.ctx());
            stats::init_test(scenario.ctx());
            price_provider::init_test(scenario.ctx());
            gauge_cap::init_test(scenario.ctx());
            rewarder::test_init(scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 1, 1000, scenario.ctx());
            config::add_role(&admin_cap, &mut global_config, admin, acl::pool_manager_role());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };

        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let create_gauge_cap = scenario.take_from_sender<gauge_cap::CreateCap>();
            let mut pool = pool::new<TestCoinB, TestCoinA>(
                1, 18584142135623730951, 1000, std::string::utf8(b""), 0, @0x2, @0x3, true, &clock, scenario.ctx()
            );
            let gauge_cap = gauge_cap::create_gauge_cap(&create_gauge_cap, sui::object::id(&pool), sui::object::id(&pool), scenario.ctx());
            pool::init_fullsail_distribution_gauge<TestCoinB, TestCoinA>(&mut pool, &gauge_cap);
            transfer::public_share_object(pool);
            transfer::public_transfer(gauge_cap, user);
            transfer::public_transfer(create_gauge_cap, admin);
            test_scenario::return_shared(global_config);
            clock::destroy_for_testing(clock);
        };

        scenario.next_tx(user);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let clock = clock::create_for_testing(scenario.ctx());
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let mut pool = scenario.take_shared<pool::Pool<TestCoinB, TestCoinA>>();
            let gauge_cap = scenario.take_from_sender<gauge_cap::GaugeCap>();

            // Position 0: Full range, staked
            let tick_lower_0 = tick_math::min_tick();
            let tick_upper_0 = tick_math::max_tick();
            let liquidity_0 = 1_000_000_000;
            let position0 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, i32::as_u32(tick_lower_0), i32::as_u32(tick_upper_0), liquidity_0, &clock);
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position0, &clock);
            
            // Position 1: In-range, staked
            let tick_lower_1 = 100;
            let tick_upper_1 = 200;
            let liquidity_1 = 200_000;
            let position1 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, tick_lower_1, tick_upper_1, liquidity_1, &clock);
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position1, &clock);

            // Position 2: In-range, not staked
            let tick_lower_2 = 120;
            let tick_upper_2 = 180;
            let liquidity_2 = 300_000;
            let position2 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, tick_lower_2, tick_upper_2, liquidity_2, &clock);

            // Position 3: Out-of-range (above), staked
            let tick_lower_3 = 300;
            let tick_upper_3 = 400;
            let liquidity_3 = 400_000;
            let position3 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, tick_lower_3, tick_upper_3, liquidity_3, &clock);
            pool::stake_in_fullsail_distribution<TestCoinB, TestCoinA>(&mut pool, &gauge_cap, &position3, &clock);

            // Position 4: Out-of-range (below), not staked
            let tick_lower_4 = 0;
            let tick_upper_4 = 50;
            let liquidity_4 = 500_000;
            let position4 = open_position_and_add_liquidity<TestCoinB, TestCoinA>(&mut scenario, &global_config, &mut vault, &mut pool, tick_lower_4, tick_upper_4, liquidity_4, &clock);

            // Return objects to scenario
            transfer::public_transfer(position0, user);
            transfer::public_transfer(position1, user);
            transfer::public_transfer(position2, user);
            transfer::public_transfer(position3, user);
            transfer::public_transfer(position4, user);
            transfer::public_transfer(gauge_cap, user);
            test_scenario::return_shared(pool);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(vault);
            clock::destroy_for_testing(clock);
        };
        
        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut pool = scenario.take_shared<pool::Pool<TestCoinB, TestCoinA>>();
            let liquidity_before = pool.liquidity();
            let staked_liquidity_before = pool.get_fullsail_distribution_staked_liquidity();

            pool::restore_fullsail_distribution_staked_liquidity<TestCoinB, TestCoinA>(&mut pool, &global_config, scenario.ctx());

            let liquidity_after = pool.liquidity();
            let staked_liquidity_after = pool.get_fullsail_distribution_staked_liquidity();

            assert!(liquidity_before == liquidity_after, 1);
            assert!(staked_liquidity_before == staked_liquidity_after, 2);

            test_scenario::return_shared(pool);
            test_scenario::return_shared(global_config);
        };

        test_scenario::end(scenario);
    }
}
