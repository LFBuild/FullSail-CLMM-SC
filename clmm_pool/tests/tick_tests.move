#[test_only]
module clmm_pool::tick_tests {
    use sui::test_scenario::{Self, Scenario};
    use clmm_pool::tick::{Self, Tick};
    use clmm_pool::tick_math;
    use sui::tx_context;
    use std::vector;
    use integer_mate::i32;
    use integer_mate::i128;
    use move_stl::option_u64;
    use sui::transfer;

    #[test_only]
    public struct TickTestHelper has key,store {
        id: sui::object::UID,
        tick_manager: tick::TickManager,
    }

    #[test_only]
    public fun get_tick_manager(self: &mut TickTestHelper): &mut tick::TickManager {
        &mut self.tick_manager
    }

    #[test]
    fun test_increase_liquidity() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper =   TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(0);
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 0;
            let fee_growth_global_b = 0;
            let points_growth_global = 0;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 0;

            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Check that ticks were created
            let lower_tick = tick::try_borrow_tick(tick_manager, tick_lower);
            let upper_tick = tick::try_borrow_tick(tick_manager, tick_upper);
            assert!(std::option::is_some(&lower_tick), 2);
            assert!(std::option::is_some(&upper_tick), 3);

            // Check liquidity values
            let lower_tick_value = std::option::borrow(&lower_tick);
            let upper_tick_value = std::option::borrow(&upper_tick);
            assert!(tick::liquidity_gross(lower_tick_value) == liquidity, 4);
            assert!(tick::liquidity_gross(upper_tick_value) == liquidity, 5);

