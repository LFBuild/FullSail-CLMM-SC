/// Tick math module for the CLMM (Concentrated Liquidity Market Maker) pool system.
/// This module provides functionality for:
/// * Converting between price and tick index
/// * Calculating square root of price
/// * Managing tick spacing and boundaries
/// * Handling tick-related mathematical operations
/// 
/// The module implements:
/// * Price to tick index conversion
/// * Tick index to price conversion
/// * Square root price calculations
/// * Tick spacing validation
/// 
/// # Key Concepts
/// * Tick - A discrete price point in the pool
/// * Price - The actual price value
/// * Tick Index - Integer representation of a price point
/// * Tick Spacing - Minimum distance between ticks
/// 
/// # Constants
/// * MIN_TICK - Minimum allowed tick index
/// * MAX_TICK - Maximum allowed tick index
/// * MIN_SQRT_PRICE - Minimum allowed square root price
/// * MAX_SQRT_PRICE - Maximum allowed square root price
module clmm_pool::tick_math {
    /// Converts a boolean value to u8.
    /// Returns 1 if the input is true, 0 otherwise.
    /// 
    /// # Arguments
    /// * `is_true` - Boolean value to convert
    /// 
    /// # Returns
    /// * 1 if input is true
    /// * 0 if input is false
    fun as_u8(is_true: bool): u8 {
        if (is_true) {
            1
        } else {
            0
        }
    }

