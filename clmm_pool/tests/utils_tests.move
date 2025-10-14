/// © 2025 Metabyte Labs, Inc.  All Rights Reserved.
/// U.S. Patent Application No. 63/861,982. The technology described herein is the subject of a pending U.S. patent application.
/// Full Sail has added a license to its Full Sail protocol code. You can view the terms of the license at [ULR](LICENSE/250825_Metabyte_Negotiated_Services_Agreement21634227_2_002.docx).

#[test_only]
module clmm_pool::utils_tests {
    #[allow(unused_const)]
    const COPYRIGHT_NOTICE: vector<u8> = b"© 2025 Metabyte Labs, Inc.  All Rights Reserved.";
    #[allow(unused_const)]
    const PATENT_NOTICE: vector<u8> = b"Patent pending - U.S. Patent Application No. 63/861,982";

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
