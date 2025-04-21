# Move STL

## Overview

The `move_stl` package (Standard Template Library for Move) provides a set of standard data structures and utilities for the Move programming language. It includes various containers and helper modules for working with data.


## Main modules
### skip_list.move
Skip list data structure implementation

### skip_list_u128.move
Same as skip_list.move, but for u128 data type

### linked_table.move
Linked bidirection list implementation (main purpose is to store different levels lists for skip list)

### random.move
Pseudo-random number generator. Mainly used for skip list. For that reason it's not required to guarantee absence of potential abuses.

### option_u64.move
Option pattern implementation for u64 data type in SUI object format.

### option_u128.move
Option pattern implementation for u128 data type in SUI object format.

### Key features

#### Safey
* Bound checks and conditions
* Safe memory operations
* Protection against invalid operations
* Input validation
#### Performance

* Optimized algorithms
* Efficient memory usage
* Minimized overhead
* Specialized implementations for different types

#### Flexibility

* Support for different data types
* Customizable parameters
* Extensible functionality
* Adaptability to different use cases

## Usage in CLMM protocol

### Data management
* Storage and processing of prices
* Liquidity management
* Position management
* Reward management

### Optimization

* Fast data access and processing
* Efficient storage of large volumes of information
* Optimization of data operations
* Minimization of transaction costs