    /// Calculates the square root price for a negative tick index.
    /// This function uses a series of bitwise operations and multiplications
    /// to compute the square root price efficiently.
    /// 
    /// # Arguments
    /// * `tick_index` - Negative tick index to calculate square root price for
    /// 
    /// # Returns
    /// The square root price as a u128 value
    /// 
    /// # Implementation Details
    /// The function uses a lookup table approach with pre-computed values
    /// for different bit positions to efficiently calculate the square root price.
    /// It performs a series of conditional multiplications based on the bit
    /// representation of the absolute tick value.
    fun get_sqrt_price_at_negative_tick(tick_index: integer_mate::i32::I32): u128 {
        let abs_tick = integer_mate::i32::as_u32(integer_mate::i32::abs(tick_index));
        let initial_price = if (abs_tick & 1 != 0) {
            18445821805675392311
        } else {
            18446744073709551616
        };
        let mut result = initial_price;
        if (abs_tick & 2 != 0) {
            result = integer_mate::full_math_u128::mul_shr(initial_price, 18444899583751176498, 64);
        };
        if (abs_tick & 4 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 18443055278223354162, 64);
        };
        if (abs_tick & 8 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 18439367220385604838, 64);
        };
        if (abs_tick & 16 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 18431993317065449817, 64);
        };
        if (abs_tick & 32 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 18417254355718160513, 64);
        };
        if (abs_tick & 64 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 18387811781193591352, 64);
        };
        if (abs_tick & 128 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 18329067761203520168, 64);
        };
        if (abs_tick & 256 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 18212142134806087854, 64);
        };
        if (abs_tick & 512 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 17980523815641551639, 64);
        };
        if (abs_tick & 1024 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 17526086738831147013, 64);
        };
        if (abs_tick & 2048 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 16651378430235024244, 64);
        };
        if (abs_tick & 4096 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 15030750278693429944, 64);
        };
        if (abs_tick & 8192 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 12247334978882834399, 64);
        };
        if (abs_tick & 16384 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 8131365268884726200, 64);
        };
        if (abs_tick & 32768 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 3584323654723342297, 64);
        };
        if (abs_tick & 65536 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 696457651847595233, 64);
        };
        if (abs_tick & 131072 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 26294789957452057, 64);
        };
        if (abs_tick & 262144 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 37481735321082, 64);
        };
        result
    }

    /// Calculates the square root price for a positive tick index.
    /// This function uses a series of bitwise operations and multiplications
    /// to compute the square root price efficiently.
    /// 
    /// # Arguments
    /// * `tick` - Positive tick index to calculate square root price for
    /// 
    /// # Returns
    /// The square root price as a u128 value
    /// 
    /// # Implementation Details
    /// The function uses a lookup table approach with pre-computed values
    /// for different bit positions to efficiently calculate the square root price.
    /// It performs a series of conditional multiplications based on the bit
    /// representation of the absolute tick value.
    /// The result is shifted right by 32 bits to normalize the output.
    fun get_sqrt_price_at_positive_tick(tick: integer_mate::i32::I32): u128 {
        let abs_tick = integer_mate::i32::as_u32(integer_mate::i32::abs(tick));
        let initial_price = if (abs_tick & 1 != 0) {
            79232123823359799118286999567
        } else {
            79228162514264337593543950336
        };
        let mut result = initial_price;
        if (abs_tick & 2 != 0) {
            result = integer_mate::full_math_u128::mul_shr(initial_price, 79236085330515764027303304731, 96);
        };
        if (abs_tick & 4 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 79244008939048815603706035061, 96);
        };
        if (abs_tick & 8 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 79259858533276714757314932305, 96);
        };
        if (abs_tick & 16 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 79291567232598584799939703904, 96);
        };
        if (abs_tick & 32 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 79355022692464371645785046466, 96);
        };
        if (abs_tick & 64 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 79482085999252804386437311141, 96);
        };
        if (abs_tick & 128 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 79736823300114093921829183326, 96);
        };
        if (abs_tick & 256 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 80248749790819932309965073892, 96);
        };
        if (abs_tick & 512 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 81282483887344747381513967011, 96);
        };
        if (abs_tick & 1024 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 83390072131320151908154831281, 96);
        };
        if (abs_tick & 2048 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 87770609709833776024991924138, 96);
        };
        if (abs_tick & 4096 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 97234110755111693312479820773, 96);
        };
        if (abs_tick & 8192 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 119332217159966728226237229890, 96);
        };
        if (abs_tick & 16384 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 179736315981702064433883588727, 96);
        };
        if (abs_tick & 32768 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 407748233172238350107850275304, 96);
        };
        if (abs_tick & 65536 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 2098478828474011932436660412517, 96);
        };
        if (abs_tick & 131072 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 55581415166113811149459800483533, 96);
        };
        if (abs_tick & 262144 != 0) {
            result = integer_mate::full_math_u128::mul_shr(result, 38992368544603139932233054999993551, 96);
        };
        result >> 32
    }

    /// Calculates the square root price for a given tick index.
    /// This function determines whether the tick is positive or negative
    /// and calls the appropriate calculation function.
    /// 
    /// # Arguments
    /// * `tick_index` - Tick index to calculate square root price for
    /// 
    /// # Returns
    /// The square root price as a u128 value
    /// 
    /// # Abort Conditions
    /// * If tick_index is less than MIN_TICK (error code: 1)
    /// * If tick_index is greater than MAX_TICK (error code: 1)
    /// 
    /// # Implementation Details
    /// The function first validates that the tick index is within valid bounds,
    /// then delegates the calculation to either get_sqrt_price_at_negative_tick
    /// or get_sqrt_price_at_positive_tick based on the sign of the tick.
    public fun get_sqrt_price_at_tick(tick_index: integer_mate::i32::I32): u128 {
        assert!(integer_mate::i32::gte(tick_index, min_tick()) && integer_mate::i32::lte(tick_index, max_tick()), 1);
        if (integer_mate::i32::is_neg(tick_index)) {
            get_sqrt_price_at_negative_tick(tick_index)
        } else {
            get_sqrt_price_at_positive_tick(tick_index)
        }
    }

    /// Calculates the tick index for a given square root price.
    /// This function performs a binary search-like algorithm to find the closest tick
    /// that corresponds to the given square root price.
    /// 
    /// # Arguments
    /// * `sqrt_price` - Square root price to find tick index for
    /// 
    /// # Returns
    /// The tick index as an I32 value
    /// 
    /// # Abort Conditions
    /// * If sqrt_price is less than MIN_SQRT_PRICE (error code: 2)
    /// * If sqrt_price is greater than MAX_SQRT_PRICE (error code: 2)
    /// 
    /// # Implementation Details
    /// The function uses a combination of bit manipulation and binary search to efficiently
    /// find the closest tick. It:
    /// 1. Validates the input price is within valid bounds
    /// 2. Calculates the most significant bits of the price
    /// 3. Uses bit shifting and comparison to find the closest tick
    /// 4. Performs final validation by checking the calculated tick's price
    public fun get_tick_at_sqrt_price(sqrt_price: u128): integer_mate::i32::I32 {
        assert!(sqrt_price >= 4295048016 && sqrt_price <= 79226673515401279992447579055, 2);
        let msb_bits = as_u8(sqrt_price >= 18446744073709551616) << 6;
        let msb_shifted = sqrt_price >> msb_bits;
        let high_bits = as_u8(msb_shifted >= 4294967296) << 5;
        let high_shifted = msb_shifted >> high_bits;
        let mid_high_bits = as_u8(high_shifted >= 65536) << 4;
        let mid_high_shifted = high_shifted >> mid_high_bits;
        let mid_bits = as_u8(mid_high_shifted >= 256) << 3;
        let mid_shifted = mid_high_shifted >> mid_bits;
        let mid_low_bits = as_u8(mid_shifted >= 16) << 2;
        let mid_low_shifted = mid_shifted >> mid_low_bits;
        let low_bits = as_u8(mid_low_shifted >= 4) << 1;
        let total_bits = 0 | msb_bits | high_bits | mid_high_bits | mid_bits | mid_low_bits | low_bits | as_u8(mid_low_shifted >> low_bits >= 2) << 0;
        let mut result = integer_mate::i128::shl(
            integer_mate::i128::sub(integer_mate::i128::from(total_bits as u128), integer_mate::i128::from(64)),
            32
        );
        let shifted_price = if (total_bits >= 64) {
            sqrt_price >> total_bits - 63
        } else {
            sqrt_price << 63 - total_bits
        };
        let mut current_value = shifted_price;
        let mut bit_pos = 31;
        while (bit_pos >= 18) {
            let squared = current_value * current_value >> 63;
            let shift_amount = (squared >> 64) as u8;
            result = integer_mate::i128::or(result, integer_mate::i128::shl(integer_mate::i128::from(shift_amount as u128), bit_pos));
            current_value = squared >> shift_amount;
            bit_pos = bit_pos - 1;
        };
        let multiplied = integer_mate::i128::mul(result, integer_mate::i128::from(59543866431366));
        let tick_low = integer_mate::i128::as_i32(
            integer_mate::i128::shr(integer_mate::i128::sub(multiplied, integer_mate::i128::from(184467440737095516)), 64)
        );
        let tick_high = integer_mate::i128::as_i32(
            integer_mate::i128::shr(integer_mate::i128::add(multiplied, integer_mate::i128::from(15793534762490258745)), 64)
        );
        if (integer_mate::i32::eq(tick_low, tick_high)) {
            tick_low
        } else {
            let final_tick = if (get_sqrt_price_at_tick(tick_high) <= sqrt_price) {
                tick_high
            } else {
                tick_low
            };
            final_tick
        }
    }

    /// Checks if a tick index is valid based on the tick spacing.
    /// A tick index is valid if it:
    /// 1. Is greater than or equal to MIN_TICK
    /// 2. Is less than or equal to MAX_TICK
    /// 3. Is divisible by the tick spacing
    /// 
    /// # Arguments
    /// * `tick_index` - The tick index to validate
    /// * `tick_spacing` - The minimum distance between valid ticks
    /// 
    /// # Returns
    /// * true if the tick index is valid
    /// * false otherwise
    public fun is_valid_index(tick_index: integer_mate::i32::I32, tick_spacing: u32): bool {
        if (integer_mate::i32::gte(tick_index, min_tick())) {
            if (integer_mate::i32::lte(tick_index, max_tick())) {
                integer_mate::i32::mod(tick_index, integer_mate::i32::from(tick_spacing)) == integer_mate::i32::from(0)
            } else {
                false
            }
        } else {
            false
        }
    }

    /// Returns the maximum allowed square root price.
    /// This is the highest possible price that can be represented in the pool.
    /// 
    /// # Returns
    /// The maximum square root price as a u128 value
    public fun max_sqrt_price(): u128 {
        79226673515401279992447579055
    }

    /// Returns the maximum allowed tick index.
    /// This is the highest possible tick that can be used in the pool.
    /// 
    /// # Returns
    /// The maximum tick index as an I32 value
    public fun max_tick(): integer_mate::i32::I32 {
        integer_mate::i32::from(443636)
    }

    /// Returns the minimum allowed square root price.
    /// This is the lowest possible price that can be represented in the pool.
    /// 
    /// # Returns
    /// The minimum square root price as a u128 value
    public fun min_sqrt_price(): u128 {
        4295048016
    }

    /// Returns the minimum allowed tick index.
    /// This is the lowest possible tick that can be used in the pool.
    /// 
    /// # Returns
    /// The minimum tick index as an I32 value
    public fun min_tick(): integer_mate::i32::I32 {
        integer_mate::i32::neg_from(443636)
    }

    /// Returns the maximum allowed tick bound.
    /// This value represents the absolute maximum tick index that can be used,
    /// regardless of direction (positive or negative).
    /// 
    /// # Returns
    /// The maximum tick bound as a u32 value
    public fun tick_bound(): u32 {
        443636
    }

    #[test]
    fun test_get_sqrt_price_at_negative_tick() {
        // Test with tick = -1
        let tick_minus_one = integer_mate::i32::neg_from(1);
        let sqrt_price = get_sqrt_price_at_negative_tick(tick_minus_one);
        assert!(sqrt_price == 18445821805675392311, 1);

        // Test with tick = -2
        let tick_minus_two = integer_mate::i32::neg_from(2);
        let sqrt_price = get_sqrt_price_at_negative_tick(tick_minus_two);
        assert!(sqrt_price == 18444899583751176498, 2);

        // Test with tick = -4
        let tick_minus_four = integer_mate::i32::neg_from(4);
        let sqrt_price = get_sqrt_price_at_negative_tick(tick_minus_four);
        assert!(sqrt_price == 18443055278223354162, 3);
    }

    #[test]
    fun test_get_sqrt_price_at_positive_tick() {
        // Test with tick = 1
        let tick_one = integer_mate::i32::from(1);
        let sqrt_price = get_sqrt_price_at_positive_tick(tick_one);
        assert!(sqrt_price == 79232123823359799118286999567 >> 32, 1);

        // Test with tick = 2
        let tick_two = integer_mate::i32::from(2);
        let sqrt_price = get_sqrt_price_at_positive_tick(tick_two);
        assert!(sqrt_price == 79236085330515764027303304731 >> 32, 2);

        // Test with tick = 4
        let tick_four = integer_mate::i32::from(4);
            let sqrt_price = get_sqrt_price_at_positive_tick(tick_four);
        assert!(sqrt_price == 79244008939048815603706035061 >> 32, 3);
    }

    #[test]
    fun test_get_sqrt_price_at_positive_tick_powers_of_two() {
        // Test with tick = 8 (2^3)
        let tick_eight = integer_mate::i32::from(8);
        let sqrt_price = get_sqrt_price_at_positive_tick(tick_eight);
        assert!(sqrt_price == 79259858533276714757314932305 >> 32, 1);

        // Test with tick = 16 (2^4)
        let tick_sixteen = integer_mate::i32::from(16);
        let sqrt_price = get_sqrt_price_at_positive_tick(tick_sixteen);
        assert!(sqrt_price == 79291567232598584799939703904 >> 32, 2);

        // Test with tick = 32 (2^5)
        let tick_thirty_two = integer_mate::i32::from(32);
        let sqrt_price = get_sqrt_price_at_positive_tick(tick_thirty_two);
        assert!(sqrt_price == 79355022692464371645785046466 >> 32, 3);
    }

    #[test]
    fun test_get_sqrt_price_at_negative_tick_powers_of_two() {
        // Test with tick = -8 (2^3)
        let tick_minus_eight = integer_mate::i32::neg_from(8);
        let sqrt_price = get_sqrt_price_at_negative_tick(tick_minus_eight);
        assert!(sqrt_price == 18439367220385604838, 1);

        // Test with tick = -16 (2^4)
        let tick_minus_sixteen = integer_mate::i32::neg_from(16);
        let sqrt_price = get_sqrt_price_at_negative_tick(tick_minus_sixteen);
        assert!(sqrt_price == 18431993317065449817, 2);

        // Test with tick = -32 (2^5)
        let tick_minus_thirty_two = integer_mate::i32::neg_from(32);
        let sqrt_price = get_sqrt_price_at_negative_tick(tick_minus_thirty_two);
        assert!(sqrt_price == 18417254355718160513, 3);
    }
}