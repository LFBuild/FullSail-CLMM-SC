#[test_only]
module clmm_pool::rewarder_tests {
    use clmm_pool::rewarder;
    use sui::test_scenario;
    use sui::transfer;
    use sui::object;
    use sui::coin;
    use sui::balance;
    use sui::bag;
    use std::vector;
    use std::type_name;
    use std::option;

    #[test_only]
    public struct MY_COIN has drop {}

    #[test_only]
    public struct MY_COIN2 has drop {}

    #[test_only]
    public struct MY_COIN3 has drop {}

    #[test_only]
    public struct MY_COIN4 has drop {}

    #[test_only]
    public struct TestRewarder has store, key {
        id: sui::object::UID,
        rewarder_manager: rewarder::RewarderManager,
    }

    #[test]
    fun test_rewarder_manager_initialization() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder
        {
            rewarder::test_init(scenario.ctx());
        };

        // Check vault initialization
        scenario.next_tx(admin);
        {
            let vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            assert!(rewarder::balances(&vault).is_empty(), 1);
            test_scenario::return_shared(vault);
        };

        scenario.end();
    }

    #[test]
    fun test_rewarder_management() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder
        {
            rewarder::test_init(scenario.ctx());
        };

        // Create rewarder manager
        scenario.next_tx(admin);
        {
            let test_rewarder = TestRewarder {
                id: object::new(scenario.ctx()),
                rewarder_manager: rewarder::new(),
            };
            let rewarders = rewarder::rewarders(&test_rewarder.rewarder_manager);
            assert!(vector::is_empty(&rewarders), 1);
            assert!(rewarder::points_released(&test_rewarder.rewarder_manager) == 0, 2);
            assert!(rewarder::points_growth_global(&test_rewarder.rewarder_manager) == 0, 3);
            assert!(rewarder::last_update_time(&test_rewarder.rewarder_manager) == 0, 4);
            transfer::public_transfer(test_rewarder, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_rewarder_add_and_get() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder
        {
            rewarder::test_init(scenario.ctx());
        };

        // Create rewarder manager and add rewarder
        scenario.next_tx(admin);
        {
            let mut test_rewarder = TestRewarder {
                id: object::new(scenario.ctx()),
                rewarder_manager: rewarder::new(),
            };
            rewarder::add_rewarder<MY_COIN>(&mut test_rewarder.rewarder_manager);
            
            // Check rewarder was added
            let rewarders = rewarder::rewarders(&test_rewarder.rewarder_manager);
            assert!(vector::length(&rewarders) == 1, 1);
            
            // Check rewarder properties
            let rewarder = vector::borrow(&rewarders, 0);
            assert!(rewarder::reward_coin(rewarder) == type_name::get<MY_COIN>(), 2);
            assert!(rewarder::emissions_per_second(rewarder) == 0, 3);
            assert!(rewarder::growth_global(rewarder) == 0, 4);
            transfer::public_transfer(test_rewarder, admin);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 2)]
    fun test_rewarder_duplicate_add() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder
        {
            rewarder::test_init(scenario.ctx());
        };

        // Try to add same rewarder twice
        scenario.next_tx(admin);
        {
            let mut test_rewarder = TestRewarder {
                id: object::new(scenario.ctx()),
                rewarder_manager: rewarder::new(),
            };
            rewarder::add_rewarder<MY_COIN>(&mut test_rewarder.rewarder_manager);
            rewarder::add_rewarder<MY_COIN>(&mut test_rewarder.rewarder_manager);
            transfer::public_transfer(test_rewarder, admin);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 1)]
    fun test_rewarder_max_limit() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder
        {
            rewarder::test_init(scenario.ctx());
        };

        // Try to add more than 2 rewarders
        scenario.next_tx(admin);
        {
            let mut test_rewarder = TestRewarder {
                id: object::new(scenario.ctx()),
                rewarder_manager: rewarder::new(),
            };

            rewarder::add_rewarder<MY_COIN>(&mut test_rewarder.rewarder_manager);
            rewarder::add_rewarder<MY_COIN2>(&mut test_rewarder.rewarder_manager);
            rewarder::add_rewarder<MY_COIN3>(&mut test_rewarder.rewarder_manager);
            rewarder::add_rewarder<MY_COIN4>(&mut test_rewarder.rewarder_manager);
            transfer::public_transfer(test_rewarder, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_rewarder_borrow() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder
        {
            rewarder::test_init(scenario.ctx());
        };

        // Test borrowing rewarder
        scenario.next_tx(admin);
        {
            let mut test_rewarder = TestRewarder {
                id: object::new(scenario.ctx()),
                rewarder_manager: rewarder::new(),
            };
            rewarder::add_rewarder<MY_COIN>(&mut test_rewarder.rewarder_manager);
            
            // Test immutable borrow
            let rewarder_ref = rewarder::borrow_rewarder<MY_COIN>(&test_rewarder.rewarder_manager);
            assert!(rewarder::reward_coin(rewarder_ref) == type_name::get<MY_COIN>(), 1);
            
            // Test mutable borrow
            let rewarder_mut = rewarder::borrow_mut_rewarder<MY_COIN>(&mut test_rewarder.rewarder_manager);
            assert!(rewarder::reward_coin(rewarder_mut) == type_name::get<MY_COIN>(), 2);
            transfer::public_transfer(test_rewarder, admin);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 5)]
    fun test_rewarder_borrow_nonexistent() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder
        {
            rewarder::test_init(scenario.ctx());
        };

        // Try to borrow non-existent rewarder
        scenario.next_tx(admin);
        {
            let test_rewarder = TestRewarder {
                id: object::new(scenario.ctx()),
                rewarder_manager: rewarder::new(),
            };
            rewarder::borrow_rewarder<MY_COIN>(&test_rewarder.rewarder_manager);
            transfer::public_transfer(test_rewarder, admin);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 5)]
    fun test_rewarder_borrow_mut_nonexistent() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder
        {
            rewarder::test_init(scenario.ctx());
        };

        // Try to borrow non-existent rewarder
        scenario.next_tx(admin);
        {
            let mut test_rewarder = TestRewarder {
                id: object::new(scenario.ctx()),
                rewarder_manager: rewarder::new(),
            };
            rewarder::borrow_mut_rewarder<MY_COIN>(&mut test_rewarder.rewarder_manager);
            transfer::public_transfer(test_rewarder, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_deposit_reward() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder and config
        {
            rewarder::test_init(scenario.ctx());
            clmm_pool::config::test_init(scenario.ctx());
        };

        // Create test coin and deposit
        scenario.next_tx(admin);
        {
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let global_config = scenario.take_shared<clmm_pool::config::GlobalConfig>();
            
            // Create test coin
            let coin = coin::mint_for_testing<MY_COIN>(100, scenario.ctx());
            let balance = coin::into_balance(coin);
            
            // Deposit reward
            let after_amount = rewarder::deposit_reward(&global_config, &mut vault, balance);
            assert!(after_amount == 100, 1);
            
            // Check balance
            assert!(rewarder::balance_of<MY_COIN>(&vault) == 100, 2);
            
            test_scenario::return_shared(vault);
            test_scenario::return_shared(global_config);
        };

        scenario.end();
    }

    #[test]
    fun test_emergent_withdraw() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder and config
        {
            rewarder::test_init(scenario.ctx());
            clmm_pool::config::test_init(scenario.ctx());
        };

        // Create test coin, deposit and withdraw
        scenario.next_tx(admin);
        {
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let global_config = scenario.take_shared<clmm_pool::config::GlobalConfig>();
            let admin_cap = scenario.take_from_sender<clmm_pool::config::AdminCap>();
            
            // Create and deposit test coin
            let coin = coin::mint_for_testing<MY_COIN>(100, scenario.ctx());
            let balance = coin::into_balance(coin);
            rewarder::deposit_reward(&global_config, &mut vault, balance);
            
            // Withdraw reward
            let withdraw_amount = 50;
            let withdrawn = rewarder::emergent_withdraw<MY_COIN>(&admin_cap, &global_config, &mut vault, withdraw_amount);
            let withdrawn_coin = coin::from_balance(withdrawn, scenario.ctx());
            assert!(coin::value(&withdrawn_coin) == withdraw_amount, 1);
            assert!(rewarder::balance_of<MY_COIN>(&vault) == 50, 2);
            
            test_scenario::return_shared(vault);
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
            transfer::public_transfer(withdrawn_coin, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_settle() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder
        {
            rewarder::test_init(scenario.ctx());
        };

        // Test settle functionality
        scenario.next_tx(admin);
        {
            let mut test_rewarder = TestRewarder {
                id: object::new(scenario.ctx()),
                rewarder_manager: rewarder::new(),
            };
            
            // Add rewarder with emission rate
            rewarder::add_rewarder<MY_COIN>(&mut test_rewarder.rewarder_manager);
            
            // Test settle with zero liquidity
            rewarder::settle(&mut test_rewarder.rewarder_manager, 0, 1000);
            assert!(rewarder::growth_global(rewarder::borrow_rewarder<MY_COIN>(&test_rewarder.rewarder_manager)) == 0, 1);
            
            // Test settle with non-zero liquidity
            rewarder::settle(&mut test_rewarder.rewarder_manager, 1000, 2000);
            assert!(rewarder::growth_global(rewarder::borrow_rewarder<MY_COIN>(&test_rewarder.rewarder_manager)) == 0, 2);
            
            transfer::public_transfer(test_rewarder, admin);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 4)]
    fun test_update_emission_insufficient_balance() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder and config
        {
            rewarder::test_init(scenario.ctx());
            clmm_pool::config::test_init(scenario.ctx());
        };

        // Try to update emission without sufficient balance
        scenario.next_tx(admin);
        {
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let global_config = scenario.take_shared<clmm_pool::config::GlobalConfig>();
            let mut test_rewarder = TestRewarder {
                id: object::new(scenario.ctx()),
                rewarder_manager: rewarder::new(),
            };
            
            // Add rewarder
            rewarder::add_rewarder<MY_COIN>(&mut test_rewarder.rewarder_manager);
            
            // Add small amount of coins to vault (less than required for emission rate)
            let coin = coin::mint_for_testing<MY_COIN>(1000, scenario.ctx());
            let balance = coin::into_balance(coin);
            rewarder::deposit_reward(&global_config, &mut vault, balance);
            
            // Try to set emission rate that requires more balance than available
            // Required balance: 86400 * 1000 = 86400000
            // Available balance: 1000
            // After shift: 1000 << 64 = 18446744073709551616000
            // This should fail because 1000 << 64 < 86400000
            rewarder::update_emission<MY_COIN>(&vault, &mut test_rewarder.rewarder_manager, 1000, 1000 << 64, 1000);
            
            test_scenario::return_shared(vault);
            test_scenario::return_shared(global_config);
            transfer::public_transfer(test_rewarder, admin);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 5)]
    fun test_update_emission_nonexistent_rewarder() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder and config
        {
            rewarder::test_init(scenario.ctx());
            clmm_pool::config::test_init(scenario.ctx());
        };

        // Try to update emission for non-existent rewarder
        scenario.next_tx(admin);
        {
            let vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let global_config = scenario.take_shared<clmm_pool::config::GlobalConfig>();
            let mut test_rewarder = TestRewarder {
                id: object::new(scenario.ctx()),
                rewarder_manager: rewarder::new(),
            };
            
            // Try to update emission without adding rewarder first
            rewarder::update_emission<MY_COIN>(&vault, &mut test_rewarder.rewarder_manager, 1000, 1000, 1000);
            
            test_scenario::return_shared(vault);
            test_scenario::return_shared(global_config);
            transfer::public_transfer(test_rewarder, admin);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 3)]
    fun test_settle_invalid_time() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder
        {
            rewarder::test_init(scenario.ctx());
        };

        // Test settle with invalid time
        scenario.next_tx(admin);
        {
            let mut test_rewarder = TestRewarder {
                id: object::new(scenario.ctx()),
                rewarder_manager: rewarder::new(),
            };
            
            // Add rewarder
            rewarder::add_rewarder<MY_COIN>(&mut test_rewarder.rewarder_manager);
            
            // First settle with time 2000
            rewarder::settle(&mut test_rewarder.rewarder_manager, 1000, 2000);
            
            // Try to settle with time 1000 (less than last_update_time)
            rewarder::settle(&mut test_rewarder.rewarder_manager, 1000, 1000);
            
            transfer::public_transfer(test_rewarder, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_rewarder_index() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder
        {
            rewarder::test_init(scenario.ctx());
        };

        // Test rewarder_index
        scenario.next_tx(admin);
        {
            let mut test_rewarder = TestRewarder {
                id: object::new(scenario.ctx()),
                rewarder_manager: rewarder::new(),
            };
            
            // Add rewarder
            rewarder::add_rewarder<MY_COIN>(&mut test_rewarder.rewarder_manager);
            
            // Test finding index of existing rewarder
            let mut index = rewarder::rewarder_index<MY_COIN>(&test_rewarder.rewarder_manager);
            assert!(option::is_some(&index), 1);
            let index_value = option::extract(&mut index);
            assert!(index_value == 0, 2);
            
            // Add second rewarder
            rewarder::add_rewarder<MY_COIN2>(&mut test_rewarder.rewarder_manager);
            
            // Test finding index of second rewarder
            let mut index2 = rewarder::rewarder_index<MY_COIN2>(&test_rewarder.rewarder_manager);
            assert!(option::is_some(&index2), 3);
            let index2_value = option::extract(&mut index2);
            assert!(index2_value == 1, 4);

            // Test that MY_COIN3 doesn't exist
            let index3 = rewarder::rewarder_index<MY_COIN3>(&test_rewarder.rewarder_manager);
            assert!(option::is_none(&index3), 5);
            
            transfer::public_transfer(test_rewarder, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_rewards_growth_global() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder
        {
            rewarder::test_init(scenario.ctx());
        };

        // Test rewards_growth_global
        scenario.next_tx(admin);
        {
            let mut test_rewarder = TestRewarder {
                id: object::new(scenario.ctx()),
                rewarder_manager: rewarder::new(),
            };
            
            // Test empty rewards_growth_global
            let empty_growth = rewarder::rewards_growth_global(&test_rewarder.rewarder_manager);
            assert!(vector::is_empty(&empty_growth), 1);
            
            // Add first rewarder
            rewarder::add_rewarder<MY_COIN>(&mut test_rewarder.rewarder_manager);
            
            // Test single rewarder growth
            let single_growth = rewarder::rewards_growth_global(&test_rewarder.rewarder_manager);
            assert!(vector::length(&single_growth) == 1, 2);
            assert!(*vector::borrow(&single_growth, 0) == 0, 3);
            
            // Add second rewarder
            rewarder::add_rewarder<MY_COIN2>(&mut test_rewarder.rewarder_manager);
            
            // Test multiple rewarders growth
            let multiple_growth = rewarder::rewards_growth_global(&test_rewarder.rewarder_manager);
            assert!(vector::length(&multiple_growth) == 2, 4);
            assert!(*vector::borrow(&multiple_growth, 0) == 0, 5);
            assert!(*vector::borrow(&multiple_growth, 1) == 0, 6);
            
            // Update growth values using settle
            rewarder::settle(&mut test_rewarder.rewarder_manager, 1000, 2000);
            
            // Test updated growth values
            let updated_growth = rewarder::rewards_growth_global(&test_rewarder.rewarder_manager);
            assert!(vector::length(&updated_growth) == 2, 7);
            assert!(*vector::borrow(&updated_growth, 0) == 0, 8);
            assert!(*vector::borrow(&updated_growth, 1) == 0, 9);
            
            transfer::public_transfer(test_rewarder, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_update_emission_success() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder and config
        {
            rewarder::test_init(scenario.ctx());
            clmm_pool::config::test_init(scenario.ctx());
        };

        // Test successful emission update
        scenario.next_tx(admin);
        {
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let global_config = scenario.take_shared<clmm_pool::config::GlobalConfig>();
            let mut test_rewarder = TestRewarder {
                id: object::new(scenario.ctx()),
                rewarder_manager: rewarder::new(),
            };
            
            // Add rewarder
            rewarder::add_rewarder<MY_COIN>(&mut test_rewarder.rewarder_manager);
            
            // Add sufficient coins to vault
            let coin = coin::mint_for_testing<MY_COIN>(100000000, scenario.ctx());
            let balance = coin::into_balance(coin);
            rewarder::deposit_reward(&global_config, &mut vault, balance);
            
            // Debug prints before update
            let initial_balance = rewarder::balance_of<MY_COIN>(&vault);
            
            // Set emission rate
            let emission_rate = 1000;
            let shifted_rate = emission_rate << 64;
            rewarder::update_emission<MY_COIN>(&vault, &mut test_rewarder.rewarder_manager, 1000, shifted_rate, 1000);
            
            // Verify emission rate was set
            let rewarder = rewarder::borrow_rewarder<MY_COIN>(&test_rewarder.rewarder_manager);
            assert!(rewarder::emissions_per_second(rewarder) == shifted_rate, 1);
            
            // Verify balance was not changed
            assert!(rewarder::balance_of<MY_COIN>(&vault) == initial_balance, 2);
            
            test_scenario::return_shared(vault);
            test_scenario::return_shared(global_config);
            transfer::public_transfer(test_rewarder, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_update_emission_zero_rate() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder and config
        {
            rewarder::test_init(scenario.ctx());
            clmm_pool::config::test_init(scenario.ctx());
        };

        // Test setting emission rate to zero
        scenario.next_tx(admin);
        {
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let global_config = scenario.take_shared<clmm_pool::config::GlobalConfig>();
            let mut test_rewarder = TestRewarder {
                id: object::new(scenario.ctx()),
                rewarder_manager: rewarder::new(),
            };
            
            // Add rewarder
            rewarder::add_rewarder<MY_COIN>(&mut test_rewarder.rewarder_manager);
            
            // Add coins to vault
            let coin = coin::mint_for_testing<MY_COIN>(1000, scenario.ctx());
            let balance = coin::into_balance(coin);
            rewarder::deposit_reward(&global_config, &mut vault, balance);
            
            // Set emission rate to zero
            rewarder::update_emission<MY_COIN>(&vault, &mut test_rewarder.rewarder_manager, 1000, 0, 1000);
            
            // Verify emission rate was set to zero
            let rewarder = rewarder::borrow_rewarder<MY_COIN>(&test_rewarder.rewarder_manager);
            assert!(rewarder::emissions_per_second(rewarder) == 0, 1);
            
            // Verify balance was not changed (no balance required for zero emission)
            assert!(rewarder::balance_of<MY_COIN>(&vault) == 1000, 2);
            
            test_scenario::return_shared(vault);
            test_scenario::return_shared(global_config);
            transfer::public_transfer(test_rewarder, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_withdraw_reward() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder and config
        {
            rewarder::test_init(scenario.ctx());
            clmm_pool::config::test_init(scenario.ctx());
        };

        // Test successful withdrawal
        scenario.next_tx(admin);
        {
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let global_config = scenario.take_shared<clmm_pool::config::GlobalConfig>();
            
            // Add coins to vault
            let coin = coin::mint_for_testing<MY_COIN>(100, scenario.ctx());
            let balance = coin::into_balance(coin);
            rewarder::deposit_reward(&global_config, &mut vault, balance);
            
            // Withdraw reward
            let withdraw_amount = 50;
            let withdrawn = rewarder::withdraw_reward<MY_COIN>(&mut vault, withdraw_amount);
            let withdrawn_coin = coin::from_balance(withdrawn, scenario.ctx());
            
            // Verify withdrawal
            assert!(coin::value(&withdrawn_coin) == withdraw_amount, 1);
            assert!(rewarder::balance_of<MY_COIN>(&vault) == 50, 2);
            
            test_scenario::return_shared(vault);
            test_scenario::return_shared(global_config);
            transfer::public_transfer(withdrawn_coin, admin);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 2)]
    fun test_withdraw_reward_insufficient_balance() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder and config
        {
            rewarder::test_init(scenario.ctx());
            clmm_pool::config::test_init(scenario.ctx());
        };

        // Test withdrawal with insufficient balance
        scenario.next_tx(admin);
        {
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            let global_config = scenario.take_shared<clmm_pool::config::GlobalConfig>();
            
            // Add small amount of coins to vault
            let coin = coin::mint_for_testing<MY_COIN>(10, scenario.ctx());
            let balance = coin::into_balance(coin);
            rewarder::deposit_reward(&global_config, &mut vault, balance);
            
            // Try to withdraw more than available
            let withdrawn = rewarder::withdraw_reward<MY_COIN>(&mut vault, 20);
            let withdrawn_coin = coin::from_balance(withdrawn, scenario.ctx());
            transfer::public_transfer(withdrawn_coin, admin);
            
            test_scenario::return_shared(vault);
            test_scenario::return_shared(global_config);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 1)]
    fun test_withdraw_reward_empty_vault() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize rewarder and config
        {
            rewarder::test_init(scenario.ctx());
            clmm_pool::config::test_init(scenario.ctx());
        };

        // Test withdrawal from empty vault
        scenario.next_tx(admin);
        {
            let mut vault = scenario.take_shared<rewarder::RewarderGlobalVault>();
            
            // Try to withdraw from empty vault
            // This should fail because there is no balance for MY_COIN in the vault
            let withdrawn = rewarder::withdraw_reward<MY_COIN>(&mut vault, 10);
            let withdrawn_coin = coin::from_balance(withdrawn, scenario.ctx());
            transfer::public_transfer(withdrawn_coin, admin);
            
            test_scenario::return_shared(vault);
        };

        scenario.end();
    }
}
