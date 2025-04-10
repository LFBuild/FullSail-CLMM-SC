/// Utility module providing helper functions for the CLMM (Concentrated Liquidity Market Maker) pool system.
/// This module contains utility functions for string conversion and formatting.
/// 
/// # Functions
/// * `str` - Converts unsigned 64-bit integers to their string representation
/// 
/// # Usage
/// This module is used internally by other modules in the CLMM pool system to:
/// * Convert numbers to strings for display and logging
module clmm_pool::utils {
    /// Converts an unsigned 64-bit integer to its string representation.
    /// 
    /// # Arguments
    /// * `number` - The u64 number to convert to string
    /// 
    /// # Returns
    /// A string representation of the input number
    /// 
    /// # Examples
    /// ```
    /// let s = str(123); // returns "123"
    /// let s = str(0);   // returns "0"
    /// ```
    /// 
    /// # Implementation Details
    /// * Handles zero case separately, returning "0"
    /// * For non-zero numbers:
    ///   - Extracts digits one by one from right to left
    ///   - Converts each digit to ASCII by adding 48
    ///   - Reverses the resulting vector to get correct order
    ///   - Converts the byte vector to UTF-8 string
    public fun str(mut number: u64): std::string::String {
        if (number == 0) {
            return std::string::utf8(b"0")
        };
        let mut digits = std::vector::empty<u8>();
        while (number > 0) {
            let digit = (number % 10) as u8;
            number = number / 10;
            std::vector::push_back<u8>(&mut digits, digit + 48);
        };
        std::vector::reverse<u8>(&mut digits);
        std::string::utf8(digits)
    }
}

