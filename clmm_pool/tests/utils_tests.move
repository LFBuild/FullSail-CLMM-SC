#[test_only]
module clmm_pool::utils_tests {
    use clmm_pool::utils;
    use std::string;

    #[test]
    fun test_str_zero() {
        let result = utils::str(0);
        assert!(result == string::utf8(b"0"), 0);
    }

    #[test]
    fun test_str_single_digit() {
        let result = utils::str(5);
        assert!(result == string::utf8(b"5"), 1);
    }

    #[test]
    fun test_str_multiple_digits() {
        let result = utils::str(123);
        assert!(result == string::utf8(b"123"), 2);
    }

    #[test]
    fun test_str_large_number() {
        let result = utils::str(18446744073709551615);
        assert!(result == string::utf8(b"18446744073709551615"), 3);
    }
}
