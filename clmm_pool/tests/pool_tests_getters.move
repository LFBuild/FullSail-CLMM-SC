/// © 2025 Metabyte Labs, Inc.  All Rights Reserved.
/// U.S. Patent Application No. 63/861,982. The technology described herein is the subject of a pending U.S. patent application.
/// Full Sail has added a license to its Full Sail protocol code. You can view the terms of the license at [ULR](LICENSE/250825_Metabyte_Negotiated_Services_Agreement21634227_2_002.docx).

#[test_only]
module clmm_pool::pool_tests_getters {
    use sui::test_scenario;
    use sui::clock;
    use clmm_pool::pool;
    use clmm_pool::factory::{Self as factory};
    use clmm_pool::config::{Self as config};
    use clmm_pool::rewarder;

    #[test_only]
    public struct TestCoinA has drop {}
    #[test_only]
    public struct TestCoinB has drop {}

    #[test]
    /// Test step_swap_result getters
    /// Verifies that:
    /// 1. Getters for SwapStepResult return correct values
    fun test_step_swap_result_getters() {
        let admin = @0x1;
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
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
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
                &mut vault,
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

            // Verify there is one step
            assert!(pool::calculated_swap_result_steps_length(&result) == 1, 0);

            // Get step result
            let step_results = pool::calculate_swap_result_step_results(&result);
            let step_result = std::vector::borrow(step_results, 0);

            // Test getters
            let amount_in = pool::step_swap_result_amount_in(step_result);
            let amount_out = pool::step_swap_result_amount_out(step_result);
            let fee_amount = pool::step_swap_result_fee_amount(step_result);
            let current_sqrt_price = pool::step_swap_result_current_sqrt_price(step_result);
            let current_liquidity = pool::step_swap_result_current_liquidity(step_result);
            let remainder_amount = pool::step_swap_result_remainder_amount(step_result);
            let target_sqrt_price = pool::step_swap_result_target_sqrt_price(step_result);

            let (total_fee, _, _, _) = pool::calculated_swap_result_fees_amount(&result);

            // Assert values
            assert!(amount_in == pool::calculated_swap_result_amount_in(&result), 1);
            assert!(amount_out == pool::calculated_swap_result_amount_out(&result), 2);
            assert!(fee_amount == total_fee, 3);
            assert!(current_sqrt_price == pool::current_sqrt_price(&pool), 4);
            assert!(current_liquidity == pool::liquidity(&pool), 5);
            assert!(10 - amount_in - fee_amount == remainder_amount, 6);
            
            let sqrt_price_at_tick_0 = clmm_pool::tick_math::get_sqrt_price_at_tick(integer_mate::i32::from(0));
            assert!(target_sqrt_price == sqrt_price_at_tick_0, 7);

            pool::destroy_receipt<TestCoinB, TestCoinA>(receipt);
            
            // Return objects to scenario
            transfer::public_transfer(pool, admin);
            transfer::public_transfer(position, admin);
            test_scenario::return_shared(global_config);
            test_scenario::return_shared(vault);
            clock::destroy_for_testing(clock);
        };
        
        test_scenario::end(scenario);
    }
}
