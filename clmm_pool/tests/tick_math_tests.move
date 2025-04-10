#[test_only]
module clmm_pool::tick_math_tests {
    use clmm_pool::tick_math;
    use integer_mate::i32;
    use integer_mate::i128;

    #[test]
    fun test_get_sqrt_price_at_tick() {
        // Check boundary values
        let min_tick = tick_math::min_tick();
        let max_tick = tick_math::max_tick();
        
        // Check minimum tick
        let min_sqrt_price = tick_math::get_sqrt_price_at_tick(min_tick);
        assert!(min_sqrt_price == tick_math::min_sqrt_price(), 1);
        
        // Check maximum tick
        let max_sqrt_price = tick_math::get_sqrt_price_at_tick(max_tick);
        assert!(max_sqrt_price == tick_math::max_sqrt_price(), 2);
        
        // Check zero tick
        let zero_tick = i32::from(0);
        let sqrt_price_at_zero = tick_math::get_sqrt_price_at_tick(zero_tick);
        assert!(sqrt_price_at_zero == 79228162514264337593543950336 >> 32, 3);
    }

    #[test]
    fun test_get_tick_at_sqrt_price() {
        // Check boundary values
        let min_sqrt_price = tick_math::min_sqrt_price();
        let max_sqrt_price = tick_math::max_sqrt_price();
        
        // Check minimum price
        let tick_at_min = tick_math::get_tick_at_sqrt_price(min_sqrt_price);
        assert!(i32::eq(tick_at_min, tick_math::min_tick()), 1);
        
        // Check maximum price
        let tick_at_max = tick_math::get_tick_at_sqrt_price(max_sqrt_price);
        assert!(i32::eq(tick_at_max, tick_math::max_tick()), 2);
        
        // Check price in the middle of the range
        let mid_sqrt_price = (min_sqrt_price + max_sqrt_price) / 2;
        let tick_at_mid = tick_math::get_tick_at_sqrt_price(mid_sqrt_price);
        assert!(i32::gte(tick_at_mid, tick_math::min_tick()) && i32::lte(tick_at_mid, tick_math::max_tick()), 3);
    }

    #[test]
    fun test_is_valid_index() {
        // Check valid ticks
        assert!(tick_math::is_valid_index(i32::from(0), 1), 1);
        assert!(tick_math::is_valid_index(i32::from(10), 1), 2);
        assert!(tick_math::is_valid_index(i32::neg_from(10), 1), 3);
        
        // Check invalid ticks (out of bounds)
        assert!(!tick_math::is_valid_index(i32::add(tick_math::max_tick(), i32::from(1)), 1), 4);
        assert!(!tick_math::is_valid_index(i32::sub(tick_math::min_tick(), i32::from(1)), 1), 5);
        
        // Check invalid ticks (not divisible by spacing)
        assert!(!tick_math::is_valid_index(i32::from(1), 2), 6);
        assert!(!tick_math::is_valid_index(i32::from(3), 2), 7);
    }

    #[test]
    #[expected_failure(abort_code = 1)]
    fun test_get_sqrt_price_at_tick_out_of_bounds_min() {
        let tick_below_min = i32::sub(tick_math::min_tick(), i32::from(1));
        tick_math::get_sqrt_price_at_tick(tick_below_min);
    }

    #[test]
    #[expected_failure(abort_code = 1)]
    fun test_get_sqrt_price_at_tick_out_of_bounds_max() {
        let tick_above_max = i32::add(tick_math::max_tick(), i32::from(1));
        tick_math::get_sqrt_price_at_tick(tick_above_max);
    }

    #[test]
    #[expected_failure(abort_code = 2)]
    fun test_get_tick_at_sqrt_price_out_of_bounds_min() {
        let sqrt_price_below_min = tick_math::min_sqrt_price() - 1;
        tick_math::get_tick_at_sqrt_price(sqrt_price_below_min);
    }

    #[test]
    #[expected_failure(abort_code = 2)]
    fun test_get_tick_at_sqrt_price_out_of_bounds_max() {
        let sqrt_price_above_max = tick_math::max_sqrt_price() + 1;
        tick_math::get_tick_at_sqrt_price(sqrt_price_above_max);
    }
}
