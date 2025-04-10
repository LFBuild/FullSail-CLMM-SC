#[test_only]
module clmm_pool::position_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::tx_context::{Self, TxContext};
    use clmm_pool::position::{
        Self,
        PositionInfo,
        PositionReward,
        POSITION,
        PositionManager,
        Position,
        check_position_tick_range,
        new,
        open_position,
        borrow_position_info,
        is_staked,
        mark_position_staked,
        StakePositionEvent,
        new_position_name,
        borrow_mut_position_info,
        reset_fee,
        test_update_fees,
        reset_rewarder,
        reward_amount_owned,
        reward_growth_inside,
        rewards_amount_owned,
        url,
        update_and_reset_fee,
        update_and_reset_fullsail_distribution,
        update_and_reset_rewards,
        update_fee,
        update_fullsail_distribution,
        update_points,
        update_rewards,
    };
    use integer_mate::i32;
    use sui::object;
    use move_stl::linked_table;
    use sui::transfer;
    use std::type_name;
    use std::string;
    use sui::object::ID;
    use std::vector;

    /// Test structure for managing position manager in tests
    #[test_only]
    public struct TestPositionManager has key, store {
        id: sui::object::UID,
        position_manager: PositionManager,
    }

    #[test]
    /// Test new function
    /// Verifies that:
    /// 1. PositionManager is created with correct tick_spacing
    /// 2. Initial position_index is 0
    /// 3. Positions table is empty
    fun test_new() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        let tick_spacing = 1;
        let test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(tick_spacing, scenario.ctx())
        };

        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test open_position function
    /// Verifies that:
    /// 1. A new position is created with correct parameters
    /// 2. Position info is initialized correctly
    /// 3. Position is added to the positions table
    /// 4. Position index is incremented
    fun test_open_position() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Verify position properties
        assert!(position::pool_id(&position) == pool_id, 1);
        assert!(position::index(&position) == 1, 2);
        
        let (pos_tick_lower, pos_tick_upper) = position::tick_range(&position);
        assert!(i32::eq(pos_tick_lower, tick_lower), 3);
        assert!(i32::eq(pos_tick_upper, tick_upper), 4);
        
        assert!(position::liquidity(&position) == 0, 5);
        
        let pos_name = position::name(&position);
        assert!(string::utf8(b"Fullsail position:1-1") == pos_name, 6);
        
        let pos_desc = position::description(&position);
        assert!(string::utf8(b"Fullsail Liquidity Position") == pos_desc, 7);
        
        let pos_url = position::url(&position);
        assert!(pool_url == pos_url, 8);

        // Verify position info is in the table
        let position_id = object::id(&position);
        assert!(position::is_position_exist(&test_manager.position_manager, position_id), 9);
        
        // Verify position info properties
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        assert!(position::info_position_id(position_info) == position_id, 10);
        assert!(position::info_liquidity(position_info) == 0, 11);
        
        let (info_tick_lower, info_tick_upper) = position::info_tick_range(position_info);
        assert!(i32::eq(info_tick_lower, tick_lower), 12);
        assert!(i32::eq(info_tick_upper, tick_upper), 13);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test open_position with different tick ranges
    /// Verifies that:
    /// 1. Positions with different tick ranges can be created
    /// 2. Each position gets a unique index
    /// 3. All positions are properly stored in the manager
    fun test_open_position_different_tick_ranges() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define different tick ranges
        let mut tick_lower_ranges = vector::empty<integer_mate::i32::I32>();
        let mut tick_upper_ranges = vector::empty<integer_mate::i32::I32>();
        
        vector::push_back(&mut tick_lower_ranges, i32::from(0));
        vector::push_back(&mut tick_upper_ranges, i32::from(10));
        
        vector::push_back(&mut tick_lower_ranges, i32::from(10));
        vector::push_back(&mut tick_upper_ranges, i32::from(20));
        
        vector::push_back(&mut tick_lower_ranges, i32::from(20));
        vector::push_back(&mut tick_upper_ranges, i32::from(30));
        
        vector::push_back(&mut tick_lower_ranges, i32::from(30));
        vector::push_back(&mut tick_upper_ranges, i32::from(40));
        
        // Create positions with different tick ranges
        let mut i = 0;
        while (i < vector::length(&tick_lower_ranges)) {
            let tick_lower = *vector::borrow(&tick_lower_ranges, i);
            let tick_upper = *vector::borrow(&tick_upper_ranges, i);
            
            let position = position::open_position<type_name::TypeName, type_name::TypeName>(
                &mut test_manager.position_manager,
                pool_id,
                pool_index,
                pool_url,
                tick_lower,
                tick_upper,
                scenario.ctx()
            );
            
            // Verify position index is incremented correctly
            assert!(position::index(&position) == i + 1, 1);
            
            // Verify tick range
            let (pos_tick_lower, pos_tick_upper) = position::tick_range(&position);
            assert!(i32::eq(pos_tick_lower, tick_lower), 2);
            assert!(i32::eq(pos_tick_upper, tick_upper), 3);
            
            assert!(position::is_position_exist(&test_manager.position_manager, object::id(&position)), 4);

            transfer::public_transfer(position, admin);
            
            i = i + 1;
        };
        
    
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test open_position with different tick spacing
    /// Verifies that:
    /// 1. PositionManager with different tick spacing can create positions
    /// 2. Positions are created with correct tick alignment
    fun test_open_position_different_tick_spacing() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager with tick spacing of 2
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(2, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick ranges that are aligned with tick spacing of 2
        let mut tick_lower_ranges = vector::empty<integer_mate::i32::I32>();
        let mut tick_upper_ranges = vector::empty<integer_mate::i32::I32>();
        
        vector::push_back(&mut tick_lower_ranges, i32::from(0));
        vector::push_back(&mut tick_upper_ranges, i32::from(10));
        
        vector::push_back(&mut tick_lower_ranges, i32::from(10));
        vector::push_back(&mut tick_upper_ranges, i32::from(20));
        
        vector::push_back(&mut tick_lower_ranges, i32::from(20));
        vector::push_back(&mut tick_upper_ranges, i32::from(30));
        
        // Create positions with different tick ranges
        let mut i = 0;
        while (i < vector::length(&tick_lower_ranges)) {
            let tick_lower = *vector::borrow(&tick_lower_ranges, i);
            let tick_upper = *vector::borrow(&tick_upper_ranges, i);
            
            let position = position::open_position<type_name::TypeName, type_name::TypeName>(
                &mut test_manager.position_manager,
                pool_id,
                pool_index,
                pool_url,
                tick_lower,
                tick_upper,
                scenario.ctx()
            );
            
            // Verify tick range
            let (pos_tick_lower, pos_tick_upper) = position::tick_range(&position);
            assert!(i32::eq(pos_tick_lower, tick_lower), 1);
            assert!(i32::eq(pos_tick_upper, tick_upper), 2);
            
            transfer::public_transfer(position, admin);
            
            i = i + 1;
        };
        
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test open_position with multiple pools
    /// Verifies that:
    /// 1. Positions can be created for different pools
    /// 2. Position names reflect the correct pool index
    fun test_open_position_multiple_pools() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create multiple pool IDs for testing
        let mut pool_ids = vector::empty<object::ID>();
        vector::push_back(&mut pool_ids, object::id_from_address(admin));
        vector::push_back(&mut pool_ids, object::id_from_address(@0x2));
        vector::push_back(&mut pool_ids, object::id_from_address(@0x3));
        
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);
                
        // Create positions for different pools
        let mut i = 0;
        while (i < vector::length(&pool_ids)) {
            let pool_id = *vector::borrow(&pool_ids, i);
            let pool_index = i + 1;
            
            let position = position::open_position<type_name::TypeName, type_name::TypeName>(
                &mut test_manager.position_manager,
                pool_id,
                pool_index,
                pool_url,
                tick_lower,
                tick_upper,
                scenario.ctx()
            );
            
            // Verify pool ID
            assert!(position::pool_id(&position) == pool_id, 1);
            
            // Verify position name reflects the correct pool index
            let pos_name = position::name(&position);
            let expected_name = if (pool_index == 1) {
                string::utf8(b"Fullsail position:1-1")
            } else if (pool_index == 2) {
                string::utf8(b"Fullsail position:2-2")
            } else {
                string::utf8(b"Fullsail position:3-3")
            };

            assert!(pos_name == expected_name, 2);

            transfer::public_transfer(position, admin);
            
            i = i + 1;
        };
        
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test open_position with different token types
    /// Verifies that:
    /// 1. Positions can be created with different token type combinations
    /// 2. Token types are correctly stored in the position
    fun test_open_position_different_token_types() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);
        
        // Create positions with different token type combinations
        let position1 = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );
        
        let position2 = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );
        
        // Verify positions have different indices
        assert!(position::index(&position1) == 1, 1);
        assert!(position::index(&position2) == 2, 2);
        
        // Transfer objects
        transfer::public_transfer(position1, admin);
        transfer::public_transfer(position2, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test position getter methods
    /// Verifies that:
    /// 1. All getter methods for Position return correct values
    fun test_position_getters() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Test all getter methods
        assert!(position::pool_id(&position) == pool_id, 1);
        assert!(position::index(&position) == 1, 2);
        
        let (pos_tick_lower, pos_tick_upper) = position::tick_range(&position);
        assert!(i32::eq(pos_tick_lower, tick_lower), 3);
        assert!(i32::eq(pos_tick_upper, tick_upper), 4);
        
        assert!(position::liquidity(&position) == 0, 5);
        
        let pos_name = position::name(&position);
        assert!(string::utf8(b"Fullsail position:1-1") == pos_name, 6);
        
        let pos_desc = position::description(&position);
        assert!(string::utf8(b"Fullsail Liquidity Position") == pos_desc, 7);
        
        let pos_url = position::url(&position);
        assert!(pool_url == pos_url, 8);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test set_description method
    /// Verifies that:
    /// 1. Description can be updated for a position
    fun test_set_description() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let mut position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Update description
        let new_description = string::utf8(b"Updated Position Description");
        position::set_description(&mut position, new_description);
        
        // Verify description was updated
        let updated_desc = position::description(&position);
        assert!(new_description == updated_desc, 1);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test close_position method
    /// Verifies that:
    /// 1. Empty positions can be closed
    /// 2. Position is removed from the manager
    fun test_close_position() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Verify position exists in the manager
        let position_id = object::id(&position);
        assert!(position::is_position_exist(&test_manager.position_manager, position_id), 1);
        
        // Close the position
        position::close_position(&mut test_manager.position_manager, position);
        
        // Verify position no longer exists in the manager
        assert!(!position::is_position_exist(&test_manager.position_manager, position_id), 2);
        
        // Transfer manager
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test close_position method with non-empty position
    /// Verifies that:
    /// 1. Attempting to close a non-empty position fails with error code 7
    #[expected_failure(abort_code = 7)]
    fun test_close_position_non_empty() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let mut position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Add liquidity to make the position non-empty
        let liquidity_delta = 1000;
        let fee_growth_a = 0;
        let fee_growth_b = 0;
        let points_growth = 0;
        let mut rewards_growth = vector::empty<u128>();
        let fullsail_growth = 0;
        
        position::increase_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            liquidity_delta,
            fee_growth_a,
            fee_growth_b,
            points_growth,
            rewards_growth,
            fullsail_growth
        );

        // Verify position exists in the manager
        let position_id = object::id(&position);
        assert!(position::is_position_exist(&test_manager.position_manager, position_id), 1);
        
        // Attempt to close the non-empty position
        // This should abort with error code 7
        position::close_position(&mut test_manager.position_manager, position);
        
        // Transfer manager
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test is_empty function with empty position
    /// Verifies that:
    /// 1. A newly created position is considered empty
    fun test_is_empty_true() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Get position ID
        let position_id = object::id(&position);
        
        // Get position info
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        
        // Verify position is empty
        assert!(position::is_empty(position_info), 1);
        
        // Verify position has no liquidity
        assert!(position::info_liquidity(position_info) == 0, 2);
        
        // Verify position has no fees
        let (fee_owned_a, fee_owned_b) = position::info_fee_owned(position_info);
        assert!(fee_owned_a == 0, 3);
        assert!(fee_owned_b == 0, 4);
        
        // Verify position has no points
        assert!(position::info_points_owned(position_info) == 0, 5);
        
        // Verify position has no rewards
        let rewards = position::info_rewards(position_info);
        assert!(vector::length(rewards) == 0, 6);
        
        // Verify position has no fullsail distribution
        assert!(position::info_fullsail_distribution_owned(position_info) == 0, 7);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test is_empty function with non-empty position (with liquidity)
    /// Verifies that:
    /// 1. A position with liquidity is not considered empty
    fun test_is_empty_false_liquidity() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let mut position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Add liquidity to make the position non-empty
        let liquidity_delta = 1000;
        let fee_growth_a = 0;
        let fee_growth_b = 0;
        let points_growth = 0;
        let mut rewards_growth = vector::empty<u128>();
        let fullsail_growth = 0;
        
        position::increase_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            liquidity_delta,
            fee_growth_a,
            fee_growth_b,
            points_growth,
            rewards_growth,
            fullsail_growth
        );

        // Get position ID
        let position_id = object::id(&position);
        
        // Get position info
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        
        // Verify position is not empty
        assert!(!position::is_empty(position_info), 1);
        
        // Verify position has liquidity
        assert!(position::info_liquidity(position_info) == liquidity_delta, 2);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test is_empty function with non-empty position (with fees)
    /// Verifies that:
    /// 1. A position with fees is not considered empty
    fun test_is_empty_false_fees() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let mut position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Add liquidity first
        let liquidity_delta = 1000;
        let fee_growth_a = 0;
        let fee_growth_b = 0;
        let points_growth = 0;
        let mut rewards_growth = vector::empty<u128>();
        let fullsail_growth = 0;
        
        position::increase_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            liquidity_delta,
            fee_growth_a,
            fee_growth_b,
            points_growth,
            rewards_growth,
            fullsail_growth
        );

        // Get position ID
        let position_id = object::id(&position);
        
        // Get position info before updating fees
        let position_info_before = position::borrow_position_info(&test_manager.position_manager, position_id);
        
        // Verify position is not empty due to liquidity
        assert!(!position::is_empty(position_info_before), 1);

        // Update fees to make the position have fees
        let fee_growth_a_updated = 100;
        let fee_growth_b_updated = 200;
        
        let (fee_owned_a, fee_owned_b) = position::update_fee(
            &mut test_manager.position_manager,
            position_id,
            fee_growth_a_updated,
            fee_growth_b_updated
        );
        
        // Get position info after updating fees
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        
        // Verify position is not empty
        assert!(!position::is_empty(position_info), 2);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test is_empty function with non-empty position (with rewards)
    /// Verifies that:
    /// 1. A position with rewards is not considered empty
    fun test_is_empty_false_rewards() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let mut position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Add liquidity first
        let liquidity_delta = 1000;
        let fee_growth_a = 0;
        let fee_growth_b = 0;
        let points_growth = 0;
        let mut rewards_growth = vector::empty<u128>();
        let fullsail_growth = 0;
        
        position::increase_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            liquidity_delta,
            fee_growth_a,
            fee_growth_b,
            points_growth,
            rewards_growth,
            fullsail_growth
        );

        // Get position ID
        let position_id = object::id(&position);
        
        // Get position info before updating rewards
        let position_info_before = position::borrow_position_info(&test_manager.position_manager, position_id);
        
        // Verify position is not empty due to liquidity
        assert!(!position::is_empty(position_info_before), 1);

        // Update rewards to simulate some reward growth
        let mut rewards_growth_updated = vector::empty<u128>();
        vector::push_back(&mut rewards_growth_updated, 100);
        
        let rewards_amount = position::update_rewards(
            &mut test_manager.position_manager,
            position_id,
            rewards_growth_updated
        );
        
        // Verify rewards were updated
        assert!(vector::length(&rewards_amount) == 1, 2);
        
        // Get position info after updating rewards
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        
        // Verify position is not empty
        assert!(!position::is_empty(position_info), 3);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test increase_liquidity method
    /// Verifies that:
    /// 1. Liquidity can be increased for a position
    /// 2. Position info is updated correctly
    fun test_increase_liquidity() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let mut position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Initial liquidity should be 0
        assert!(position::liquidity(&position) == 0, 1);
        
        // Increase liquidity
        let liquidity_delta = 1000;
        let fee_growth_a = 0;
        let fee_growth_b = 0;
        let points_growth = 0;
        let mut rewards_growth = vector::empty<u128>();
        let fullsail_growth = 0;
        
        let new_liquidity = position::increase_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            liquidity_delta,
            fee_growth_a,
            fee_growth_b,
            points_growth,
            rewards_growth,
            fullsail_growth
        );
        
        // Verify liquidity was increased
        assert!(new_liquidity == liquidity_delta, 2);
        assert!(position::liquidity(&position) == liquidity_delta, 3);
        
        // Verify position info was updated
        let position_id = object::id(&position);
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        assert!(position::info_liquidity(position_info) == liquidity_delta, 4);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test decrease_liquidity method
    /// Verifies that:
    /// 1. Liquidity can be decreased for a position
    /// 2. Position info is updated correctly
    fun test_decrease_liquidity() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let mut position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Initial liquidity should be 0
        assert!(position::liquidity(&position) == 0, 1);
        
        // Increase liquidity first
        let initial_liquidity = 1000;
        let fee_growth_a = 0;
        let fee_growth_b = 0;
        let points_growth = 0;
        let mut rewards_growth = vector::empty<u128>();
        let fullsail_growth = 0;
        
        position::increase_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            initial_liquidity,
            fee_growth_a,
            fee_growth_b,
            points_growth,
            rewards_growth,
            fullsail_growth
        );
        
        // Now decrease liquidity
        let liquidity_decrease = 500;
        let new_liquidity = position::decrease_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            liquidity_decrease,
            fee_growth_a,
            fee_growth_b,
            points_growth,
            rewards_growth,
            fullsail_growth
        );
        
        // Verify liquidity was decreased
        assert!(new_liquidity == initial_liquidity - liquidity_decrease, 2);
        assert!(position::liquidity(&position) == initial_liquidity - liquidity_decrease, 3);
        
        // Verify position info was updated
        let position_id = object::id(&position);
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        assert!(position::info_liquidity(position_info) == initial_liquidity - liquidity_decrease, 4);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test decrease_liquidity method with zero decrease
    /// Verifies that:
    /// 1. Decreasing liquidity by 0 returns the same liquidity value
    /// 2. Position info remains unchanged
    fun test_decrease_liquidity_zero() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let mut position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Initial liquidity should be 0
        assert!(position::liquidity(&position) == 0, 1);
        
        // Increase liquidity first
        let initial_liquidity = 1000;
        let fee_growth_a = 0;
        let fee_growth_b = 0;
        let points_growth = 0;
        let mut rewards_growth = vector::empty<u128>();
        let fullsail_growth = 0;
        
        position::increase_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            initial_liquidity,
            fee_growth_a,
            fee_growth_b,
            points_growth,
            rewards_growth,
            fullsail_growth
        );
        
        // Now decrease liquidity by 0
        let liquidity_decrease = 0;
        let new_liquidity = position::decrease_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            liquidity_decrease,
            fee_growth_a,
            fee_growth_b,
            points_growth,
            rewards_growth,
            fullsail_growth
        );
        
        // Verify liquidity remains the same
        assert!(new_liquidity == initial_liquidity, 2);
        assert!(position::liquidity(&position) == initial_liquidity, 3);
        
        // Verify position info was not changed
        let position_id = object::id(&position);
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        assert!(position::info_liquidity(position_info) == initial_liquidity, 4);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test decrease_liquidity method with full decrease
    /// Verifies that:
    /// 1. Decreasing liquidity by the full amount returns 0
    /// 2. Position becomes empty after full decrease
    fun test_decrease_liquidity_full() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let mut position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Initial liquidity should be 0
        assert!(position::liquidity(&position) == 0, 1);
        
        // Increase liquidity first
        let initial_liquidity = 1000;
        let fee_growth_a = 0;
        let fee_growth_b = 0;
        let points_growth = 0;
        let mut rewards_growth = vector::empty<u128>();
        let fullsail_growth = 0;
        
        position::increase_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            initial_liquidity,
            fee_growth_a,
            fee_growth_b,
            points_growth,
            rewards_growth,
            fullsail_growth
        );
        
        // Now decrease liquidity by the full amount
        let liquidity_decrease = initial_liquidity;
        let new_liquidity = position::decrease_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            liquidity_decrease,
            fee_growth_a,
            fee_growth_b,
            points_growth,
            rewards_growth,
            fullsail_growth
        );
        
        // Verify liquidity is now 0
        assert!(new_liquidity == 0, 2);
        assert!(position::liquidity(&position) == 0, 3);
        
        // Verify position is empty
        let position_id = object::id(&position);
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        assert!(position::is_empty(position_info), 4);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test decrease_liquidity method with partial decrease and fees
    /// Verifies that:
    /// 1. Decreasing liquidity by a partial amount updates liquidity correctly
    /// 2. Fees are updated correctly during decrease
    fun test_decrease_liquidity_with_fees() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let mut position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Initial liquidity should be 0
        assert!(position::liquidity(&position) == 0, 1);
        
        // Increase liquidity first
        let initial_liquidity = 1000;
        let fee_growth_a = 0;
        let fee_growth_b = 0;
        let points_growth = 0;
        let mut rewards_growth = vector::empty<u128>();
        let fullsail_growth = 0;
        
        position::increase_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            initial_liquidity,
            fee_growth_a,
            fee_growth_b,
            points_growth,
            rewards_growth,
            fullsail_growth
        );
        
        // Update fees to simulate some fee growth
        let fee_growth_a_updated = 1000000;
        let fee_growth_b_updated = 2000000;
        
        // First update fees to accumulate some fees
        let (fee_owned_a_before, fee_owned_b_before) = position::update_fee(
            &mut test_manager.position_manager,
            object::id(&position),
            fee_growth_a_updated,
            fee_growth_b_updated
        );
        
        
        // Now decrease liquidity by a partial amount
        let liquidity_decrease = 500;
        let new_liquidity = position::decrease_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            liquidity_decrease,
            fee_growth_a_updated,
            fee_growth_b_updated,
            points_growth,
            rewards_growth,
            fullsail_growth
        );
        
        // Verify liquidity was decreased
        assert!(new_liquidity == initial_liquidity - liquidity_decrease, 4);
        assert!(position::liquidity(&position) == initial_liquidity - liquidity_decrease, 5);
        
        // Verify position info was updated
        let position_id = object::id(&position);
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        assert!(position::info_liquidity(position_info) == initial_liquidity - liquidity_decrease, 6);
        
        // Verify fees were updated - they should be proportional to the remaining liquidity
        let (fee_owned_a, fee_owned_b) = position::info_fee_owned(position_info);
        
        
        // Verify that the fee growth values were updated
        let (fee_growth_a_inside, fee_growth_b_inside) = position::info_fee_growth_inside(position_info);
        assert!(fee_growth_a_inside == fee_growth_a_updated, 9);
        assert!(fee_growth_b_inside == fee_growth_b_updated, 10);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test decrease_liquidity method with partial decrease and rewards
    /// Verifies that:
    /// 1. Decreasing liquidity by a partial amount updates liquidity correctly
    /// 2. Rewards are updated correctly during decrease
    fun test_decrease_liquidity_with_rewards() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let mut position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Initial liquidity should be 0
        assert!(position::liquidity(&position) == 0, 1);
        
        // Increase liquidity first
        let initial_liquidity = 1000;
        let fee_growth_a = 0;
        let fee_growth_b = 0;
        let points_growth = 0;
        let mut rewards_growth = vector::empty<u128>();
        let fullsail_growth = 0;
        
        position::increase_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            initial_liquidity,
            fee_growth_a,
            fee_growth_b,
            points_growth,
            rewards_growth,
            fullsail_growth
        );
        
        // Update rewards to simulate some reward growth
        let mut rewards_growth_updated = vector::empty<u128>();
        vector::push_back(&mut rewards_growth_updated, 100);
        
        position::update_rewards(
            &mut test_manager.position_manager,
            object::id(&position),
            rewards_growth_updated
        );
        
        // Now decrease liquidity by a partial amount
        let liquidity_decrease = 500;
        let new_liquidity = position::decrease_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            liquidity_decrease,
            fee_growth_a,
            fee_growth_b,
            points_growth,
            rewards_growth_updated,
            fullsail_growth
        );
        
        // Verify liquidity was decreased
        assert!(new_liquidity == initial_liquidity - liquidity_decrease, 2);
        assert!(position::liquidity(&position) == initial_liquidity - liquidity_decrease, 3);
        
        // Verify position info was updated
        let position_id = object::id(&position);
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        assert!(position::info_liquidity(position_info) == initial_liquidity - liquidity_decrease, 4);
        
        // Verify rewards were updated
        let rewards = position::info_rewards(position_info);
        assert!(&rewards.length() == 1, 5);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test decrease_liquidity method with partial decrease and fullsail growth
    /// Verifies that:
    /// 1. Decreasing liquidity by a partial amount updates liquidity correctly
    /// 2. Fullsail growth is updated correctly during decrease
    fun test_decrease_liquidity_with_fullsail() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let mut position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Initial liquidity should be 0
        assert!(position::liquidity(&position) == 0, 1);
        
        // Increase liquidity first
        let initial_liquidity = 1000;
        let fee_growth_a = 0;
        let fee_growth_b = 0;
        let points_growth = 0;
        let mut rewards_growth = vector::empty<u128>();
        let fullsail_growth = 0;
        
        position::increase_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            initial_liquidity,
            fee_growth_a,
            fee_growth_b,
            points_growth,
            rewards_growth,
            fullsail_growth
        );
        
        // Update fullsail growth
        let fullsail_growth_updated = 100;
        
        // Now decrease liquidity by a partial amount
        let liquidity_decrease = 500;
        let new_liquidity = position::decrease_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            liquidity_decrease,
            fee_growth_a,
            fee_growth_b,
            points_growth,
            rewards_growth,
            fullsail_growth_updated
        );
        
        // Verify liquidity was decreased
        assert!(new_liquidity == initial_liquidity - liquidity_decrease, 2);
        assert!(position::liquidity(&position) == initial_liquidity - liquidity_decrease, 3);
        
        // Verify position info was updated
        let position_id = object::id(&position);
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        assert!(position::info_liquidity(position_info) == initial_liquidity - liquidity_decrease, 4);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test decrease_liquidity method with partial decrease and points growth
    /// Verifies that:
    /// 1. Decreasing liquidity by a partial amount updates liquidity correctly
    /// 2. Points growth is updated correctly during decrease
    fun test_decrease_liquidity_with_points() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let mut position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Initial liquidity should be 0
        assert!(position::liquidity(&position) == 0, 1);
        
        // Increase liquidity first
        let initial_liquidity = 1000;
        let fee_growth_a = 0;
        let fee_growth_b = 0;
        let points_growth = 0;
        let mut rewards_growth = vector::empty<u128>();
        let fullsail_growth = 0;
        
        position::increase_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            initial_liquidity,
            fee_growth_a,
            fee_growth_b,
            points_growth,
            rewards_growth,
            fullsail_growth
        );
        
        // Update points growth
        let points_growth_updated = 100;
        
        // Now decrease liquidity by a partial amount
        let liquidity_decrease = 500;
        let new_liquidity = position::decrease_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            liquidity_decrease,
            fee_growth_a,
            fee_growth_b,
            points_growth_updated,
            rewards_growth,
            fullsail_growth
        );
        
        // Verify liquidity was decreased
        assert!(new_liquidity == initial_liquidity - liquidity_decrease, 2);
        assert!(position::liquidity(&position) == initial_liquidity - liquidity_decrease, 3);
        
        // Verify position info was updated
        let position_id = object::id(&position);
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        assert!(position::info_liquidity(position_info) == initial_liquidity - liquidity_decrease, 4);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test decrease_liquidity method with error when decreasing more than available
    /// Verifies that:
    /// 1. Attempting to decrease more liquidity than available results in an error
    #[expected_failure(abort_code = 9)]
    fun test_decrease_liquidity_error_more_than_available() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);
        
        // Open a new position
        let mut position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );
        
        // Get position ID
        let position_id = object::id(&position);
        
        // Add some initial liquidity
        let initial_liquidity = 1000;
        let _ = position::increase_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            initial_liquidity,
            0, // fee_growth_a
            0, // fee_growth_b
            0, // points_growth
            vector::empty<u128>(), // rewards_growth
            0 // fullsail_growth
        );
        
        // Try to decrease more liquidity than available
        let liquidity_decrease = initial_liquidity + 1; // More than available
        
        // This should abort with error code 9 (insufficient liquidity)
        let _ = position::decrease_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            liquidity_decrease,
            0, // fee_growth_a
            0, // fee_growth_b
            0, // points_growth
            vector::empty<u128>(), // rewards_growth
            0 // fullsail_growth
        );
        
        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }


    #[test]
    /// Test borrow_mut_position_info method
    /// Verifies that:
    /// 1. Mutable reference to position info can be obtained
    /// 2. Position info can be modified through the reference
    fun test_borrow_mut_position_info() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Get position ID
        let position_id = object::id(&position);
        
        // Verify position exists in the manager
        assert!(position::is_position_exist(&test_manager.position_manager, position_id), 1);
        
        // Get reference to position info using the public function
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        
        // Verify position info properties
        assert!(position::info_position_id(position_info) == position_id, 2);
        assert!(position::info_liquidity(position_info) == 0, 3);
        
        let (info_tick_lower, info_tick_upper) = position::info_tick_range(position_info);
        assert!(i32::eq(info_tick_lower, tick_lower), 4);
        assert!(i32::eq(info_tick_upper, tick_upper), 5);
        
        // Verify fee growth is initialized to 0
        let (fee_growth_a, fee_growth_b) = position::info_fee_growth_inside(position_info);
        assert!(fee_growth_a == 0, 6);
        assert!(fee_growth_b == 0, 7);
        
        // Verify fee owned is initialized to 0
        let (fee_owned_a, fee_owned_b) = position::info_fee_owned(position_info);
        assert!(fee_owned_a == 0, 8);
        assert!(fee_owned_b == 0, 9);
        
        // Verify points are initialized to 0
        assert!(position::info_points_owned(position_info) == 0, 10);
        assert!(position::info_points_growth_inside(position_info) == 0, 11);
        
        // Verify rewards are initialized to empty
        let rewards = position::info_rewards(position_info);
        assert!(vector::length(rewards) == 0, 12);
        
        // Verify fullsail distribution is initialized
        assert!(!position::is_staked(position_info), 13);
        assert!(position::info_fullsail_distribution_owned(position_info) == 0, 14);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test check_position_tick_range with valid tick range
    /// Verifies that:
    /// 1. Valid tick range passes validation
    fun test_check_position_tick_range_valid() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Define valid tick range with tick spacing of 1
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);
        let tick_spacing = 1;
        
        // This should not abort
        check_position_tick_range(tick_lower, tick_upper, tick_spacing);
        
        test_scenario::end(scenario);
    }
    
    #[test]
    /// Test check_position_tick_range with lower tick greater than upper tick
    /// Verifies that:
    /// 1. Invalid tick range (lower > upper) fails validation
    #[expected_failure(abort_code = 5)]
    fun test_check_position_tick_range_lower_greater_upper() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Define invalid tick range (lower > upper)
        let tick_lower = i32::from(10);
        let tick_upper = i32::from(0);
        let tick_spacing = 1;
        
        // This should abort with error code 5
        check_position_tick_range(tick_lower, tick_upper, tick_spacing);
        
        test_scenario::end(scenario);
    }
    
    #[test]
    /// Test check_position_tick_range with lower tick less than minimum allowed
    /// Verifies that:
    /// 1. Invalid tick range (lower < min_tick) fails validation
    #[expected_failure(abort_code = 5)]
    fun test_check_position_tick_range_lower_less_than_min() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Define invalid tick range (lower < min_tick)
        // The minimum tick value in clmm_pool::tick_math::min_tick() is -443636
        // Using a value of -443637, which is less than the minimum
        let tick_lower = integer_mate::i32::neg_from(443637);
        let tick_upper = i32::from(10);
        let tick_spacing = 1;
        
        // This test should fail because tick_lower < min_tick()
        check_position_tick_range(tick_lower, tick_upper, tick_spacing);
        
        test_scenario::end(scenario);
    }
    
    #[test]
    /// Test check_position_tick_range with upper tick greater than maximum allowed
    /// Verifies that:
    /// 1. Invalid tick range (upper > max_tick) fails validation
    #[expected_failure(abort_code = 5)]
    fun test_check_position_tick_range_upper_greater_than_max() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Define invalid tick range (upper > max_tick)
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(1000000);
        let tick_spacing = 1;
        
        // This should abort with error code 5
        check_position_tick_range(tick_lower, tick_upper, tick_spacing);
        
        test_scenario::end(scenario);
    }
    
    #[test]
    /// Test check_position_tick_range with lower tick not aligned with tick spacing
    /// Verifies that:
    /// 1. Invalid tick range (lower not aligned with tick spacing) fails validation
    #[expected_failure(abort_code = 5)]
    fun test_check_position_tick_range_lower_not_aligned() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Define invalid tick range (lower not aligned with tick spacing)
        let tick_lower = i32::from(1);
        let tick_upper = i32::from(10);
        let tick_spacing = 2;
        
        // This should abort with error code 5
        check_position_tick_range(tick_lower, tick_upper, tick_spacing);
        
        test_scenario::end(scenario);
    }
    
    #[test]
    /// Test check_position_tick_range with upper tick not aligned with tick spacing
    /// Verifies that:
    /// 1. Invalid tick range (upper not aligned with tick spacing) fails validation
    #[expected_failure(abort_code = 5)]
    fun test_check_position_tick_range_upper_not_aligned() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Define invalid tick range (upper not aligned with tick spacing)
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(11);
        let tick_spacing = 2;
        
        // This should abort with error code 5
        check_position_tick_range(tick_lower, tick_upper, tick_spacing);
        
        test_scenario::end(scenario);
    }
    
    #[test]
    /// Test check_position_tick_range with different tick spacing values
    /// Verifies that:
    /// 1. Different tick spacing values work correctly with aligned ticks
    fun test_check_position_tick_range_different_spacing() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Test with tick spacing of 2
        let tick_lower_2 = i32::from(0);
        let tick_upper_2 = i32::from(10);
        let tick_spacing_2 = 2;
        check_position_tick_range(tick_lower_2, tick_upper_2, tick_spacing_2);
        
        // Test with tick spacing of 5
        let tick_lower_5 = i32::from(0);
        let tick_upper_5 = i32::from(10);
        let tick_spacing_5 = 5;
        check_position_tick_range(tick_lower_5, tick_upper_5, tick_spacing_5);
        
        // Test with tick spacing of 10
        let tick_lower_10 = i32::from(0);
        let tick_upper_10 = i32::from(20);
        let tick_spacing_10 = 10;
        check_position_tick_range(tick_lower_10, tick_upper_10, tick_spacing_10);
        
        test_scenario::end(scenario);
    }

    #[test]
    /// Test fetch_positions with empty position_ids
    /// Verifies that:
    /// 1. When position_ids is empty, fetch_positions starts from the first position
    /// 2. Returns up to the specified limit
    fun test_fetch_positions_empty_ids() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Create multiple positions
        let mut position_ids = vector::empty<object::ID>();
        
        // Create 5 positions
        let mut i = 0;
        while (i < 5) {
            let position = position::open_position<type_name::TypeName, type_name::TypeName>(
                &mut test_manager.position_manager,
                pool_id,
                pool_index,
                pool_url,
                tick_lower,
                tick_upper,
                scenario.ctx()
            );
            
            vector::push_back(&mut position_ids, object::id(&position));
            transfer::public_transfer(position, admin);
            
            i = i + 1;
        };
        
        // Test fetching positions with empty position_ids
        let empty_ids = vector::empty<object::ID>();
        let fetched_positions = position::fetch_positions(&test_manager.position_manager, empty_ids, 3);
        
        // Verify that 3 positions were fetched
        assert!(vector::length(&fetched_positions) == 3, 1);
        
        // Verify that the first position in the fetched list is the first position we created
        let first_position_id = position::info_position_id(vector::borrow(&fetched_positions, 0));
        assert!(first_position_id == *vector::borrow(&position_ids, 0), 2);
        
        // Verify that the second position in the fetched list is the second position we created
        let second_position_id = position::info_position_id(vector::borrow(&fetched_positions, 1));
        assert!(second_position_id == *vector::borrow(&position_ids, 1), 3);
        
        // Verify that the third position in the fetched list is the third position we created
        let third_position_id = position::info_position_id(vector::borrow(&fetched_positions, 2));
        assert!(third_position_id == *vector::borrow(&position_ids, 2), 4);
        
        // Test fetching positions with a limit greater than the number of positions
        let fetched_all_positions = position::fetch_positions(&test_manager.position_manager, empty_ids, 10);
        
        // Verify that all 5 positions were fetched
        assert!(vector::length(&fetched_all_positions) == 5, 5);
        
        // Transfer manager
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }
    
    #[test]
    /// Test fetch_positions with specific position_ids
    /// Verifies that:
    /// 1. When position_ids is provided, fetch_positions starts from the first ID in the vector
    /// 2. Returns up to the specified limit
    fun test_fetch_positions_with_ids() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Create multiple positions
        let mut position_ids = vector::empty<object::ID>();
        
        // Create 5 positions
        let mut i = 0;
        while (i < 5) {
            let position = position::open_position<type_name::TypeName, type_name::TypeName>(
                &mut test_manager.position_manager,
                pool_id,
                pool_index,
                pool_url,
                tick_lower,
                tick_upper,
                scenario.ctx()
            );
            
            vector::push_back(&mut position_ids, object::id(&position));
            transfer::public_transfer(position, admin);
            
            i = i + 1;
        };
        
        // Create a vector with specific position IDs to start from (e.g., the third position)
        let mut specific_ids = vector::empty<object::ID>();
        vector::push_back(&mut specific_ids, *vector::borrow(&position_ids, 2));
        
        // Test fetching positions with specific position_ids
        let fetched_positions = position::fetch_positions(&test_manager.position_manager, specific_ids, 2);
        
        // Verify that 2 positions were fetched
        assert!(vector::length(&fetched_positions) == 2, 1);
        
        // Verify that the first position in the fetched list is the third position we created
        let first_position_id = position::info_position_id(vector::borrow(&fetched_positions, 0));
        assert!(first_position_id == *vector::borrow(&position_ids, 2), 2);
        
        // Verify that the second position in the fetched list is the fourth position we created
        let second_position_id = position::info_position_id(vector::borrow(&fetched_positions, 1));
        assert!(second_position_id == *vector::borrow(&position_ids, 3), 3);
        
        // Test fetching positions with a limit greater than the remaining positions
        let fetched_all_positions = position::fetch_positions(&test_manager.position_manager, specific_ids, 10);
        
        // Verify that all 3 remaining positions were fetched
        assert!(vector::length(&fetched_all_positions) == 3, 4);
        
        // Transfer manager
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }
    
    #[test]
    /// Test fetch_positions with non-existent position ID
    /// Verifies that:
    /// 1. When a non-existent position ID is provided, fetch_positions returns an empty vector
    fun test_fetch_positions_non_existent_id() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a non-existent position ID
        let non_existent_id = object::id_from_address(@0x2);
        
        // Create a vector with the non-existent position ID
        let mut specific_ids = vector::empty<object::ID>();
        vector::push_back(&mut specific_ids, non_existent_id);
        
        // Test fetching positions with a non-existent position ID
        let fetched_positions = position::fetch_positions(&test_manager.position_manager, specific_ids, 5);
        
        // Verify that no positions were fetched
        assert!(vector::length(&fetched_positions) == 0, 1);
        
        // Transfer manager
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }
    
    #[test]
    /// Test fetch_positions with multiple position IDs
    /// Verifies that:
    /// 1. When multiple position IDs are provided, fetch_positions starts from the first ID in the vector
    /// 2. Returns up to the specified limit
    fun test_fetch_positions_multiple_ids() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Create multiple positions
        let mut position_ids = vector::empty<object::ID>();
        
        // Create 5 positions
        let mut i = 0;
        while (i < 5) {
            let position = position::open_position<type_name::TypeName, type_name::TypeName>(
                &mut test_manager.position_manager,
                pool_id,
                pool_index,
                pool_url,
                tick_lower,
                tick_upper,
                scenario.ctx()
            );
            
            vector::push_back(&mut position_ids, object::id(&position));
            transfer::public_transfer(position, admin);
            
            i = i + 1;
        };
        
        // Create a vector with multiple position IDs to start from (e.g., the second and fourth positions)
        let mut specific_ids = vector::empty<object::ID>();
        vector::push_back(&mut specific_ids, *vector::borrow(&position_ids, 1));
        vector::push_back(&mut specific_ids, *vector::borrow(&position_ids, 3));
        
        // Test fetching positions with multiple position IDs
        let fetched_positions = position::fetch_positions(&test_manager.position_manager, specific_ids, 2);
        
        // Verify that 2 positions were fetched
        assert!(vector::length(&fetched_positions) == 2, 1);
        
        // Verify that the first position in the fetched list is the second position we created
        let first_position_id = position::info_position_id(vector::borrow(&fetched_positions, 0));
        assert!(first_position_id == *vector::borrow(&position_ids, 1), 2);
        
        // Verify that the second position in the fetched list is the third position we created
        let second_position_id = position::info_position_id(vector::borrow(&fetched_positions, 1));
        assert!(second_position_id == *vector::borrow(&position_ids, 2), 3);
        
        // Transfer manager
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test mark_position_staked function
    /// Verifies that:
    /// 1. Position can be marked as staked
    /// 2. Position can be marked as unstaked
    /// 3. Event is emitted when staking status changes
    fun test_mark_position_staked() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        let position_id = object::id(&position);

        // Mark position as staked
        position::mark_position_staked(&mut test_manager.position_manager, position_id, true);
        
        // Verify position is staked
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        assert!(position::is_staked(position_info), 1);

        // Mark position as unstaked
        position::mark_position_staked(&mut test_manager.position_manager, position_id, false);
        
        // Verify position is not staked
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        assert!(!position::is_staked(position_info), 6);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 6)]
    fun test_mark_position_staked_nonexistent() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a non-existent position ID
        let fake_position_id = object::id_from_address(@0x2);
        
        // Try to mark non-existent position as staked (should fail)
        position::mark_position_staked(&mut test_manager.position_manager, fake_position_id, true);

        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 11)]
    fun test_mark_position_staked_same_status() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        let position_id = object::id(&position);

        // Mark position as staked
        position::mark_position_staked(&mut test_manager.position_manager, position_id, true);
        
        // Try to mark position as staked again (should fail)
        position::mark_position_staked(&mut test_manager.position_manager, position_id, true);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test new_position_name function
    /// Verifies that:
    /// 1. Position name is correctly formatted with pool and position indices
    /// 2. Different pool and position indices produce different names
    fun test_new_position_name() {
        // Test with pool_index = 1, position_index = 1
        let name1 = position::test_new_position_name(1, 1);
        assert!(string::utf8(b"Fullsail position:1-1") == name1, 1);
        
        // Test with pool_index = 2, position_index = 3
        let name2 = position::test_new_position_name(2, 3);
        assert!(string::utf8(b"Fullsail position:2-3") == name2, 2);
        
        // Test with pool_index = 0, position_index = 0
        let name3 = position::test_new_position_name(0, 0);
        assert!(string::utf8(b"Fullsail position:0-0") == name3, 3);
        
        // Test with large indices
        let name4 = position::test_new_position_name(1000, 5000);
        assert!(string::utf8(b"Fullsail position:1000-5000") == name4, 4);
        
        // Verify that different indices produce different names
        assert!(name1 != name2, 5);
        assert!(name1 != name3, 6);
        assert!(name1 != name4, 7);
        assert!(name2 != name3, 8);
        assert!(name2 != name4, 9);
        assert!(name3 != name4, 10);
    }

    #[test]
    /// Test reset_fee function
    /// Verifies that:
    /// 1. Unclaimed fees for both tokens are reset to zero
    /// 2. Function returns tuple with both values set to zero
    fun test_reset_fee() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        let position_id = object::id(&position);
        
        // Initially, fees should be zero
        let (fee_owned_a, fee_owned_b) = position::info_fee_owned(position::borrow_position_info(&test_manager.position_manager, position_id));
        assert!(fee_owned_a == 0, 1);
        assert!(fee_owned_b == 0, 2);
        
        // Update fees to non-zero values using test function
        position::test_update_fees(&mut test_manager.position_manager, position_id, 100, 200);
        
        // Verify fees are updated
        let (fee_owned_a, fee_owned_b) = position::info_fee_owned(position::borrow_position_info(&test_manager.position_manager, position_id));
        assert!(fee_owned_a == 100, 3);
        assert!(fee_owned_b == 200, 4);
        
        // Reset fees
        let (reset_fee_a, reset_fee_b) = position::reset_fee(&mut test_manager.position_manager, position_id);
        
        // Verify reset fees are zero
        assert!(reset_fee_a == 0, 5);
        assert!(reset_fee_b == 0, 6);
        
        // Verify position fees are reset to zero
        let (fee_owned_a, fee_owned_b) = position::info_fee_owned(position::borrow_position_info(&test_manager.position_manager, position_id));
        assert!(fee_owned_a == 0, 7);
        assert!(fee_owned_b == 0, 8);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test reset_rewarder function
    /// Verifies that:
    /// 1. Reward amount is reset to 0 for a valid position and reward index
    /// 2. Returns 0 after reset
    /// 3. Aborts with invalid reward index
    fun test_reset_rewarder() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);
        // Create position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };
        
        test_scenario::next_tx(&mut scenario, admin);
        
        // Create a position with some rewards
        let position = position::open_position<std::type_name::TypeName, std::type_name::TypeName>(
            &mut test_manager.position_manager,
            object::id_from_address(admin),
            1,
            std::string::utf8(b"https://fullsailfinance.io/pool/1"),
            integer_mate::i32::neg_from(10),
            i32::from(10),
            test_scenario::ctx(&mut scenario)
        );
        let position_id = object::id(&position);
        transfer::public_transfer(position, admin);
        test_scenario::next_tx(&mut scenario, admin);
        
        // Add a reward to the position using update_rewards
        let mut rewards_growth = std::vector::empty<u128>();
        std::vector::push_back(&mut rewards_growth, 100);
        let _rewards = position::update_rewards(&mut test_manager.position_manager, position_id, rewards_growth);
        
        // Test reset_rewarder
        let reset_amount = position::reset_rewarder(&mut test_manager.position_manager, position_id, 0);
        
        // Verify reward was reset by checking the reward amount
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        let rewards = position::info_rewards(position_info);
        assert!(std::vector::length(rewards) == 1, 1);
        let reward = std::vector::borrow(rewards, 0);
        assert!(position::reward_amount_owned(reward) == 0, 2);

        transfer::public_transfer(test_manager, admin);
        
        test_scenario::end(scenario);
    }

    #[test]
    /// Test rewards_amount_owned function
    /// Verifies that:
    /// 1. Returns empty vector for position with no rewards
    /// 2. Returns correct amounts for position with rewards
    fun test_rewards_amount_owned() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a position
        let position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            object::id_from_address(admin),
            1,
            std::string::utf8(b"https://fullsailfinance.io/pool/1"),
            integer_mate::i32::neg_from(10),
            i32::from(10),
            test_scenario::ctx(&mut scenario)
        );
        let position_id = object::id(&position);
        transfer::public_transfer(position, admin);
        test_scenario::next_tx(&mut scenario, admin);

        // Test empty rewards
        let rewards = position::rewards_amount_owned(&test_manager.position_manager, position_id);
        assert!(std::vector::length(&rewards) == 0, 1);

        // Add rewards to the position
        let mut rewards_growth = std::vector::empty<u128>();
        std::vector::push_back(&mut rewards_growth, 100);
        std::vector::push_back(&mut rewards_growth, 200);
        let _rewards = position::update_rewards(&mut test_manager.position_manager, position_id, rewards_growth);

        // Test rewards with amounts
        let rewards = position::rewards_amount_owned(&test_manager.position_manager, position_id);
        assert!(std::vector::length(&rewards) == 2, 2);
        assert!(*std::vector::borrow(&rewards, 0) == 0, 3);
        assert!(*std::vector::borrow(&rewards, 1) == 0, 4);

        transfer::public_transfer(test_manager, admin);

        test_scenario::end(scenario);
    }

    #[test]
    /// Test url function
    /// Verifies that:
    /// 1. Returns the correct URL for a position
    fun test_url() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };
        test_scenario::next_tx(&mut scenario, admin);

        // Create a position with a specific URL
        let pool_url = string::utf8(b"https://example.com/pool");
        let position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
             object::id_from_address(admin),
            1,
            std::string::utf8(b"https://fullsailfinance.io/pool/1"),
            integer_mate::i32::neg_from(10),
            i32::from(10),
            test_scenario::ctx(&mut scenario)
        );
        
        // Test url function
        let url = url(&position);
        assert!(string::utf8(b"https://fullsailfinance.io/pool/1") == url, 1);

        test_scenario::next_tx(&mut scenario, admin);
        transfer::public_transfer(test_manager, admin);
        transfer::public_transfer(position, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test update_and_reset_fee function
    /// Verifies that:
    /// 1. Updates fee growth correctly
    /// 2. Resets fee owned to zero
    /// 3. Returns the reset fee amounts
    fun test_update_and_reset_fee() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Create a position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };
        test_scenario::next_tx(&mut scenario, admin);
        // Create a position with initial liquidity
        let position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
             object::id_from_address(admin),
            1,
            std::string::utf8(b"https://fullsailfinance.io/pool/1"),
            integer_mate::i32::neg_from(10),
            i32::from(10),
            test_scenario::ctx(&mut scenario)
        );
        let position_id = object::id(&position);
        transfer::public_transfer(position, admin);

        // Set initial fees using test function
        test_update_fees(&mut test_manager.position_manager, position_id, 100, 200);

        // Verify initial fees
        let (fee_owned_a, fee_owned_b) = position::info_fee_owned(position::borrow_position_info(&test_manager.position_manager, position_id));
        assert!(fee_owned_a == 100, 1);
        assert!(fee_owned_b == 200, 2);

        // Update and reset fees
        let (reset_fee_a, reset_fee_b) = position::update_and_reset_fee(&mut test_manager.position_manager, position_id, 1000, 2000);

        // Verify fees are reset to zero
        assert!(reset_fee_a == 0, 3);
        assert!(reset_fee_b == 0, 4);

        // Verify position fees are reset to zero
        let (fee_owned_a, fee_owned_b) = position::info_fee_owned(position::borrow_position_info(&test_manager.position_manager, position_id));
        assert!(fee_owned_a == 0, 5);
        assert!(fee_owned_b == 0, 6);

        // Verify fee growth is updated
        let (fee_growth_a, fee_growth_b) = position::info_fee_growth_inside(position::borrow_position_info(&test_manager.position_manager, position_id));
        assert!(fee_growth_a == 1000, 7);
        assert!(fee_growth_b == 2000, 8);

        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test update_and_reset_fullsail_distribution function
    /// Verifies that:
    /// 1. Updates fullsail distribution growth correctly using Q64.64 fixed-point format
    /// 2. Resets fullsail distribution owned to zero
    /// 3. Returns the reset fullsail distribution amount
    /// 
    /// The test uses the following Q64.64 values:
    /// - Initial growth: 1.0 (1 << 64)
    /// - Second growth: 2.0 (2 << 64)
    /// - Final growth: 3.0 (3 << 64)
    /// 
    /// The difference between growth values (1.0) is multiplied by the position's liquidity
    /// and right-shifted by 64 bits to calculate the accumulated rewards.
    fun test_update_and_reset_fullsail_distribution() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a position
        let mut position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            object::id_from_address(admin),
            1,
            std::string::utf8(b"https://fullsailfinance.io/pool/1"),
            integer_mate::i32::neg_from(10),
            i32::from(10),
            test_scenario::ctx(&mut scenario)
        );
        let position_id = object::id(&position);

        // Add liquidity to position
        position::increase_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            1000000000, // 1 billion
            0,
            0,
            0,
            std::vector::empty<u128>(),
            0
        );

        // First update to set initial growth
        let _initial_fullsail = position::update_fullsail_distribution(&mut test_manager.position_manager, position_id, 1 << 64); // 1.0 in Q64.64

        // Second update to accumulate rewards
        let _updated_fullsail = position::update_fullsail_distribution(&mut test_manager.position_manager, position_id, 2 << 64); // 2.0 in Q64.64

        // Verify fullsail distribution is greater than zero
        let fullsail_owned = position::info_fullsail_distribution_owned(position::borrow_position_info(&test_manager.position_manager, position_id));
        assert!(fullsail_owned > 0, 1);

        // Update and reset fullsail distribution
        let reset_fullsail = position::update_and_reset_fullsail_distribution(&mut test_manager.position_manager, position_id, 3 << 64); // 3.0 in Q64.64

        // Verify fullsail distribution is reset to zero
        assert!(reset_fullsail == 0, 2);

        // Verify position fullsail distribution is reset to zero
        let fullsail_owned = position::info_fullsail_distribution_owned(position::borrow_position_info(&test_manager.position_manager, position_id));
        assert!(fullsail_owned == 0, 3);

        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test update_and_reset_rewards function
    /// Verifies that:
    /// 1. Updates rewards growth correctly using Q64.64 fixed-point format
    /// 2. Resets specified reward to zero
    /// 3. Returns the reset reward amount
    /// 
    /// The test uses the following Q64.64 values:
    /// - Initial growth: 1.0 (1 << 64)
    /// - Second growth: 2.0 (2 << 64)
    /// - Final growth: 3.0 (3 << 64)
    /// 
    /// The difference between growth values (1.0) is multiplied by the position's liquidity
    /// and right-shifted by 64 bits to calculate the accumulated rewards.
    fun test_update_and_reset_rewards() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a position
        let mut position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            object::id_from_address(admin),
            1,
            std::string::utf8(b"https://fullsailfinance.io/pool/1"),
            integer_mate::i32::neg_from(10),
            i32::from(10),
            test_scenario::ctx(&mut scenario)
        );
        let position_id = object::id(&position);

        // Add liquidity to position
        position::increase_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            1000000000, // 1 billion
            0,
            0,
            0,
            std::vector::empty<u128>(),
            0
        );

        // Create rewards growth vector
        let mut rewards_growth = std::vector::empty<u128>();
        std::vector::push_back<u128>(&mut rewards_growth, 1 << 64); // 1.0 in Q64.64

        // First update to set initial growth
        let _initial_rewards = position::update_rewards(&mut test_manager.position_manager, position_id, rewards_growth);

        // Update rewards growth
        std::vector::pop_back<u128>(&mut rewards_growth);
        std::vector::push_back<u128>(&mut rewards_growth, 2 << 64); // 2.0 in Q64.64

        // Second update to accumulate rewards
        let _updated_rewards = position::update_rewards(&mut test_manager.position_manager, position_id, rewards_growth);

        // Verify rewards are greater than zero
        let rewards = position::info_rewards(position::borrow_position_info(&test_manager.position_manager, position_id));
        assert!(position::reward_amount_owned(std::vector::borrow<PositionReward>(rewards, 0)) > 0, 1);

        // Update rewards growth again
        std::vector::pop_back<u128>(&mut rewards_growth);
        std::vector::push_back<u128>(&mut rewards_growth, 3 << 64); // 3.0 in Q64.64

        // Update and reset reward
        let reset_reward = position::update_and_reset_rewards(&mut test_manager.position_manager, position_id, rewards_growth, 0);

        // Verify reward is reset to zero
        assert!(reset_reward == 0, 2);

        // Verify position reward is reset to zero
        let rewards = position::info_rewards(position::borrow_position_info(&test_manager.position_manager, position_id));
        assert!(position::reward_amount_owned(std::vector::borrow<PositionReward>(rewards, 0)) == 0, 3);

        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test update_points with non-zero value
    /// Verifies that:
    /// 1. Points can be updated to a non-zero value
    /// 2. info_points_owned returns the correct non-zero value
    fun test_update_points_non_zero() {
        let mut scenario = test_scenario::begin(@0x1);
        let admin = @0x1;
        scenario.next_tx(admin);

        // Create a test position manager
        let mut test_manager = TestPositionManager {
            id: sui::object::new(scenario.ctx()),
            position_manager: position::new(1, scenario.ctx())
        };

        // Create a pool ID for testing
        let pool_id = object::id_from_address(admin);
        let pool_index = 1;
        let pool_url = string::utf8(b"https://fullsailfinance.io/pool/1");
        
        // Define tick range
        let tick_lower = i32::from(0);
        let tick_upper = i32::from(10);

        // Open a new position
        let mut position = position::open_position<type_name::TypeName, type_name::TypeName>(
            &mut test_manager.position_manager,
            pool_id,
            pool_index,
            pool_url,
            tick_lower,
            tick_upper,
            scenario.ctx()
        );

        // Get position ID
        let position_id = object::id(&position);
        
        // Add some liquidity to the position
        let initial_liquidity = 1000;
        let _new_liquidity = position::increase_liquidity(
            &mut test_manager.position_manager,
            &mut position,
            initial_liquidity,
            0, // fee_growth_a
            0, // fee_growth_b
            0, // points_growth
            vector::empty<u128>(), // rewards_growth
            0  // fullsail_growth
        );

        // Update points with a non-zero growth value in Q64.64 format
        let points_growth = 1000 << 64;
        let points_owned = position::update_points(
            &mut test_manager.position_manager,
            position_id,
            points_growth
        );
        
        // Calculate expected points value
        // points_delta = (liquidity * (points_growth - points_growth_inside)) >> 64
        // points_growth_inside initially is 0
        let expected_points = integer_mate::full_math_u128::mul_shr(
            initial_liquidity,
            points_growth,
            64
        );
        
        // Verify points were updated correctly
        assert!(points_owned == expected_points, 1);
        
        // Get position info and verify points
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        assert!(position::info_points_owned(position_info) == expected_points, 2);
        assert!(position::info_points_growth_inside(position_info) == points_growth, 3);

        // Update and verify fullsail distribution with non-zero growth value in Q64.64 format
        let fullsail_growth = 2000 << 64;
        let fullsail_owned = position::update_fullsail_distribution(
            &mut test_manager.position_manager,
            position_id,
            fullsail_growth
        );

        // Calculate expected fullsail value
        let expected_fullsail = integer_mate::full_math_u128::mul_shr(
            initial_liquidity,
            fullsail_growth,
            64
        ) as u64;

        // Verify fullsail distribution is updated correctly
        let position_info = position::borrow_position_info(&test_manager.position_manager, position_id);
        assert!(position::info_fullsail_distribution_owned(position_info) == fullsail_owned, 4);
        assert!(fullsail_owned == expected_fullsail, 5);

        // Initialize some rewards
        let mut rewards_growth = vector::empty<u128>();
        vector::push_back(&mut rewards_growth, 3000 << 64); // First reward growth in Q64.64
        vector::push_back(&mut rewards_growth, 4000 << 64); // Second reward growth in Q64.64
        
        let rewards_owned = position::update_rewards(
            &mut test_manager.position_manager,
            position_id,
            rewards_growth
        );

        // Verify rewards were initialized
        let updated_rewards_count = position::inited_rewards_count(&test_manager.position_manager, position_id);
        assert!(updated_rewards_count == 2, 7); // Now we should have 2 rewards initialized
        assert!(vector::length(&rewards_owned) == 2, 8);

        // Transfer objects
        transfer::public_transfer(position, admin);
        transfer::public_transfer(test_manager, admin);
        test_scenario::end(scenario);
    }

    #[test]
    /// Test setting display fields for a position
    /// Verifies that:
    /// 1. Display fields are set correctly
    /// 2. Custom values are applied
    fun test_set_display() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        {
            clmm_pool::config::test_init(scenario.ctx());
            position::test_init(scenario.ctx());
        };

        // Create partner
        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<clmm_pool::config::GlobalConfig>();            
            // Create position manager
            let mut test_manager = TestPositionManager {
                id: sui::object::new(scenario.ctx()),
                position_manager: new(1, scenario.ctx())
            };
            
            // Create a pool ID for testing
            let pool_id = sui::object::id_from_address(admin);
            let pool_index = 1;
            let pool_url = std::string::utf8(b"https://fullsailfinance.io/pool/1");
            
            // Define tick range
            let tick_lower = integer_mate::i32::from(0);
            let tick_upper = integer_mate::i32::from(10);
            
            // Open a new position
            let position = open_position<std::type_name::TypeName, std::type_name::TypeName>(
                &mut test_manager.position_manager,
                pool_id,
                pool_index,
                pool_url,
                tick_lower,
                tick_upper,
                scenario.ctx()
            );

            // Get position ID
            let position_id = sui::object::id(&position);

            // Set custom display values
            let custom_description = std::string::utf8(b"Custom position description");
            let custom_link = std::string::utf8(b"https://app.fullsailfinance.io/custom-position");
            let custom_project_url = std::string::utf8(b"https://custom-project.io");
            let custom_creator = std::string::utf8(b"Custom Creator");

            // Get publisher from scenario
            let publisher = scenario.take_from_sender<sui::package::Publisher>();

            // Set display fields
            position::set_display(
                &global_config,
                &publisher,
                custom_description,
                custom_link,
                custom_project_url,
                custom_creator,
                scenario.ctx()
            );

            scenario.return_to_sender(publisher);
            sui::transfer::public_transfer(position, admin);
            sui::transfer::public_transfer(test_manager, admin);
            test_scenario::return_shared(global_config);
        };


        scenario.next_tx(admin);
        {
            // Get display object
            let display = scenario.take_from_sender<sui::display::Display<Position>>();

            // Verify display fields
            let display_fields = sui::display::fields(&display);

            let keys = sui::vec_map::keys(display_fields);
            let mut i = 0;
            while (i < vector::length(&keys)) {
                let key = vector::borrow(&keys, i);
                let value = sui::vec_map::get(display_fields, key);
                i = i + 1;
            };

            let custom_description = std::string::utf8(b"Custom position description");
            let custom_link = std::string::utf8(b"https://app.fullsailfinance.io/custom-position");
            let custom_project_url = std::string::utf8(b"https://custom-project.io");
            let custom_creator = std::string::utf8(b"Custom Creator");
            
            // Verify custom values were set correctly
            let description_field = sui::vec_map::get(display_fields, &std::string::utf8(b"description"));
            
            assert!(custom_description == *description_field, 1);

            let link_field = sui::vec_map::get(display_fields, &std::string::utf8(b"link"));
            
            assert!(custom_link == *link_field, 2);

            let project_url_field = sui::vec_map::get(display_fields, &std::string::utf8(b"project_url"));
            
            assert!(custom_project_url == *project_url_field, 3);

            let creator_field = sui::vec_map::get(display_fields, &std::string::utf8(b"creator"));
            
            assert!(custom_creator == *creator_field, 4);

            // Verify template values are preserved
            let name_field = sui::vec_map::get(display_fields, &std::string::utf8(b"name"));
            assert!(std::string::utf8(b"{name}") == *name_field, 5);

            let coin_a_field = sui::vec_map::get(display_fields, &std::string::utf8(b"coin_a"));
            assert!(std::string::utf8(b"{coin_type_a}") == *coin_a_field, 6);

            let coin_b_field = sui::vec_map::get(display_fields, &std::string::utf8(b"coin_b"));
            assert!(std::string::utf8(b"{coin_type_b}") == *coin_b_field, 7);

            let image_url_field = sui::vec_map::get(display_fields, &std::string::utf8(b"image_url"));
            assert!(std::string::utf8(b"{url}") == *image_url_field, 8);

            // Return objects to scenario
            scenario.return_to_sender(display);
        };

        scenario.end();
    }
}
