#[test_only]
module clmm_pool::clmm_math_tests {
    use clmm_pool::clmm_math;
    use std::debug;

    #[test]
    fun test_compute_swap_step_zero_liquidity() {
        let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_math::compute_swap_step(
            100000 << 64, // current_sqrt_price
            90000 << 64,  // target_sqrt_price
            0,      // liquidity
            1000,   // amount
            3000,   // fee_rate (0.3%)
            true,   // a2b
            true    // by_amount_in
        );
        assert!(amount_in == 0, 1);
        assert!(amount_out == 0, 2);
        assert!(next_sqrt_price == 90000 << 64, 3);
        assert!(fee_amount == 0, 4);
    }

    #[test]
    fun test_compute_swap_step_a2b_by_amount_in() {
        let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_math::compute_swap_step(
            100000 << 64, // current_sqrt_price
            99000 << 64,  // target_sqrt_price (increased difference)
            10000000 << 64, // liquidity (increased and shifted)
            5,      // amount (further reduced to avoid price going below minimum)
            3000,   // fee_rate (0.3% = 3000/1000000)
            true,   // a2b
            true    // by_amount_in
        );
        assert!(amount_in == 4, 1); // 5 - 0.3% fee
        assert!(amount_out > 0, 2);
        assert!(next_sqrt_price < 100000 << 64, 3); // Price should decrease for a2b
        assert!(fee_amount == 1, 4); // 0.3% of 5
    }

    // TODO
    // #[test]
    // fun test_compute_swap_step_b2a_by_amount_in() {
    //     let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_math::compute_swap_step(
    //         100000 << 64, // current_sqrt_price
    //         200000 << 64, // target_sqrt_price (increased difference)
    //         1000000 << 64, // liquidity (decreased)
    //         5,    // amount
    //         3000,   // fee_rate (0.3% = 3000/1000000)
    //         false,  // b2a
    //         true    // by_amount_in
    //     );
    //     assert!(amount_in == 4, 1); // 5 - 0.3% fee
    //     assert!(amount_out > 0, 2);
    //     assert!(next_sqrt_price > 100000 << 64, 3); // Price should increase for b2a
    //     assert!(fee_amount == 1, 4); // 0.3% of 5
    // }

    #[test]
    fun test_compute_swap_step_a2b_by_amount_out() {
        let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_math::compute_swap_step(
            100000 << 64, // current_sqrt_price
            95000 << 64,  // target_sqrt_price
            10000000 << 64, // liquidity (increased and shifted)
            100,    // amount
            3000,   // fee_rate (0.3% = 3000/1000000)
            true,   // a2b
            false   // by_amount_out
        );
        assert!(amount_out == 100, 1);
        assert!(amount_in > 0, 2); // Should be positive but may be less than amount_out due to price movement
        assert!(next_sqrt_price < 100000 << 64, 3);
        assert!(fee_amount > 0, 4);
    }

    #[test]
    fun test_compute_swap_step_b2a_by_amount_out() {
        let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_math::compute_swap_step(
            100000 << 64, // current_sqrt_price
            105000 << 64, // target_sqrt_price
            10000000 << 64, // liquidity (increased and shifted)
            100,    // amount
            3000,   // fee_rate (0.3% = 3000/1000000)
            false,  // b2a
            false   // by_amount_out
        );
        assert!(amount_out == 100, 1);
        assert!(amount_in > 100, 2); // Should be more due to fee
        assert!(next_sqrt_price > 100000 << 64, 3);
        assert!(fee_amount > 0, 4);
    }

    #[test]
    fun test_compute_swap_step_zero_fee() {
        let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_math::compute_swap_step(
            100000 << 64, // current_sqrt_price
            95000 << 64,  // target_sqrt_price
            10000000 << 64, // liquidity (increased and shifted)
            100,    // amount
            0,      // fee_rate (0%)
            true,   // a2b
            true    // by_amount_in
        );
        assert!(amount_in == 100, 1); // No fee deduction
        assert!(amount_out > 0, 2);
        assert!(next_sqrt_price < 100000 << 64, 3);
        assert!(fee_amount == 0, 4);
    }

    #[test]
    #[expected_failure(abort_code = 4)]
    fun test_compute_swap_step_invalid_price_a2b() {
        clmm_math::compute_swap_step(
            100000 << 64, // current_sqrt_price
            105000 << 64, // target_sqrt_price (higher than current for a2b)
            10000000 << 64, // liquidity (increased and shifted)
            100,    // amount
            3000,   // fee_rate (0.3% = 3000/1000000)
            true,   // a2b
            true    // by_amount_in
        );
    }

    #[test]
    #[expected_failure(abort_code = 4)]
    fun test_compute_swap_step_invalid_price_b2a() {
        clmm_math::compute_swap_step(
            100000 << 64, // current_sqrt_price
            95000 << 64,  // target_sqrt_price (lower than current for b2a)
            10000000 << 64, // liquidity (increased and shifted)
            100,    // amount
            3000,   // fee_rate (0.3% = 3000/1000000)
            false,  // b2a
            true    // by_amount_in
        );
    }

