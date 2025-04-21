# integer_mate

## Overview

The `integer_mate` package provides a set of functions for working with integers. It includes various functions for working with integers, including addition, subtraction, multiplication, division, and more.

## Main modules

### Wrappers

* i32.move
* i64.move
* i128.move

Contains wrappers for basic integer types with basic arithmetic operations.

Key feature are calculations efficiency and overflow checks.

### Math

* math_u64.move
* math_u128.move
* math_u256.move

Overflow safe arithmetic operations for u64, u128 and u256 types. For u64 and u128 safety is being achieved by using u128 and u256 for intermediate calculations. For u256 there are only supportive functions for possible overflow checks before calculations.

### Full math

* full_math_u64.move
* full_math_u128.move

Functions for common arithmetic formulas with two operations. For example, mul_div_floor = floor((a*b)/c). Overflow safety is being achieved by using u128 and u256 data types for intermediate calculations.