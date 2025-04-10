/// Mathematical utilities module for the CLMM (Concentrated Liquidity Market Maker) pool system.
/// This module provides core mathematical functions for:
/// * Computing swap steps and price calculations
/// * Managing liquidity positions
/// * Handling fee calculations
/// * Managing price ticks and ranges
/// 
/// The module implements the mathematical formulas and algorithms required for:
/// * Price movement calculations
/// * Liquidity distribution
/// * Fee computation
/// * Position management
/// * Tick spacing and range calculations
module clmm_pool::clmm_math {
    /// Computes a single step of a swap operation, calculating the amounts, fees, and next price.
    /// This function handles the core swap logic including:
    /// * Price movement calculations
    /// * Fee computations
    /// * Liquidity adjustments
    /// * Amount calculations based on input/output direction
    /// 
    /// # Arguments
    /// * `current_sqrt_price` - Current square root price of the pool, scaled << 64
    /// * `target_sqrt_price` - Target square root price to reach, scaled << 64
    /// * `liquidity` - Current liquidity in the pool, scaled << 64
    /// * `amount` - Amount of tokens to swap
    /// * `fee_rate` - Fee rate for the swap (in basis points, 1/10000)
    /// * `a2b` - Direction of the swap (true for token A to B, false for B to A)
    /// * `by_amount_in` - Whether the amount parameter represents input or output amount
    /// 
    /// # Returns
    /// A tuple containing:
    /// * `amount_in` - Amount of input tokens used
    /// * `amount_out` - Amount of output tokens received
    /// * `next_sqrt_price` - New square root price after the swap
    /// * `fee_amount` - Amount of fees charged
    /// 
    /// # Aborts
    /// * If the target price is invalid for the swap direction (error code: 4)
    /// * If the liquidity is zero (returns zero amounts)
    public fun compute_swap_step(
        current_sqrt_price: u128,
        target_sqrt_price: u128,
        liquidity: u128,
        amount: u64,
        fee_rate: u64,
        a2b: bool,
        by_amount_in: bool
    ): (u64, u64, u128, u64) {
        if (liquidity == 0) {
            return (0, 0, target_sqrt_price, 0)
        };
        if (a2b) {
            assert!(current_sqrt_price >= target_sqrt_price, 4);
        } else {
            assert!(current_sqrt_price < target_sqrt_price, 4);
        };
        let (fee_amount, next_sqrt_price, amount_in, amount_out) = if (by_amount_in) {
            let amount_after_fee = integer_mate::full_math_u64::mul_div_floor(amount, 1000000 - fee_rate, 1000000);
            let mut adjusted_amount = amount_after_fee;
            if (fee_rate > 0 && amount_after_fee == amount) {
                adjusted_amount = amount_after_fee - 1;
            };
            let delta_up = get_delta_up_from_input(current_sqrt_price, target_sqrt_price, liquidity, a2b);
            let (final_amount_in, final_fee_amount, final_sqrt_price) = if (delta_up > (adjusted_amount as u256)) {
                (adjusted_amount, amount - adjusted_amount, get_next_sqrt_price_from_input(current_sqrt_price, liquidity, adjusted_amount, a2b))
            } else {
                (delta_up as u64, integer_mate::full_math_u64::mul_div_ceil(delta_up as u64, fee_rate, 1000000 - fee_rate), target_sqrt_price)
            };
            (final_fee_amount, final_sqrt_price, final_amount_in, get_delta_down_from_output(current_sqrt_price, final_sqrt_price, liquidity, a2b) as u64)
        } else {
            let delta_down = get_delta_down_from_output(current_sqrt_price, target_sqrt_price, liquidity, a2b);
            let (final_amount_out, final_sqrt_price) = if (delta_down > (amount as u256)) {
                (amount, get_next_sqrt_price_from_output(current_sqrt_price, liquidity, amount, a2b))
            } else {
                (delta_down as u64, target_sqrt_price)
            };
            let amount_in = get_delta_up_from_input(current_sqrt_price, final_sqrt_price, liquidity, a2b) as u64;
            let calculated_fee = integer_mate::full_math_u64::mul_div_ceil(amount_in, fee_rate, 1000000 - fee_rate);
            let mut final_fee = calculated_fee;
            if (fee_rate > 0 && calculated_fee == 0) {
                final_fee = 1;
            };
            (final_fee, final_sqrt_price, amount_in, final_amount_out)
        };
        (amount_in, amount_out, next_sqrt_price, fee_amount)
    }