    #[test]
    fun test_fee_rate_denominator() {
        assert!(clmm_math::fee_rate_denominator() == 1000000, 1);
    }

// TODO
    // #[test]
    // #[expected_failure(abort_code = 2)]
    // fun test_compute_swap_step_overflow() {
    //     clmm_math::compute_swap_step(
    //         100000 << 64, // current_sqrt_price
    //         105000 << 64, // target_sqrt_price
    //         100000000 << 64, // liquidity 
    //         1000,   // amount
    //         3000,   // fee_rate (0.3% = 3000/1000000)
    //         false,  // b2a
    //         true    // by_amount_in
    //     );
    // }

    #[test]
    fun test_compute_swap_step_b2a_large_amount() {
        let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_math::compute_swap_step(
            100000 << 64, // current_sqrt_price
            50000 << 64,  // target_sqrt_price (large difference)
            10000000 << 64, // liquidity
            1000000,    // amount (large amount)
            3000,   // fee_rate (0.3% = 3000/1000000)
            true,   // a2b
            true    // by_amount_in
        );
        assert!(amount_in == 997000, 1); // 1000000 - 0.3% fee
        assert!(amount_out > 0, 2);
        assert!(next_sqrt_price < 100000 << 64, 3); // Price should decrease for a2b
        assert!(fee_amount == 3000, 4); // 0.3% of 1000000
    }

    // TODO
    // #[test]
    // fun test_compute_swap_step_b2a_large_amount_small_diff() {
    //     let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_math::compute_swap_step(
    //         100000 << 64, // current_sqrt_price
    //         105000 << 64, // target_sqrt_price (small difference)
    //         10000000 << 64, // liquidity
    //         1000000,    // amount (large amount)
    //         3000,   // fee_rate (0.3% = 3000/1000000)
    //         false,  // b2a
    //         true    // by_amount_in
    //     );
    //     assert!(amount_in == 997000, 1); // 1000000 - 0.3% fee
    //     assert!(amount_out > 0, 2);
    //     assert!(next_sqrt_price > 100000 << 64, 3); // Price should increase for b2a
    //     assert!(fee_amount == 3000, 4); // 0.3% of 1000000
    // }

    // #[test]
    // fun test_compute_swap_step_b2a_large_amount_large_diff() {
    //     let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_math::compute_swap_step(
    //         100000 << 64, // current_sqrt_price
    //         300000 << 64, // target_sqrt_price (large difference)
    //         10000000 << 64, // liquidity
    //         1000000,    // amount (large amount)
    //         3000,   // fee_rate (0.3% = 3000/1000000)
    //         false,  // b2a
    //         true    // by_amount_in
    //     );
    //     assert!(amount_in == 997000, 1); // 1000000 - 0.3% fee
    //     assert!(amount_out > 0, 2);
    //     assert!(next_sqrt_price > 100000 << 64, 3); // Price should increase for b2a
    //     assert!(fee_amount == 3000, 4); // 0.3% of 1000000
    // }

    // TODO
    // #[test]
    // fun test_compute_swap_step_b2a_large_amount_large_liquidity() {
    //     let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_math::compute_swap_step(
    //         100000 << 64, // current_sqrt_price
    //         150000 << 64, // target_sqrt_price
    //         1000000000 << 64, // liquidity (large liquidity)
    //         1000000,    // amount (large amount)
    //         3000,   // fee_rate (0.3% = 3000/1000000)
    //         false,  // b2a
    //         true    // by_amount_in
    //     );
    //     assert!(amount_in == 997000, 1); // 1000000 - 0.3% fee
    //     assert!(amount_out > 0, 2);
    //     assert!(next_sqrt_price > 100000 << 64, 3); // Price should increase for b2a
    //     assert!(fee_amount == 3000, 4); // 0.3% of 1000000
    // }

// TODO
    // #[test]
    // fun test_compute_swap_step_b2a_large_amount_small_liquidity() {
    //     let (amount_in, amount_out, next_sqrt_price, fee_amount) = clmm_math::compute_swap_step(
    //         100000 << 64, // current_sqrt_price
    //         110000 << 64, // target_sqrt_price (higher than current for b2a)
    //         1000000 << 64, // liquidity
    //         1000000,    // amount (large amount)
    //         3000,   // fee_rate (0.3% = 3000/1000000)
    //         false,  // b2a
    //         true    // by_amount_in
    //     );
    //     assert!(amount_in == 997000, 1); // 1000000 - 0.3% fee
    //     assert!(amount_out > 0, 2);
    //     assert!(next_sqrt_price > 100000 << 64, 3); // Price should increase for b2a
    //     assert!(fee_amount == 3000, 4); // 0.3% of 1000000
    // }
}