            transfer::public_transfer(helper, @0x1);
        };

        scenario.end();
    }

    #[test]
    fun test_decrease_liquidity_basic() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(0);
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 0;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 0;

            // First, increase liquidity
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Check that ticks were created
            let lower_tick = tick::try_borrow_tick(tick_manager, tick_lower);
            let upper_tick = tick::try_borrow_tick(tick_manager, tick_upper);
            assert!(std::option::is_some(&lower_tick), 2);
            assert!(std::option::is_some(&upper_tick), 3);

            // Check liquidity values
            let lower_tick_value = std::option::borrow(&lower_tick);
            let upper_tick_value = std::option::borrow(&upper_tick);
            assert!(tick::liquidity_gross(lower_tick_value) == liquidity, 4);
            assert!(tick::liquidity_gross(upper_tick_value) == liquidity, 5);

            // Decrease liquidity by half
            tick::decrease_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity / 2,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Check that ticks still exist
            let lower_tick = tick::try_borrow_tick(tick_manager, tick_lower);
            let upper_tick = tick::try_borrow_tick(tick_manager, tick_upper);
            assert!(std::option::is_some(&lower_tick), 6);
            assert!(std::option::is_some(&upper_tick), 7);

            // Check new liquidity values
            let lower_tick_value = std::option::borrow(&lower_tick);
            let upper_tick_value = std::option::borrow(&upper_tick);
            assert!(tick::liquidity_gross(lower_tick_value) == liquidity / 2, 8);
            assert!(tick::liquidity_gross(upper_tick_value) == liquidity / 2, 9);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_decrease_liquidity_full() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(0);
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 0;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 0;

            // First, increase liquidity
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Decrease all liquidity
            tick::decrease_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Check that ticks were removed
            let lower_tick = tick::try_borrow_tick(tick_manager, tick_lower);
            let upper_tick = tick::try_borrow_tick(tick_manager, tick_upper);
            assert!(std::option::is_none(&lower_tick), 10);
            assert!(std::option::is_none(&upper_tick), 11);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_decrease_liquidity_multiple_positions() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(0);
            let tick_lower = i32::neg_from(10);
            let tick_middle = i32::from(5);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 0;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 0;

            // Create two positions with a common tick
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_middle,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_middle,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Check that the middle tick has double liquidity
            let middle_tick = tick::try_borrow_tick(tick_manager, tick_middle);
            assert!(std::option::is_some(&middle_tick), 12);
            let middle_tick_value = std::option::borrow(&middle_tick);
            assert!(tick::liquidity_gross(middle_tick_value) == liquidity * 2, 13);

            // Decrease liquidity for the first position
            tick::decrease_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_middle,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Check that the lower tick was removed
            let lower_tick = tick::try_borrow_tick(tick_manager, tick_lower);
            assert!(std::option::is_none(&lower_tick), 14);

            // Check that the middle tick still exists and has the correct liquidity
            let middle_tick = tick::try_borrow_tick(tick_manager, tick_middle);
            assert!(std::option::is_some(&middle_tick), 15);
            let middle_tick_value = std::option::borrow(&middle_tick);
            assert!(tick::liquidity_gross(middle_tick_value) == liquidity, 16);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 1)]
    fun test_decrease_liquidity_too_much() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(0);
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 0;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 0;

            // First, increase liquidity
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Attempt to decrease liquidity more than available
            tick::decrease_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity * 2, // Attempting to decrease twice as much as available
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_cross_by_swap() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper =   TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(0);
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 0;
            let fee_growth_global_b = 0;
            let points_growth_global = 0;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 0;

            // First, increase liquidity
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Get the tick before crossing
            let tick = tick::try_borrow_tick(tick_manager, tick_lower);
            assert!(std::option::is_some(&tick), 2);
            let tick_value = std::option::borrow(&tick);
            let tick_liquidity_net = tick::liquidity_net(tick_value);
            let tick_staked_liquidity_net = tick::fullsail_distribution_staked_liquidity_net(tick_value);

            // Cross the tick
            let (new_liquidity, new_staked_liquidity) = tick::cross_by_swap(
                tick_manager,
                tick_lower,
                true, // is_a2b
                liquidity,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Check that liquidity changed
            // For is_a2b = true, we take the negative value of liquidity_net
            // In cross_by_swap we check the sign of liquidity_delta (which is equal to -liquidity_net)
            let expected_liquidity = if (integer_mate::i128::is_neg(tick_liquidity_net)) {
                // If liquidity_net is negative, then liquidity_delta is positive
                liquidity + integer_mate::i128::abs_u128(tick_liquidity_net)
            } else {
                // If liquidity_net is positive, then liquidity_delta is negative
                liquidity - integer_mate::i128::abs_u128(tick_liquidity_net)
            };

            // Similarly for staked_liquidity
            let expected_staked_liquidity = if (integer_mate::i128::is_neg(tick_staked_liquidity_net)) {
                liquidity + integer_mate::i128::abs_u128(tick_staked_liquidity_net)
            } else {
                liquidity - integer_mate::i128::abs_u128(tick_staked_liquidity_net)
            };

            assert!(new_liquidity == expected_liquidity, 8);
            assert!(new_staked_liquidity == expected_staked_liquidity, 9);

            transfer::public_transfer(helper, @0x1);
        };

        scenario.end();
    }

    #[test]
    fun test_get_fee_in_range() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper =   TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(0);
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let points_growth_global = 0;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 0;

            // Create ticks with initial values
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                1000, // fee_growth_global_a
                2000, // fee_growth_global_b
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the lower tick to update fee_growth_outside
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_lower,
                true,
                liquidity,
                liquidity,
                1000, // fee_growth_global_a
                2000, // fee_growth_global_b
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the upper tick with new fee_growth_global values
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_upper,
                false,
                liquidity,
                liquidity,
                2000, // fee_growth_global_a
                4000, // fee_growth_global_b
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the lower tick again to update fee_growth_outside
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_lower,
                true,
                liquidity,
                liquidity,
                3000, // fee_growth_global_a
                6000, // fee_growth_global_b
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Get ticks through try_borrow_tick
            let lower_tick = tick::try_borrow_tick(tick_manager, tick_lower);
            let upper_tick = tick::try_borrow_tick(tick_manager, tick_upper);

            // Get ticks through borrow_tick
            let lower_tick_ref = tick::borrow_tick(tick_manager, tick_lower);
            let upper_tick_ref = tick::borrow_tick(tick_manager, tick_upper);

            // Compare values obtained by different methods
            let lower_tick_value = std::option::borrow(&lower_tick);
            let upper_tick_value = std::option::borrow(&upper_tick);

            assert!(tick::liquidity_gross(lower_tick_value) == tick::liquidity_gross(lower_tick_ref), 12);
            assert!(tick::liquidity_gross(upper_tick_value) == tick::liquidity_gross(upper_tick_ref), 13);
            assert!(tick::liquidity_net(lower_tick_value) == tick::liquidity_net(lower_tick_ref), 14);
            assert!(tick::liquidity_net(upper_tick_value) == tick::liquidity_net(upper_tick_ref), 15);

            let (fee_growth_below_a, fee_growth_below_b) = tick::fee_growth_outside(lower_tick_value);
            let (fee_growth_above_a, fee_growth_above_b) = tick::fee_growth_outside(upper_tick_value);

            let (fee_growth_below_a_ref, fee_growth_below_b_ref) = tick::fee_growth_outside(lower_tick_ref);
            let (fee_growth_above_a_ref, fee_growth_above_b_ref) = tick::fee_growth_outside(upper_tick_ref);

            assert!(fee_growth_below_a == fee_growth_below_a_ref, 16);
            assert!(fee_growth_below_b == fee_growth_below_b_ref, 17);
            assert!(fee_growth_above_a == fee_growth_above_a_ref, 18);
            assert!(fee_growth_above_b == fee_growth_above_b_ref, 19);

            // Check fees in range with new fee_growth_global values
            let (fee_a, fee_b) = tick::get_fee_in_range(
                current_tick,
                3000, // fee_growth_global_a
                6000, // fee_growth_global_b
                lower_tick,
                upper_tick
            );

            let expected_fee_a = integer_mate::math_u128::wrapping_sub(
                integer_mate::math_u128::wrapping_sub(3000, fee_growth_below_a),
                fee_growth_above_a
            );
            let expected_fee_b = integer_mate::math_u128::wrapping_sub(
                integer_mate::math_u128::wrapping_sub(6000, fee_growth_below_b),
                fee_growth_above_b
            );

            assert!(fee_a == expected_fee_a, 10);
            assert!(fee_b == expected_fee_b, 11);

            transfer::public_transfer(helper, @0x1);
        };

        scenario.end();
    }

    #[test]
    fun test_get_fee_in_range_current_tick_between() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(0); // Current tick between lower and upper
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let points_growth_global = 0;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 0;

            // Create ticks with initial values
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                1000, // fee_growth_global_a
                2000, // fee_growth_global_b
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the lower tick to update fee_growth_outside
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_lower,
                true,
                liquidity,
                liquidity,
                1000, // fee_growth_global_a
                2000, // fee_growth_global_b
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the upper tick with new fee_growth_global values
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_upper,
                false,
                liquidity,
                liquidity,
                1000,
                2000,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Get ticks through try_borrow_tick
            let lower_tick = tick::try_borrow_tick(tick_manager, tick_lower);
            let upper_tick = tick::try_borrow_tick(tick_manager, tick_upper);

            // Check fees in range with new fee_growth_global values
            let (fee_a, fee_b) = tick::get_fee_in_range(
                current_tick, // Current tick between lower and upper
                3000, // fee_growth_global_a
                6000, // fee_growth_global_b
                lower_tick,
                upper_tick
            );

            // When the current tick is between the lower and upper:
            // fee_growth_below = fee_growth_outside_lower
            // fee_growth_above = fee_growth_outside_upper
            let lower_tick_value = std::option::borrow(&lower_tick);
            let upper_tick_value = std::option::borrow(&upper_tick);
            let (fee_growth_below_a, fee_growth_below_b) = tick::fee_growth_outside(lower_tick_value);
            let (fee_growth_above_a, fee_growth_above_b) = tick::fee_growth_outside(upper_tick_value);

            let expected_fee_a = integer_mate::math_u128::wrapping_sub(
                integer_mate::math_u128::wrapping_sub(3000, fee_growth_below_a),
                fee_growth_above_a
            );
            let expected_fee_b = integer_mate::math_u128::wrapping_sub(
                integer_mate::math_u128::wrapping_sub(6000, fee_growth_below_b),
                fee_growth_above_b
            );

            assert!(fee_a == expected_fee_a, 42);
            assert!(fee_b == expected_fee_b, 43);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_borrow_tick_for_swap() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper =   TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(0);
            let tick_lower = i32::neg_from(10);
            let tick_middle = i32::from(5);
            let tick_upper = i32::from(10);
            let tick_upper_plus = i32::from(15);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 0;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 0;

            // Create all ticks in the correct order
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_middle,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_middle,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_upper,
                tick_upper_plus,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Get the lower tick and its next tick
            let lower_tick = tick::borrow_tick(tick_manager, tick_lower);
            let lower_score = tick::first_score_for_swap(tick_manager, tick_lower, false);
            assert!(move_stl::option_u64::is_some(&lower_score), 20);
            let (_, next_score) = tick::borrow_tick_for_swap(
                tick_manager,
                move_stl::option_u64::borrow(&lower_score),
                false // is_prev
            );

            // Check that the next tick exists
            assert!(move_stl::option_u64::is_some(&next_score), 21);

            // Check values of the lower tick
            assert!(tick::liquidity_gross(lower_tick) == liquidity, 22);
            assert!(tick::liquidity_net(lower_tick) == integer_mate::i128::from(liquidity), 23);

            // Get the middle tick and its next tick
            let middle_tick = tick::borrow_tick(tick_manager, tick_middle);
            let middle_score = tick::first_score_for_swap(tick_manager, tick_middle, false);
            assert!(move_stl::option_u64::is_some(&middle_score), 24);
            let (_, next_score) = tick::borrow_tick_for_swap(
                tick_manager,
                move_stl::option_u64::borrow(&middle_score),
                false // is_prev
            );

            // Check that the next tick exists and it is the upper tick
            assert!(move_stl::option_u64::is_some(&next_score), 25);

            // Check values of the middle tick
            assert!(tick::liquidity_gross(middle_tick) == liquidity * 2, 26);
            assert!(tick::liquidity_net(middle_tick) == integer_mate::i128::from(0), 27);

            // Get the upper tick and its next tick
            let upper_tick = tick::borrow_tick(tick_manager, tick_upper);
            let upper_score = tick::first_score_for_swap(tick_manager, tick_upper, false);
            assert!(move_stl::option_u64::is_some(&upper_score), 28);
            let (_, next_score) = tick::borrow_tick_for_swap(
                tick_manager,
                move_stl::option_u64::borrow(&upper_score),
                false // is_prev
            );

            // TODO
            // Check that the next tick exists and it is tick_upper_plus
            // assert!(move_stl::option_u64::is_some(&next_score), 29);

            // Check values of the upper tick
            // assert!(tick::liquidity_gross(upper_tick) == liquidity * 2, 30);
            // assert!(tick::liquidity_net(upper_tick) == integer_mate::i128::neg_from(liquidity), 31);

            transfer::public_transfer(helper, @0x1);
        };

        scenario.end();
    }

    #[test]
    fun test_fetch_ticks_empty_start() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(0);
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 0;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 0;

            // Create ticks
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Get all ticks without specifying a starting index
            let ticks = tick::fetch_ticks(tick_manager, vector::empty<u32>(), 10);
            
            // Check that 2 ticks were obtained (lower and upper)
            assert!(vector::length(&ticks) == 2, 32);
            
            // Check that ticks are in the correct order
            let first_tick = vector::borrow(&ticks, 0);
            let second_tick = vector::borrow(&ticks, 1);
            assert!(tick::index(first_tick) == tick_lower, 33);
            assert!(tick::index(second_tick) == tick_upper, 34);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_fetch_ticks_with_start_index() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(0);
            let tick_lower = i32::neg_from(10);
            let tick_middle = i32::from(5);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 0;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 0;

            // Create three ticks
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_middle,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_middle,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Check that all ticks exist
            let lower_tick = tick::try_borrow_tick(tick_manager, tick_lower);
            let middle_tick = tick::try_borrow_tick(tick_manager, tick_middle);
            let upper_tick = tick::try_borrow_tick(tick_manager, tick_upper);
            assert!(std::option::is_some(&lower_tick), 35);
            assert!(std::option::is_some(&middle_tick), 36);
            assert!(std::option::is_some(&upper_tick), 37);

            // Get all ticks without specifying a starting index
            let all_ticks = tick::fetch_ticks(tick_manager, vector::empty<u32>(), 10);
            let all_ticks_length = vector::length(&all_ticks);
            assert!(all_ticks_length > 0, 38);

            // Check the order of ticks in the full sample
            let first_all_tick = vector::borrow(&all_ticks, 0);
            assert!(tick::index(first_all_tick) == tick_lower, 39);

            // Get ticks starting from the middle
            let mut start_indices = vector::empty<u32>();
            vector::push_back(&mut start_indices, i32::as_u32(tick_middle));
            let ticks = tick::fetch_ticks(tick_manager, start_indices, 10);
            
            // Check the number of ticks obtained
            let ticks_length = vector::length(&ticks);
            assert!(ticks_length > 0, 40);

            // Check the order of ticks
            let mut i = 0;
            while (i < ticks_length) {
                let current_tick = vector::borrow(&ticks, i);
                let current_index = tick::index(current_tick);
                // Check that ticks are in the correct order
                if (i > 0) {
                    let prev_tick = vector::borrow(&ticks, i - 1);
                    let prev_index = tick::index(prev_tick);
                    assert!(integer_mate::i32::lt(prev_index, current_index), 41);
                };
                i = i + 1;
            };

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_fetch_ticks_with_limit() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(0);
            let tick_lower = i32::neg_from(10);
            let tick_middle = i32::from(5);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 0;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 0;

            // Create three ticks
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_middle,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_middle,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Get only one tick
            let ticks = tick::fetch_ticks(tick_manager, vector::empty<u32>(), 1);
            
            // Check that only one tick was obtained
            assert!(vector::length(&ticks) == 1, 38);
            
            // Check that this is the lower tick
            let first_tick = vector::borrow(&ticks, 0);
            assert!(tick::index(first_tick) == tick_lower, 39);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_fetch_ticks_with_nonexistent_start() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(0);
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 0;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 0;

            // Create ticks
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Attempt to get ticks starting from a nonexistent index
            let mut start_indices = vector::empty<u32>();
            vector::push_back(&mut start_indices, 100); // Nonexistent index
            let ticks = tick::fetch_ticks(tick_manager, start_indices, 10);
            
            // Check that an empty vector was obtained
            assert!(vector::is_empty(&ticks), 40);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_get_fullsail_distribution_growth_in_range_current_tick_below() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::neg_from(20); // Current tick below the lower
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 0;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 1000;

            // Create ticks with initial values
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the lower tick to update fullsail_distribution_growth_outside
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_lower,
                true,
                liquidity,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the upper tick with new values
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_upper,
                false,
                liquidity,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global * 2
            );

            // Get ticks
            let lower_tick = tick::try_borrow_tick(tick_manager, tick_lower);
            let upper_tick = tick::try_borrow_tick(tick_manager, tick_upper);

            // Check FULLSAIL distribution in range
            let fullsail_growth = tick::get_fullsail_distribution_growth_in_range(
                current_tick,
                fullsail_distribution_growth_global * 3,
                lower_tick,
                upper_tick
            );

            // When the current tick is below the lower:
            // fullsail_growth_below = fullsail_growth_global - fullsail_growth_outside_lower
            // fullsail_growth_above = fullsail_growth_outside_upper
            let lower_tick_value = std::option::borrow(&lower_tick);
            let upper_tick_value = std::option::borrow(&upper_tick);
            let fullsail_growth_below = integer_mate::math_u128::wrapping_sub(
                fullsail_distribution_growth_global * 3,
                tick::fullsail_distribution_growth_outside(lower_tick_value)
            );
            let fullsail_growth_above = tick::fullsail_distribution_growth_outside(upper_tick_value);

            let expected_fullsail_growth = integer_mate::math_u128::wrapping_sub(
                integer_mate::math_u128::wrapping_sub(fullsail_distribution_growth_global * 3, fullsail_growth_below),
                fullsail_growth_above
            );

            assert!(fullsail_growth == expected_fullsail_growth, 44);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_get_fullsail_distribution_growth_in_range_current_tick_above() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(20); // Current tick above the upper
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 0;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 1000;

            // Create ticks with initial values
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the lower tick to update fullsail_distribution_growth_outside
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_lower,
                true,
                liquidity,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the upper tick with new values
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_upper,
                false,
                liquidity,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global * 2
            );

            // Get ticks
            let lower_tick = tick::try_borrow_tick(tick_manager, tick_lower);
            let upper_tick = tick::try_borrow_tick(tick_manager, tick_upper);

            // Check FULLSAIL distribution in range
            let fullsail_growth = tick::get_fullsail_distribution_growth_in_range(
                current_tick,
                fullsail_distribution_growth_global * 3,
                lower_tick,
                upper_tick
            );

            // When the current tick is above the upper:
            // fullsail_growth_below = fullsail_growth_outside_lower
            // fullsail_growth_above = fullsail_growth_global - fullsail_growth_outside_upper
            let lower_tick_value = std::option::borrow(&lower_tick);
            let upper_tick_value = std::option::borrow(&upper_tick);
            let fullsail_growth_below = tick::fullsail_distribution_growth_outside(lower_tick_value);
            let fullsail_growth_above = integer_mate::math_u128::wrapping_sub(
                fullsail_distribution_growth_global * 3,
                tick::fullsail_distribution_growth_outside(upper_tick_value)
            );

            let expected_fullsail_growth = integer_mate::math_u128::wrapping_sub(
                integer_mate::math_u128::wrapping_sub(fullsail_distribution_growth_global * 3, fullsail_growth_below),
                fullsail_growth_above
            );

            assert!(fullsail_growth == expected_fullsail_growth, 45);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_get_fullsail_distribution_growth_in_range_current_tick_between() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(0); // Current tick is between lower and upper
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 0;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 1000;

            // Create ticks with initial values
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the lower tick to update fullsail_distribution_growth_outside
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_lower,
                true,
                liquidity,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the upper tick with new values
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_upper,
                false,
                liquidity,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global * 2
            );

            // Get ticks
            let lower_tick = tick::try_borrow_tick(tick_manager, tick_lower);
            let upper_tick = tick::try_borrow_tick(tick_manager, tick_upper);

            // Check FULLSAIL distribution in range
            let fullsail_growth = tick::get_fullsail_distribution_growth_in_range(
                current_tick,
                fullsail_distribution_growth_global * 3,
                lower_tick,
                upper_tick
            );

            // When the current tick is between lower and upper:
            // fullsail_growth_below = fullsail_growth_outside_lower
            // fullsail_growth_above = fullsail_growth_outside_upper
            let lower_tick_value = std::option::borrow(&lower_tick);
            let upper_tick_value = std::option::borrow(&upper_tick);
            let fullsail_growth_below = tick::fullsail_distribution_growth_outside(lower_tick_value);
            let fullsail_growth_above = tick::fullsail_distribution_growth_outside(upper_tick_value);

            let expected_fullsail_growth = integer_mate::math_u128::wrapping_sub(
                integer_mate::math_u128::wrapping_sub(fullsail_distribution_growth_global * 3, fullsail_growth_below),
                fullsail_growth_above
            );

            assert!(fullsail_growth == expected_fullsail_growth, 46);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_get_points_in_range_current_tick_below() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::neg_from(20); // Current tick is below the lower
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 1000;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 1000;

            // Create ticks with initial values
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the lower tick to update points_growth_outside
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_lower,
                true,
                liquidity,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the upper tick with new values
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_upper,
                false,
                liquidity,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global * 2,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Get ticks
            let lower_tick = tick::try_borrow_tick(tick_manager, tick_lower);
            let upper_tick = tick::try_borrow_tick(tick_manager, tick_upper);

            // Check points in range
            let points_growth = tick::get_points_in_range(
                current_tick,
                points_growth_global * 3,
                lower_tick,
                upper_tick
            );

            // When the current tick is below the lower:
            // points_growth_below = points_growth_global - points_growth_outside_lower
            // points_growth_above = points_growth_outside_upper
            let lower_tick_value = std::option::borrow(&lower_tick);
            let upper_tick_value = std::option::borrow(&upper_tick);
            let points_growth_below = integer_mate::math_u128::wrapping_sub(
                points_growth_global * 3,
                tick::points_growth_outside(lower_tick_value)
            );
            let points_growth_above = tick::points_growth_outside(upper_tick_value);

            let expected_points_growth = integer_mate::math_u128::wrapping_sub(
                integer_mate::math_u128::wrapping_sub(points_growth_global * 3, points_growth_below),
                points_growth_above
            );

            assert!(points_growth == expected_points_growth, 47);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_get_points_in_range_current_tick_above() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(20); // Current tick is above the upper
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 1000;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 1000;

            // Create ticks with initial values
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the lower tick to update points_growth_outside
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_lower,
                true,
                liquidity,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the upper tick with new values
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_upper,
                false,
                liquidity,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global * 2,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Get ticks
            let lower_tick = tick::try_borrow_tick(tick_manager, tick_lower);
            let upper_tick = tick::try_borrow_tick(tick_manager, tick_upper);

            // Check points in range
            let points_growth = tick::get_points_in_range(
                current_tick,
                points_growth_global * 3,
                lower_tick,
                upper_tick
            );

            // When the current tick is above the upper:
            // points_growth_below = points_growth_outside_lower
            // points_growth_above = points_growth_global - points_growth_outside_upper
            let lower_tick_value = std::option::borrow(&lower_tick);
            let upper_tick_value = std::option::borrow(&upper_tick);
            let points_growth_below = tick::points_growth_outside(lower_tick_value);
            let points_growth_above = integer_mate::math_u128::wrapping_sub(
                points_growth_global * 3,
                tick::points_growth_outside(upper_tick_value)
            );

            let expected_points_growth = integer_mate::math_u128::wrapping_sub(
                integer_mate::math_u128::wrapping_sub(points_growth_global * 3, points_growth_below),
                points_growth_above
            );

            assert!(points_growth == expected_points_growth, 48);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_get_points_in_range_current_tick_between() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(0); // Current tick is between lower and upper
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 1000;
            let rewards_growth_global = vector::empty<u128>();
            let fullsail_distribution_growth_global = 1000;

            // Create ticks with initial values
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the lower tick to update points_growth_outside
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_lower,
                true,
                liquidity,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the upper tick with new values
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_upper,
                false,
                liquidity,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global * 2,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Get ticks
            let lower_tick = tick::try_borrow_tick(tick_manager, tick_lower);
            let upper_tick = tick::try_borrow_tick(tick_manager, tick_upper);

            // Check points in range
            let points_growth = tick::get_points_in_range(
                current_tick,
                points_growth_global * 3,
                lower_tick,
                upper_tick
            );

            // When the current tick is between lower and upper:
            // points_growth_below = points_growth_outside_lower
            // points_growth_above = points_growth_outside_upper
            let lower_tick_value = std::option::borrow(&lower_tick);
            let upper_tick_value = std::option::borrow(&upper_tick);
            let points_growth_below = tick::points_growth_outside(lower_tick_value);
            let points_growth_above = tick::points_growth_outside(upper_tick_value);

            let expected_points_growth = integer_mate::math_u128::wrapping_sub(
                integer_mate::math_u128::wrapping_sub(points_growth_global * 3, points_growth_below),
                points_growth_above
            );

            assert!(points_growth == expected_points_growth, 49);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_get_reward_growth_outside() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(0);
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 0;
            let mut rewards_growth_global = vector::empty<u128>();
            vector::push_back(&mut rewards_growth_global, 1000); // First reward
            vector::push_back(&mut rewards_growth_global, 2000); // Second reward
            let fullsail_distribution_growth_global = 0;

            // Create ticks with initial values
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Get tick
            let tick = tick::borrow_tick(tick_manager, tick_lower);

            // Check getting rewards for existing indices
            let reward_0 = tick::get_reward_growth_outside(tick, 0);
            let reward_1 = tick::get_reward_growth_outside(tick, 1);
            assert!(reward_0 == 1000, 50);
            assert!(reward_1 == 2000, 51);

            // Check getting reward for non-existing index
            let reward_2 = tick::get_reward_growth_outside(tick, 2);
            assert!(reward_2 == 0, 52);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_get_rewards_in_range_current_tick_below() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::neg_from(20); // Current tick is below the lower
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 0;
            let mut rewards_growth_global = vector::empty<u128>();
            vector::push_back(&mut rewards_growth_global, 1000); // First reward
            vector::push_back(&mut rewards_growth_global, 2000); // Second reward
            let fullsail_distribution_growth_global = 0;

            // Create ticks with initial values
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the lower tick to update rewards_growth_outside
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_lower,
                true,
                liquidity,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the upper tick with new values
            let mut new_rewards_growth_global = vector::empty<u128>();
            vector::push_back(&mut new_rewards_growth_global, 2000); // First reward
            vector::push_back(&mut new_rewards_growth_global, 4000); // Second reward
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_upper,
                false,
                liquidity,
                liquidity,
                0, // fee_growth_global_a
                0, // fee_growth_global_b
                points_growth_global,
                new_rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Get ticks
            let lower_tick = tick::try_borrow_tick(tick_manager, tick_lower);
            let upper_tick = tick::try_borrow_tick(tick_manager, tick_upper);

            // Check rewards in range
            let mut final_rewards_growth_global = vector::empty<u128>();
            vector::push_back(&mut final_rewards_growth_global, 3000); // First reward
            vector::push_back(&mut final_rewards_growth_global, 6000); // Second reward
            let rewards_growth = tick::get_rewards_in_range(
                current_tick,
                final_rewards_growth_global,
                lower_tick,
                upper_tick
            );

            // When the current tick is below the lower:
            // reward_growth_below = reward_growth_global - reward_growth_outside_lower
            // reward_growth_above = reward_growth_outside_upper
            let lower_tick_value = std::option::borrow(&lower_tick);
            let upper_tick_value = std::option::borrow(&upper_tick);
            let reward_0_below = integer_mate::math_u128::wrapping_sub(
                3000,
                tick::get_reward_growth_outside(lower_tick_value, 0)
            );
            let reward_1_below = integer_mate::math_u128::wrapping_sub(
                6000,
                tick::get_reward_growth_outside(lower_tick_value, 1)
            );
            let reward_0_above = tick::get_reward_growth_outside(upper_tick_value, 0);
            let reward_1_above = tick::get_reward_growth_outside(upper_tick_value, 1);

            let expected_reward_0 = integer_mate::math_u128::wrapping_sub(
                integer_mate::math_u128::wrapping_sub(3000, reward_0_below),
                reward_0_above
            );
            let expected_reward_1 = integer_mate::math_u128::wrapping_sub(
                integer_mate::math_u128::wrapping_sub(6000, reward_1_below),
                reward_1_above
            );

            assert!(*vector::borrow(&rewards_growth, 0) == expected_reward_0, 53);
            assert!(*vector::borrow(&rewards_growth, 1) == expected_reward_1, 54);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_get_rewards_in_range_current_tick_above() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(20); // Current tick is above the upper tick
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 0;
            let mut rewards_growth_global = vector::empty<u128>();
            vector::push_back(&mut rewards_growth_global, 1000); // First reward
            vector::push_back(&mut rewards_growth_global, 2000); // Second reward
            let fullsail_distribution_growth_global = 0;

            // Create ticks with initial values
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the lower tick to update rewards_growth_outside
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_lower,
                true,
                liquidity,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the upper tick with new values
            let mut new_rewards_growth_global = vector::empty<u128>();
            vector::push_back(&mut new_rewards_growth_global, 2000); // First reward
            vector::push_back(&mut new_rewards_growth_global, 4000); // Second reward
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_upper,
                false,
                liquidity,
                liquidity,
                0, // fee_growth_global_a
                0, // fee_growth_global_b
                points_growth_global,
                new_rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Get ticks
            let lower_tick = tick::try_borrow_tick(tick_manager, tick_lower);
            let upper_tick = tick::try_borrow_tick(tick_manager, tick_upper);

            // Check rewards in range
            let mut final_rewards_growth_global = vector::empty<u128>();
            vector::push_back(&mut final_rewards_growth_global, 3000); // First reward
            vector::push_back(&mut final_rewards_growth_global, 6000); // Second reward
            let rewards_growth = tick::get_rewards_in_range(
                current_tick,
                final_rewards_growth_global,
                lower_tick,
                upper_tick
            );

            // When the current tick is above the upper tick:
            // reward_growth_below = reward_growth_outside_lower
            // reward_growth_above = reward_growth_global - reward_growth_outside_upper
            let lower_tick_value = std::option::borrow(&lower_tick);
            let upper_tick_value = std::option::borrow(&upper_tick);
            let reward_0_below = tick::get_reward_growth_outside(lower_tick_value, 0);
            let reward_1_below = tick::get_reward_growth_outside(lower_tick_value, 1);
            let reward_0_above = integer_mate::math_u128::wrapping_sub(
                3000,
                tick::get_reward_growth_outside(upper_tick_value, 0)
            );
            let reward_1_above = integer_mate::math_u128::wrapping_sub(
                6000,
                tick::get_reward_growth_outside(upper_tick_value, 1)
            );

            let expected_reward_0 = integer_mate::math_u128::wrapping_sub(
                integer_mate::math_u128::wrapping_sub(3000, reward_0_below),
                reward_0_above
            );
            let expected_reward_1 = integer_mate::math_u128::wrapping_sub(
                integer_mate::math_u128::wrapping_sub(6000, reward_1_below),
                reward_1_above
            );

            assert!(*vector::borrow(&rewards_growth, 0) == expected_reward_0, 55);
            assert!(*vector::borrow(&rewards_growth, 1) == expected_reward_1, 56);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_get_rewards_in_range_current_tick_between() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(10, 12345, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let current_tick = i32::from(0); // Current tick is between the lower and upper ticks
            let tick_lower = i32::neg_from(10);
            let tick_upper = i32::from(10);
            let liquidity = 1000;
            let fee_growth_global_a = 1000;
            let fee_growth_global_b = 2000;
            let points_growth_global = 0;
            let mut rewards_growth_global = vector::empty<u128>();
            vector::push_back(&mut rewards_growth_global, 1000); // First reward
            vector::push_back(&mut rewards_growth_global, 2000); // Second reward
            let fullsail_distribution_growth_global = 0;

            // Create ticks with initial values
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the lower tick to update rewards_growth_outside
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_lower,
                true,
                liquidity,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Cross the upper tick with new values
            let mut new_rewards_growth_global = vector::empty<u128>();
            vector::push_back(&mut new_rewards_growth_global, 2000); // First reward
            vector::push_back(&mut new_rewards_growth_global, 4000); // Second reward
            let (_, _) = tick::cross_by_swap(
                tick_manager,
                tick_upper,
                false,
                liquidity,
                liquidity,
                0, // fee_growth_global_a
                0, // fee_growth_global_b
                points_growth_global,
                new_rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Get ticks
            let lower_tick = tick::try_borrow_tick(tick_manager, tick_lower);
            let upper_tick = tick::try_borrow_tick(tick_manager, tick_upper);

            // Check rewards in range
            let mut final_rewards_growth_global = vector::empty<u128>();
            vector::push_back(&mut final_rewards_growth_global, 3000); // First reward
            vector::push_back(&mut final_rewards_growth_global, 6000); // Second reward
            let rewards_growth = tick::get_rewards_in_range(
                current_tick,
                final_rewards_growth_global,
                lower_tick,
                upper_tick
            );

            // When the current tick is between the lower and upper ticks:
            // reward_growth_below = reward_growth_outside_lower
            // reward_growth_above = reward_growth_outside_upper
            let lower_tick_value = std::option::borrow(&lower_tick);
            let upper_tick_value = std::option::borrow(&upper_tick);
            let reward_0_below = tick::get_reward_growth_outside(lower_tick_value, 0);
            let reward_1_below = tick::get_reward_growth_outside(lower_tick_value, 1);
            let reward_0_above = tick::get_reward_growth_outside(upper_tick_value, 0);
            let reward_1_above = tick::get_reward_growth_outside(upper_tick_value, 1);

            let expected_reward_0 = integer_mate::math_u128::wrapping_sub(
                integer_mate::math_u128::wrapping_sub(3000, reward_0_below),
                reward_0_above
            );
            let expected_reward_1 = integer_mate::math_u128::wrapping_sub(
                integer_mate::math_u128::wrapping_sub(6000, reward_1_below),
                reward_1_above
            );

            assert!(*vector::borrow(&rewards_growth, 0) == expected_reward_0, 57);
            assert!(*vector::borrow(&rewards_growth, 1) == expected_reward_1, 58);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_update_by_liquidity_add_lower_tick() {
        let mut scenario = test_scenario::begin(@0x1);
        {
            let mut helper = TickTestHelper {
                id: sui::object::new(scenario.ctx()),
                tick_manager: tick::new(1, 0, scenario.ctx()),
            };
            let tick_manager = get_tick_manager(&mut helper);
            let tick_lower = integer_mate::i32::from(0);
            let tick_upper = integer_mate::i32::from(10);
            let current_tick = integer_mate::i32::from(5);
            let liquidity = 1000;
            let fee_growth_global_a = 100;
            let fee_growth_global_b = 200;
            let points_growth_global = 300;
            let mut rewards_growth_global = std::vector::empty<u128>();
            std::vector::push_back<u128>(&mut rewards_growth_global, 400);
            std::vector::push_back<u128>(&mut rewards_growth_global, 500);
            let fullsail_distribution_growth_global = 600;

            // Create ticks
            tick::increase_liquidity(
                tick_manager,
                current_tick,
                tick_lower,
                tick_upper,
                liquidity,
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Get the lower tick
            let mut tick = tick::try_borrow_tick(tick_manager, tick_lower);
            assert!(std::option::is_some<Tick>(&tick), 0);
            let mut tick_value = std::option::extract<Tick>(&mut tick);

            // Update liquidity
            let new_liquidity = 500;
            let updated_gross = tick::update_by_liquidity_test(
                &mut tick_value,
                current_tick,
                new_liquidity,
                false, // is_lower_initialized
                true,  // is_add
                false, // is_upper
                fee_growth_global_a,
                fee_growth_global_b,
                points_growth_global,
                rewards_growth_global,
                fullsail_distribution_growth_global
            );

            // Check results
            assert!(updated_gross == liquidity + new_liquidity, 1);
            assert!(tick::liquidity_gross(&tick_value) == liquidity + new_liquidity, 2);
            assert!(integer_mate::i128::eq(tick::liquidity_net(&tick_value), integer_mate::i128::from(liquidity + new_liquidity)), 3);

            transfer::public_transfer(helper, @0x1);
        };
        scenario.end();
    }

    #[test]
    fun test_update_by_liquidity_remove_upper_tick() {
        let mut scenario = test_scenario::begin(@0x1);
        let mut helper = TickTestHelper {
            id: sui::object::new(scenario.ctx()),
            tick_manager: tick::new(1, 0, scenario.ctx()),
        };
        let tick_manager = get_tick_manager(&mut helper);
        let tick_lower = integer_mate::i32::from(0);
        let tick_upper = integer_mate::i32::from(10);
        let current_tick = integer_mate::i32::from(5);
        let initial_liquidity = 1000;
        let fee_growth_global_a = 100;
        let fee_growth_global_b = 200;
        let points_growth_global = 300;
        let mut rewards_growth_global = std::vector::empty<u128>();
        std::vector::push_back<u128>(&mut rewards_growth_global, 400);
        std::vector::push_back<u128>(&mut rewards_growth_global, 500);
        let fullsail_distribution_growth_global = 600;

        // Create ticks
        tick::increase_liquidity(
            tick_manager,
            current_tick,
            tick_lower,
            tick_upper,
            initial_liquidity,
            fee_growth_global_a,
            fee_growth_global_b,
            points_growth_global,
            rewards_growth_global,
            fullsail_distribution_growth_global
        );

        // Get the upper tick
        let mut tick = tick::try_borrow_tick(tick_manager, tick_upper);
        assert!(std::option::is_some<Tick>(&tick), 0);
        let mut tick_value = std::option::extract<Tick>(&mut tick);

        // Remove liquidity
        let remove_liquidity = 500;
        let updated_gross = tick::update_by_liquidity_test(
            &mut tick_value,
            current_tick,
            remove_liquidity,
            false, // is_lower_initialized
            false, // is_add
            true,  // is_upper
            fee_growth_global_a,
            fee_growth_global_b,
            points_growth_global,
            rewards_growth_global,
            fullsail_distribution_growth_global
        );

        // Check results
        assert!(updated_gross == initial_liquidity - remove_liquidity, 1);
        assert!(tick::liquidity_gross(&tick_value) == initial_liquidity - remove_liquidity, 2);
        assert!(integer_mate::i128::eq(tick::liquidity_net(&tick_value), integer_mate::i128::neg_from(initial_liquidity - remove_liquidity)), 3);
        
        transfer::public_transfer(helper, @0x1);

        sui::test_scenario::end(scenario);
    }

    #[test]
    fun test_update_by_liquidity_initialize_lower_tick() {
        // Initialize test scenario and helper
        let mut scenario = test_scenario::begin(@0x1);
        let mut helper = TickTestHelper {
            id: sui::object::new(test_scenario::ctx(&mut scenario)),
            tick_manager: tick::new(1, 0, test_scenario::ctx(&mut scenario)),
        };
        let tick_manager = get_tick_manager(&mut helper);
        let tick_lower = integer_mate::i32::from(0);
        let current_tick = integer_mate::i32::from(5);
        let liquidity = 1000;
        let fee_growth_global_a = 100;
        let fee_growth_global_b = 200;
        let points_growth_global = 300;
        let mut rewards_growth_global = std::vector::empty<u128>();
        std::vector::push_back<u128>(&mut rewards_growth_global, 400);
        std::vector::push_back<u128>(&mut rewards_growth_global, 500);
        let fullsail_distribution_growth_global = 600;

        // Create a tick through increase_liquidity
        tick::increase_liquidity(
            tick_manager,
            current_tick,
            tick_lower,
            integer_mate::i32::from(10), // upper tick
            liquidity,
            fee_growth_global_a,
            fee_growth_global_b,
            points_growth_global,
            rewards_growth_global,
            fullsail_distribution_growth_global
        );

        // Get the tick for verification
        let tick = tick::try_borrow_tick(tick_manager, tick_lower);
        assert!(std::option::is_some(&tick), 1);
        let tick_value = std::option::borrow(&tick);

        // Verify values
        assert!(tick::liquidity_gross(tick_value) == liquidity, 2);
        assert!(integer_mate::i128::eq(tick::liquidity_net(tick_value), integer_mate::i128::from(liquidity)), 3);
        let (fee_a, fee_b) = tick::fee_growth_outside(tick_value);
        // Since current_tick > tick_lower, fee_growth_outside should be equal to fee_growth_global
        assert!(fee_a == fee_growth_global_a && fee_b == fee_growth_global_b, 4);
        assert!(tick::points_growth_outside(tick_value) == points_growth_global, 5);
        assert!(tick::fullsail_distribution_growth_outside(tick_value) == fullsail_distribution_growth_global, 6);
        
        // Clean up
        transfer::public_transfer(helper, @0x1);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1)]
    fun test_update_by_liquidity_remove_more_than_available() {
        let mut scenario = test_scenario::begin(@0x1);
        let mut helper = TickTestHelper {
            id: sui::object::new(scenario.ctx()),
            tick_manager: tick::new(1, 0, scenario.ctx()),
        };
        let tick_manager = get_tick_manager(&mut helper);
        let tick_lower = integer_mate::i32::from(0);
        let tick_upper = integer_mate::i32::from(10);
        let current_tick = integer_mate::i32::from(5);
        let initial_liquidity = 1000;
        let fee_growth_global_a = 100;
        let fee_growth_global_b = 200;
        let points_growth_global = 300;
        let mut rewards_growth_global = std::vector::empty<u128>();
        std::vector::push_back<u128>(&mut rewards_growth_global, 400);
        std::vector::push_back<u128>(&mut rewards_growth_global, 500);
        let fullsail_distribution_growth_global = 600;

        tick::increase_liquidity(
            tick_manager,
            current_tick,
            tick_lower,
            tick_upper,
            initial_liquidity,
            fee_growth_global_a,
            fee_growth_global_b,
            points_growth_global,
            rewards_growth_global,
            fullsail_distribution_growth_global
        );

        // Get the lower tick
        let mut tick = tick::try_borrow_tick(tick_manager, tick_lower);
        assert!(std::option::is_some<Tick>(&tick), 0);
        let mut tick_value = std::option::extract<Tick>(&mut tick);

        // Attempt to remove more liquidity than available
        tick::update_by_liquidity_test(
            &mut tick_value,
            current_tick,
            initial_liquidity + 1,
            false, // is_lower_initialized
            false, // is_add
            false, // is_upper
            fee_growth_global_a,
            fee_growth_global_b,
            points_growth_global,
            rewards_growth_global,
            fullsail_distribution_growth_global
        );

        transfer::public_transfer(helper, @0x1);

        sui::test_scenario::end(scenario);
    }

    #[test]
    fun test_update_fullsail_stake_increase() {
        // Initialize test scenario and helper
        let mut scenario = test_scenario::begin(@0x1);
        let mut helper = TickTestHelper {
            id: sui::object::new(test_scenario::ctx(&mut scenario)),
            tick_manager: tick::new(1, 0, test_scenario::ctx(&mut scenario)),
        };
        let tick_manager = get_tick_manager(&mut helper);
        let tick_index = integer_mate::i32::from(0);
        let initial_liquidity = 1000;
        let stake_increase = integer_mate::i128::from(500);

        // Create a new tick with initial liquidity
        tick::increase_liquidity(
            tick_manager,
            integer_mate::i32::from(5),
            tick_index,
            integer_mate::i32::from(10),
            initial_liquidity,
            0, 0, 0, std::vector::empty<u128>(), 0
        );

        // Increase the stake
        tick::update_fullsail_stake(tick_manager, tick_index, stake_increase, false);

        // Verify the result
        let tick = tick::try_borrow_tick(tick_manager, tick_index);
        assert!(std::option::is_some(&tick), 1);
        let tick_value = std::option::borrow(&tick);
        assert!(integer_mate::i128::eq(
            tick::fullsail_distribution_staked_liquidity_net(tick_value),
            stake_increase
        ), 2);
        
        // Clean up
        transfer::public_transfer(helper, @0x1);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_update_fullsail_stake_decrease() {
        // Initialize test scenario and helper
        let mut scenario = test_scenario::begin(@0x1);
        let mut helper = TickTestHelper {
            id: sui::object::new(test_scenario::ctx(&mut scenario)),
            tick_manager: tick::new(1, 0, test_scenario::ctx(&mut scenario)),
        };
        let tick_manager = get_tick_manager(&mut helper);
        let tick_index = integer_mate::i32::from(0);
        let initial_liquidity = 1000;
        let initial_stake = integer_mate::i128::from(1000);
        let stake_decrease = integer_mate::i128::from(500);

        // Create a new tick with initial liquidity
        tick::increase_liquidity(
            tick_manager,
            integer_mate::i32::from(5),
            tick_index,
            integer_mate::i32::from(10),
            initial_liquidity,
            0, 0, 0, std::vector::empty<u128>(), 0
        );

        // Set initial stake
        tick::update_fullsail_stake(tick_manager, tick_index, initial_stake, false);

        // Decrease the stake
        tick::update_fullsail_stake(tick_manager, tick_index, stake_decrease, true);

        // Verify the result
        let tick = tick::try_borrow_tick(tick_manager, tick_index);
        assert!(std::option::is_some(&tick), 1);
        let tick_value = std::option::borrow(&tick);
        assert!(integer_mate::i128::eq(
            tick::fullsail_distribution_staked_liquidity_net(tick_value),
            integer_mate::i128::sub(initial_stake, stake_decrease)
        ), 2);
        
        // Clean up
        transfer::public_transfer(helper, @0x1);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_update_fullsail_stake_multiple_operations() {
        // Initialize test scenario and helper
        let mut scenario = test_scenario::begin(@0x1);
        let mut helper = TickTestHelper {
            id: sui::object::new(test_scenario::ctx(&mut scenario)),
            tick_manager: tick::new(1, 0, test_scenario::ctx(&mut scenario)),
        };
        let tick_manager = get_tick_manager(&mut helper);
        let tick_index = integer_mate::i32::from(0);
        let initial_liquidity = 1000;
        let stake1 = integer_mate::i128::from(500);
        let stake2 = integer_mate::i128::from(300);
        let stake3 = integer_mate::i128::from(200);

        // Create a new tick with initial liquidity
        tick::increase_liquidity(
            tick_manager,
            integer_mate::i32::from(5),
            tick_index,
            integer_mate::i32::from(10),
            initial_liquidity,
            0, 0, 0, std::vector::empty<u128>(), 0
        );

        // Perform multiple stake operations:
        // 1. Increase stake by 500
        // 2. Increase stake by 300
        // 3. Decrease stake by 200
        tick::update_fullsail_stake(tick_manager, tick_index, stake1, false);
        tick::update_fullsail_stake(tick_manager, tick_index, stake2, false);
        tick::update_fullsail_stake(tick_manager, tick_index, stake3, true);

        // Verify the result: 500 + 300 - 200 = 600
        let tick = tick::try_borrow_tick(tick_manager, tick_index);
        assert!(std::option::is_some(&tick), 1);
        let tick_value = std::option::borrow(&tick);
        assert!(integer_mate::i128::eq(
            tick::fullsail_distribution_staked_liquidity_net(tick_value),
            integer_mate::i128::add(stake1, integer_mate::i128::sub(stake2, stake3))
        ), 2);
        
        // Clean up
        transfer::public_transfer(helper, @0x1);
        test_scenario::end(scenario);
    }
}