    /// Returns the denominator used for fee rate calculations.
    /// The fee rate is expressed as a fraction with this denominator (1/1000000).
    /// 
    /// # Returns
    /// The fee rate denominator (1000000)
    public fun fee_rate_denominator(): u64 {
        1000000
    }

    /// Calculates the amounts of both tokens in a liquidity position based on the current price and tick range.
    /// This function handles three cases:
    /// * Current price below the lower tick (only token A)
    /// * Current price between lower and upper ticks (both tokens)
    /// * Current price above the upper tick (only token B)
    /// 
    /// # Arguments
    /// * `tick_lower` - Lower tick boundary of the position
    /// * `tick_upper` - Upper tick boundary of the position
    /// * `current_tick` - Current tick index of the pool
    /// * `current_sqrt_price` - Current square root price of the pool
    /// * `liquidity` - Amount of liquidity in the position
    /// * `round_up` - Whether to round up the calculated amounts
    /// 
    /// # Returns
    /// A tuple containing:
    /// * Amount of token A in the position
    /// * Amount of token B in the position
    /// 
    /// # Aborts
    /// * If the current tick is invalid for the position range
    public fun get_amount_by_liquidity(
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32, 
        current_tick: integer_mate::i32::I32,
        current_sqrt_price: u128,
        liquidity: u128,
        round_up: bool
    ): (u64, u64) {
        if (liquidity == 0) {
            return (0, 0)
        };
        if (integer_mate::i32::lt(current_tick, tick_lower)) {
            (get_delta_a(
                clmm_pool::tick_math::get_sqrt_price_at_tick(tick_lower),
                clmm_pool::tick_math::get_sqrt_price_at_tick(tick_upper),
                liquidity,
                round_up
            ), 0)
        } else {
            let (amount_a, amount_b) = if (integer_mate::i32::lt(current_tick, tick_upper)) {
                (get_delta_a(current_sqrt_price, clmm_pool::tick_math::get_sqrt_price_at_tick(tick_upper), liquidity, round_up), 
                 get_delta_b(
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_lower),
                    current_sqrt_price,
                    liquidity,
                    round_up
                ))
            } else {
                (0, get_delta_b(
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_lower),
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_upper),
                    liquidity,
                    round_up
                ))
            };
            (amount_a, amount_b)
        }
    }

    /// Calculates the amount of token A needed for a given price range and liquidity.
    /// This function is used to determine the amount of token A required when adding or removing liquidity.
    /// 
    /// # Arguments
    /// * `sqrt_price_a` - Square root price at point A
    /// * `sqrt_price_b` - Square root price at point B
    /// * `liquidity` - Amount of liquidity
    /// * `round_up` - Whether to round up the result
    /// 
    /// # Returns
    /// The amount of token A needed
    /// 
    /// # Aborts
    /// * If the calculation would overflow (error code: 2)
    public fun get_delta_a(sqrt_price_a: u128, sqrt_price_b: u128, liquidity: u128, round_up: bool): u64 {
        let sqrt_price_diff = if (sqrt_price_a > sqrt_price_b) {
            sqrt_price_a - sqrt_price_b
        } else {
            sqrt_price_b - sqrt_price_a
        };
        if (sqrt_price_diff == 0 || liquidity == 0) {
            return 0
        };
        let (shifted_product, overflow) = integer_mate::math_u256::checked_shlw(integer_mate::full_math_u128::full_mul(liquidity, sqrt_price_diff));
        if (overflow) {
            abort 2
        };
        integer_mate::math_u256::div_round(shifted_product, integer_mate::full_math_u128::full_mul(sqrt_price_a, sqrt_price_b), round_up) as u64
    }

    /// Calculates the amount of token B needed for a given price range and liquidity.
    /// This function is used to determine the amount of token B required when adding or removing liquidity.
    /// 
    /// # Arguments
    /// * `sqrt_price_a` - Square root price at point A
    /// * `sqrt_price_b` - Square root price at point B
    /// * `liquidity` - Amount of liquidity
    /// * `round_up` - Whether to round up the result
    /// 
    /// # Returns
    /// The amount of token B needed
    public fun get_delta_b(sqrt_price_a: u128, sqrt_price_b: u128, liquidity: u128, round_up: bool): u64 {
        let sqrt_price_diff = if (sqrt_price_a > sqrt_price_b) {
            sqrt_price_a - sqrt_price_b
        } else {
            sqrt_price_b - sqrt_price_a
        };
        if (sqrt_price_diff == 0 || liquidity == 0) {
            return 0
        };
        let product = integer_mate::full_math_u128::full_mul(liquidity, sqrt_price_diff);
        if (round_up && (product & 18446744073709551615 > 0)) {
            return ((product >> 64) + 1) as u64
        };
        (product >> 64) as u64
    }

    /// Calculates the output amount for a given price range and liquidity, rounding down.
    /// Used in swap calculations when determining output amounts.
    /// 
    /// # Arguments
    /// * `sqrt_price_a` - Square root price at point A
    /// * `sqrt_price_b` - Square root price at point B
    /// * `liquidity` - Amount of liquidity
    /// * `round_up` - Whether to round up the result
    /// 
    /// # Returns
    /// The output amount as a u256 value
    /// 
    /// # Aborts
    /// * If the calculation would overflow (error code: 2)
    public fun get_delta_down_from_output(sqrt_price_a: u128, sqrt_price_b: u128, liquidity: u128, round_up: bool): u256 {
        let sqrt_price_diff = if (sqrt_price_a > sqrt_price_b) {
            sqrt_price_a - sqrt_price_b
        } else {
            sqrt_price_b - sqrt_price_a
        };
        if (sqrt_price_diff == 0 || liquidity == 0) {
            return 0
        };
        if (round_up) {
            integer_mate::full_math_u128::full_mul(liquidity, sqrt_price_diff) >> 64
        } else {
            let (shifted_product, overflow) = integer_mate::math_u256::checked_shlw(integer_mate::full_math_u128::full_mul(liquidity, sqrt_price_diff));
            if (overflow) {
                abort 2
            };
            integer_mate::math_u256::div_round(shifted_product, integer_mate::full_math_u128::full_mul(sqrt_price_a, sqrt_price_b), false)
        }
    }

    /// Calculates the input amount needed for a given price range and liquidity, rounding up.
    /// Used in swap calculations when determining input amounts.
    /// 
    /// # Arguments
    /// * `sqrt_price_a` - Square root price at point A
    /// * `sqrt_price_b` - Square root price at point B
    /// * `liquidity` - Amount of liquidity
    /// * `round_up` - Whether to round up the result
    /// 
    /// # Returns
    /// The input amount as a u256 value
    /// 
    /// # Aborts
    /// * If the calculation would overflow (error code: 2)
    public fun get_delta_up_from_input(sqrt_price_a: u128, sqrt_price_b: u128, liquidity: u128, round_up: bool): u256 {
        let sqrt_price_diff = if (sqrt_price_a > sqrt_price_b) {
            sqrt_price_a - sqrt_price_b
        } else {
            sqrt_price_b - sqrt_price_a
        };
        if (sqrt_price_diff == 0 || liquidity == 0) {
            return 0
        };
        if (round_up) {
            let (shifted_product, overflow) = integer_mate::math_u256::checked_shlw(integer_mate::full_math_u128::full_mul(liquidity, sqrt_price_diff));
            if (overflow) {
                abort 2
            };
            integer_mate::math_u256::div_round(shifted_product, integer_mate::full_math_u128::full_mul(sqrt_price_a, sqrt_price_b), true)
        } else {
            let product = integer_mate::full_math_u128::full_mul(liquidity, sqrt_price_diff);
            let result = if (product & 18446744073709551615 > 0) {
                (product >> 64) + 1
            } else {
                product >> 64
            };
            result
        }
    }

    /// Calculates the liquidity and token amounts needed for a position based on a fixed input amount.
    /// This function handles both cases where the input amount is fixed for either token A or B.
    /// 
    /// # Arguments
    /// * `tick_lower` - Lower tick boundary of the position
    /// * `tick_upper` - Upper tick boundary of the position
    /// * `current_tick` - Current tick index of the pool
    /// * `current_sqrt_price` - Current square root price of the pool
    /// * `amount_in` - Fixed input amount of tokens
    /// * `is_fix_amount_a` - Whether the input amount is for token A (true) or B (false)
    /// 
    /// # Returns
    /// A tuple containing:
    /// * The calculated liquidity amount
    /// * The amount of token A needed
    /// * The amount of token B needed
    /// 
    /// # Aborts
    /// * If the current tick is outside the valid range (error code: 3018)
    public fun get_liquidity_by_amount(
        tick_lower: integer_mate::i32::I32,
        tick_upper: integer_mate::i32::I32,
        current_tick: integer_mate::i32::I32,
        current_sqrt_price: u128,
        amount_in: u64,
        is_fix_amount_a: bool
    ): (u128, u64, u64) {
        assert!(amount_in > 0, 3019);
        if (is_fix_amount_a) {
            let (liquidity, amount_b) = if (integer_mate::i32::lt(current_tick, tick_lower)) {
                (get_liquidity_from_a(
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_lower),
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_upper),
                    amount_in,
                    false
                ), 0)
            } else {
                assert!(integer_mate::i32::lt(current_tick, tick_upper), 3018);
                let liquidity = get_liquidity_from_a(current_sqrt_price, clmm_pool::tick_math::get_sqrt_price_at_tick(tick_upper), amount_in, false);
                (liquidity, get_delta_b(current_sqrt_price, clmm_pool::tick_math::get_sqrt_price_at_tick(tick_lower), liquidity, true))
            };
            (liquidity, amount_in, amount_b)
        } else {
            let (liquidity, amount_a) = if (integer_mate::i32::gte(current_tick, tick_upper)) {
                (get_liquidity_from_b(
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_lower),
                    clmm_pool::tick_math::get_sqrt_price_at_tick(tick_upper),
                    amount_in,
                    false
                ), 0)
            } else {
                assert!(integer_mate::i32::gte(current_tick, tick_lower), 3018);
                let liquidity = get_liquidity_from_b(clmm_pool::tick_math::get_sqrt_price_at_tick(tick_lower), current_sqrt_price, amount_in, false);
                (liquidity, get_delta_a(current_sqrt_price, clmm_pool::tick_math::get_sqrt_price_at_tick(tick_upper), liquidity, true))
            };
            (liquidity, amount_a, amount_in)
        }
    }
    
    /// Calculates the liquidity needed for a position when the amount of token A is fixed.
    /// This function is used to determine the required liquidity when adding a specific amount of token A.
    /// 
    /// # Arguments
    /// * `sqrt_price_a` - Square root price at point A
    /// * `sqrt_price_b` - Square root price at point B
    /// * `amount` - Fixed amount of token A
    /// * `round_up` - Whether to round up the result
    /// 
    /// # Returns
    /// The calculated liquidity amount
    public fun get_liquidity_from_a(
        sqrt_price_a: u128,
        sqrt_price_b: u128,
        amount: u64,
        round_up: bool
    ): u128 {
        let sqrt_price_diff = if (sqrt_price_a > sqrt_price_b) {
            sqrt_price_a - sqrt_price_b
        } else {
            sqrt_price_b - sqrt_price_a
        };
        integer_mate::math_u256::div_round(
            (integer_mate::full_math_u128::full_mul(sqrt_price_a, sqrt_price_b) >> 64) * (amount as u256),
            sqrt_price_diff as u256,
            round_up
        ) as u128
    }

    /// Calculates the liquidity needed for a position when the amount of token B is fixed.
    /// This function is used to determine the required liquidity when adding a specific amount of token B.
    /// 
    /// # Arguments
    /// * `sqrt_price_a` - Square root price at point A
    /// * `sqrt_price_b` - Square root price at point B
    /// * `amount` - Fixed amount of token B
    /// * `round_up` - Whether to round up the result
    /// 
    /// # Returns
    /// The calculated liquidity amount
    public fun get_liquidity_from_b(sqrt_price_a: u128, sqrt_price_b: u128, amount: u64, round_up: bool): u128 {
        let sqrt_price_diff = if (sqrt_price_a > sqrt_price_b) {
            sqrt_price_a - sqrt_price_b
        } else {
            sqrt_price_b - sqrt_price_a
        };
        assert!(sqrt_price_diff > 0, 3020);
        integer_mate::math_u256::div_round((amount as u256) << 64, sqrt_price_diff as u256, round_up) as u128
    }

    /// Calculates the next square root price when adding or removing token A.
    /// This function handles price movement in the direction of token A.
    /// 
    /// # Arguments
    /// * `sqrt_price` - Current square root price
    /// * `liquidity` - Current liquidity in the pool
    /// * `amount` - Amount of token A to add or remove
    /// * `add` - Whether to add (true) or remove (false) the amount
    /// 
    /// # Returns
    /// The new square root price after the operation
    /// 
    /// # Aborts
    /// * If the calculation would overflow (error code: 2)
    /// * If the resulting price would exceed maximum allowed price (error code: 0)
    /// * If the resulting price would be below minimum allowed price (error code: 1)
    public fun get_next_sqrt_price_a_up(sqrt_price: u128, liquidity: u128, amount: u64, add: bool): u128 {
        if (amount == 0) {
            return sqrt_price
        };
        let (product, overflow) = integer_mate::math_u256::checked_shlw(integer_mate::full_math_u128::full_mul(sqrt_price, liquidity));
        if (overflow) {
            abort 2
        };
        let next_sqrt_price = if (add) {
            integer_mate::math_u256::div_round(
                product,
                ((liquidity as u256) << 64) + integer_mate::full_math_u128::full_mul(sqrt_price, amount as u128),
                true
            ) as u128
        } else {
            integer_mate::math_u256::div_round(
                product,
                ((liquidity as u256) << 64) - integer_mate::full_math_u128::full_mul(sqrt_price, amount as u128),
                true
            ) as u128
        };
        if (next_sqrt_price > clmm_pool::tick_math::max_sqrt_price()) {
            abort 0
        };
        if (next_sqrt_price < clmm_pool::tick_math::min_sqrt_price()) {
            abort 1
        };
        next_sqrt_price
    }
    
    /// Calculates the next square root price when adding or removing token B.
    /// This function handles price movement in the direction of token B.
    /// 
    /// # Arguments
    /// * `sqrt_price` - Current square root price
    /// * `liquidity` - Current liquidity in the pool
    /// * `amount` - Amount of token B to add or remove
    /// * `add` - Whether to add (true) or remove (false) the amount
    /// 
    /// # Returns
    /// The new square root price after the operation
    /// 
    /// # Aborts
    /// * If the calculation would overflow
    /// * If the resulting price would exceed maximum allowed price (error code: 0)
    /// * If the resulting price would be below minimum allowed price (error code: 1)
    public fun get_next_sqrt_price_b_down(sqrt_price: u128, liquidity: u128, amount: u64, add: bool): u128 {
        let next_sqrt_price = if (add) {
            sqrt_price + integer_mate::math_u128::checked_div_round((amount as u128) << 64, liquidity, !add)
        } else {
            sqrt_price - integer_mate::math_u128::checked_div_round((amount as u128) << 64, liquidity, !add)
        };
        if (next_sqrt_price > clmm_pool::tick_math::max_sqrt_price()) {
            abort 0
        };
        if (next_sqrt_price < clmm_pool::tick_math::min_sqrt_price()) {
            abort 1
        };
        next_sqrt_price
    }

    /// Calculates the next square root price based on an input amount of tokens.
    /// This function determines the price movement based on the token type and input amount.
    /// 
    /// # Arguments
    /// * `sqrt_price` - Current square root price
    /// * `liquidity` - Current liquidity in the pool
    /// * `amount` - Input amount of tokens
    /// * `is_token_a` - Whether the input token is token A (true) or B (false)
    /// 
    /// # Returns
    /// The new square root price after the operation
    /// 
    /// # Aborts
    /// * If the calculation would overflow
    /// * If the resulting price would exceed maximum allowed price (error code: 0)
    /// * If the resulting price would be below minimum allowed price (error code: 1)
    public fun get_next_sqrt_price_from_input(sqrt_price: u128, liquidity: u128, amount: u64, is_token_a: bool): u128 {
        if (is_token_a) {
            get_next_sqrt_price_a_up(sqrt_price, liquidity, amount, true)
        } else {
            get_next_sqrt_price_b_down(sqrt_price, liquidity, amount, true)
        }
    }

    /// Calculates the next square root price based on an output amount of tokens.
    /// This function determines the price movement based on the token type and output amount.
    /// 
    /// # Arguments
    /// * `sqrt_price` - Current square root price
    /// * `liquidity` - Current liquidity in the pool
    /// * `amount` - Output amount of tokens
    /// * `is_token_a` - Whether the output token is token A (true) or B (false)
    /// 
    /// # Returns
    /// The new square root price after the operation
    /// 
    /// # Aborts
    /// * If the calculation would overflow
    /// * If the resulting price would exceed maximum allowed price (error code: 0)
    /// * If the resulting price would be below minimum allowed price (error code: 1)
    public fun get_next_sqrt_price_from_output(sqrt_price: u128, liquidity: u128, amount: u64, is_token_a: bool): u128 {
        if (is_token_a) {
            get_next_sqrt_price_b_down(sqrt_price, liquidity, amount, false)
        } else {
            get_next_sqrt_price_a_up(sqrt_price, liquidity, amount, false)
        }
    }
}

