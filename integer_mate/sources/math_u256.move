module integer_mate::math_u256 {
    const MAX_U256: u256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    public fun div_mod(num: u256, denom: u256): (u256, u256) {
        let p = num / denom;
        let r: u256 = num - (p * denom);
        (p, r)
    }

    public fun shlw(n: u256): u256 {
        n << 64
    }

    public fun shrw(n: u256): u256 {
        n >> 64
    }

    public fun checked_shlw(n: u256): (u256, bool) {
        let mask = 1 << 192;
        if (n >= mask) {
            (0, true)
        } else {
            ((n << 64), false)
        }
    }

    public fun div_round(num: u256, denom: u256, round_up: bool): u256 {
        let p = num / denom;
        if (round_up && ((p * denom) != num)) {
            p + 1
        } else {
            p
        }
    }

    public fun add_check(num1: u256, num2: u256): bool {
        (MAX_U256 - num1 >= num2)
    }

    #[test]
    fun test_div_round() {
        div_round(1, 1, true);
    }

    #[test]
    fun test_add() {
        1000u256 + 1000u256;
    }

    #[test]
    fun test_checked_shlw() {
        // Test 1: Normal case - number less than mask
        let (result, overflow) = checked_shlw(1);
        assert!(result == 1 << 64, 1);
        assert!(!overflow, 2);

        // Test 2: Edge case - number equals mask (1 << 192)
        let max = 6277101735386680763835789423207666416102355444464034512896;
        let (result, overflow) = checked_shlw(max);
        assert!(result == 0, 3);
        assert!(overflow, 4);

        // Test 3: Edge case - number greater than mask
        let (result, overflow) = checked_shlw(max + 1);
        assert!(result == 0, 5);
        assert!(overflow, 6);

        // Test 4: Edge case - maximum u256 value
        let (result, overflow) = checked_shlw(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        assert!(result == 0, 7);
        assert!(overflow, 8);

        // Test 5: Edge case - zero
        let (result, overflow) = checked_shlw(0);
        assert!(result == 0, 9);
        assert!(!overflow, 10);

        // Test 6: Edge case - number close to mask (mask - 1)
        let (result, overflow) = checked_shlw(max - 1);
        assert!(result == (max - 1) << 64, 11);
        assert!(!overflow, 12);
    }
}
