/// Rewarder module for the CLMM (Concentrated Liquidity Market Maker) pool system.
/// This module provides functionality for:
/// * Managing reward tokens and their distribution
/// * Tracking reward growth and accumulation
/// * Handling reward claims and withdrawals
/// * Managing reward configurations and parameters
/// 
/// The module implements:
/// * Reward token management
/// * Reward growth tracking
/// * Reward distribution logic
/// * Reward claim processing
/// 
/// # Key Concepts
/// * Reward Token - Token used for rewards distribution
/// * Reward Growth - Accumulated rewards per unit of liquidity
/// * Reward Claim - Process of withdrawing accumulated rewards
/// * Reward Configuration - Parameters controlling reward distribution
/// 
/// # Events
/// * Reward token registration events
/// * Reward growth update events
/// * Reward claim events
/// * Reward configuration update events
module clmm_pool::rewarder {
    /// Manager for reward distribution in the pool.
    /// Contains information about all rewarders, points, and timing.
    /// 
    /// # Fields
    /// * `rewarders` - Vector of reward configurations
    /// * `points_released` - Total points released for rewards
    /// * `points_growth_global` - Global growth of points
    /// * `last_updated_time` - Timestamp of last update
    public struct RewarderManager has store {
        rewarders: vector<Rewarder>,
        points_released: u128,
        points_growth_global: u128,
        last_updated_time: u64,
    }

    /// Configuration for a specific reward token.
    /// Contains information about emission rate and growth.
    /// 
    /// # Fields
    /// * `reward_coin` - Type of the reward token
    /// * `emissions_per_second` - Rate of reward emission
    /// * `growth_global` - Global growth of rewards
    public struct Rewarder has copy, drop, store {
        reward_coin: std::type_name::TypeName,
        emissions_per_second: u128,
        growth_global: u128,
    }

    /// Global vault for storing reward token balances.
    /// 
    /// # Fields
    /// * `id` - Unique identifier of the vault
    /// * `balances` - Bag containing reward token balances
    public struct RewarderGlobalVault has store, key {
        id: sui::object::UID,
        balances: sui::bag::Bag,
    }

    /// Event emitted when the rewarder is initialized.
    /// 
    /// # Fields
    /// * `global_vault_id` - ID of the initialized global vault
    public struct RewarderInitEvent has copy, drop {
        global_vault_id: sui::object::ID,
    }

    /// Event emitted when rewards are deposited.
    /// 
    /// # Fields
    /// * `reward_type` - Type of the deposited reward
    /// * `deposit_amount` - Amount of rewards deposited
    /// * `after_amount` - Total amount after deposit
    public struct DepositEvent has copy, drop, store {
        reward_type: std::type_name::TypeName,
        deposit_amount: u64,
        after_amount: u64,
    }

    /// Event emitted during emergency withdrawal of rewards.
    /// 
    /// # Fields
    /// * `reward_type` - Type of the withdrawn reward
    /// * `withdraw_amount` - Amount of rewards withdrawn
    /// * `after_amount` - Total amount after withdrawal
    public struct EmergentWithdrawEvent has copy, drop, store {
        reward_type: std::type_name::TypeName,
        withdraw_amount: u64,
        after_amount: u64,
    }

    /// Creates a new RewarderManager instance with default values.
    /// Initializes all fields to their zero values.
    /// 
    /// # Returns
    /// A new RewarderManager instance with:
    /// * Empty rewarders vector
    /// * Zero points released
    /// * Zero points growth
    /// * Zero last updated time
    public(package) fun new(): RewarderManager {
        RewarderManager {
            rewarders: std::vector::empty<Rewarder>(),
            points_released: 0,
            points_growth_global: 0,
            last_updated_time: 0,
        }
    }

    /// Adds a new rewarder configuration to the manager.
    /// 
    /// # Arguments
    /// * `rewarder_manager` - Mutable reference to the rewarder manager
    /// 
    /// # Abort Conditions
    /// * If the rewarder already exists (error code: 2)
    /// * If the maximum number of rewarders (3) is exceeded (error code: 1)
    public(package) fun add_rewarder<RewardCoinType>(rewarder_manager: &mut RewarderManager) {
        let rewarder_idx = rewarder_index<RewardCoinType>(rewarder_manager);
        assert!(std::option::is_none<u64>(&rewarder_idx), 2);
        assert!(std::vector::length<Rewarder>(&rewarder_manager.rewarders) <= 2, 1);
        let new_rewarder = Rewarder {
            reward_coin: std::type_name::get<RewardCoinType>(),
            emissions_per_second: 0,
            growth_global: 0,
        };
        std::vector::push_back<Rewarder>(&mut rewarder_manager.rewarders, new_rewarder);
    }

    /// Gets the balance of a specific reward token in the vault.
    /// 
    /// # Arguments
    /// * `vault` - Reference to the rewarder global vault
    /// 
    /// # Returns
    /// The balance of the specified reward token. Returns 0 if the token is not found.
    public fun balance_of<RewardCoinType>(vault: &RewarderGlobalVault): u64 {
        let reward_type = std::type_name::get<RewardCoinType>();
        if (!sui::bag::contains<std::type_name::TypeName>(&vault.balances, reward_type)) {
            return 0
        };
        sui::balance::value<RewardCoinType>(
            sui::bag::borrow<std::type_name::TypeName, sui::balance::Balance<RewardCoinType>>(&vault.balances, reward_type)
        )
    }

    /// Gets a reference to the balances bag in the vault.
    /// 
    /// # Arguments
    /// * `vault` - Reference to the rewarder global vault
    /// 
    /// # Returns
    /// Reference to the bag containing all reward token balances
    public fun balances(vault: &RewarderGlobalVault): &sui::bag::Bag {
        &vault.balances
    }

    /// Gets a mutable reference to a specific rewarder configuration.
    /// 
    /// # Arguments
    /// * `manager` - Mutable reference to the rewarder manager
    /// 
    /// # Returns
    /// Mutable reference to the rewarder configuration
    /// 
    /// # Abort Conditions
    /// * If the rewarder is not found (error code: 5)
    public(package) fun borrow_mut_rewarder<RewardCoinType>(manager: &mut RewarderManager): &mut Rewarder {
        let mut index = 0;
        while (index < std::vector::length<Rewarder>(&manager.rewarders)) {
            if (std::vector::borrow<Rewarder>(&manager.rewarders, index).reward_coin == std::type_name::get<RewardCoinType>()) {
                return std::vector::borrow_mut<Rewarder>(&mut manager.rewarders, index)
            };
            index = index + 1;
        };
        abort 5
    }

    /// Gets a reference to a specific rewarder configuration.
    /// 
    /// # Arguments
    /// * `manager` - Reference to the rewarder manager
    /// 
    /// # Returns
    /// Reference to the rewarder configuration
    /// 
    /// # Abort Conditions
    /// * If the rewarder is not found (error code: 5)
    public fun borrow_rewarder<RewardCoinType>(manager: &RewarderManager): &Rewarder {
        let mut index = 0;
        while (index < std::vector::length<Rewarder>(&manager.rewarders)) {
            if (std::vector::borrow<Rewarder>(&manager.rewarders, index).reward_coin == std::type_name::get<RewardCoinType>()) {
                return std::vector::borrow<Rewarder>(&manager.rewarders, index)
            };
            index = index + 1;
        };
        abort 5
    }

    /// Deposits reward tokens into the global vault.
    /// 
    /// # Arguments
    /// * `global_config` - Reference to the global configuration
    /// * `vault` - Mutable reference to the rewarder global vault
    /// * `balance` - Balance of reward tokens to deposit
    /// 
    /// # Returns
    /// The total amount after deposit
    public fun deposit_reward<RewardCoinType>(
        global_config: &clmm_pool::config::GlobalConfig,
        vault: &mut RewarderGlobalVault,
        balance: sui::balance::Balance<RewardCoinType>
    ): u64 {
        clmm_pool::config::checked_package_version(global_config);
        let reward_type = std::type_name::get<RewardCoinType>();
        if (!sui::bag::contains<std::type_name::TypeName>(&vault.balances, reward_type)) {
            sui::bag::add<std::type_name::TypeName, sui::balance::Balance<RewardCoinType>>(
                &mut vault.balances,
                reward_type,
                sui::balance::zero<RewardCoinType>()
            );
        };
        let deposit_amount = sui::balance::value<RewardCoinType>(&balance);
        let after_amount = sui::balance::join<RewardCoinType>(
            sui::bag::borrow_mut<std::type_name::TypeName, sui::balance::Balance<RewardCoinType>>(&mut vault.balances, reward_type),
            balance
        );
        let event = DepositEvent {
            reward_type: reward_type,
            deposit_amount: deposit_amount,
            after_amount: after_amount,
        };
        sui::event::emit<DepositEvent>(event);
        after_amount
    }

    /// Performs an emergency withdrawal of reward tokens.
    /// 
    /// # Arguments
    /// * `admin_cap` - Reference to the admin capability
    /// * `global_config` - Reference to the global configuration
    /// * `rewarder_vault` - Mutable reference to the rewarder global vault
    /// * `withdraw_amount` - Amount of tokens to withdraw
    /// 
    /// # Returns
    /// Balance of withdrawn reward tokens
    public fun emergent_withdraw<RewardCoinType>(
        admin_cap: &clmm_pool::config::AdminCap,
        global_config: &clmm_pool::config::GlobalConfig,
        rewarder_vault: &mut RewarderGlobalVault,
        withdraw_amount: u64
    ): sui::balance::Balance<RewardCoinType> {
        clmm_pool::config::checked_package_version(global_config);
        let event = EmergentWithdrawEvent {
            reward_type: std::type_name::get<RewardCoinType>(),
            withdraw_amount: withdraw_amount,
            after_amount: balance_of<RewardCoinType>(rewarder_vault),
        };
        sui::event::emit<EmergentWithdrawEvent>(event);
        withdraw_reward<RewardCoinType>(rewarder_vault, withdraw_amount)
    }

    /// Gets the emission rate for a rewarder.
    /// 
    /// # Arguments
    /// * `rewarder` - Reference to the rewarder configuration
    /// 
    /// # Returns
    /// The emission rate per second
    public fun emissions_per_second(rewarder: &Rewarder): u128 {
        rewarder.emissions_per_second
    }

    /// Gets the global growth for a rewarder.
    /// 
    /// # Arguments
    /// * `rewarder` - Reference to the rewarder configuration
    /// 
    /// # Returns
    /// The global growth value
    public fun growth_global(rewarder: &Rewarder): u128 {
        rewarder.growth_global
    }

    /// Initializes the rewarder module and creates the global vault.
    /// 
    /// # Arguments
    /// * `ctx` - Mutable reference to the transaction context
    fun init(ctx: &mut sui::tx_context::TxContext) {
        let vault = RewarderGlobalVault {
            id: sui::object::new(ctx),
            balances: sui::bag::new(ctx),
        };
        let global_vault_id = sui::object::id<RewarderGlobalVault>(&vault);
        sui::transfer::share_object<RewarderGlobalVault>(vault);
        let event = RewarderInitEvent { global_vault_id };
        sui::event::emit<RewarderInitEvent>(event);
    }

    /// Gets the last update time from the manager.
    /// 
    /// # Arguments
    /// * `manager` - Reference to the rewarder manager
    /// 
    /// # Returns
    /// The timestamp of the last update
    public fun last_update_time(manager: &RewarderManager): u64 {
        manager.last_updated_time
    }

    /// Gets the global points growth from the manager.
    /// 
    /// # Arguments
    /// * `manager` - Reference to the rewarder manager
    /// 
    /// # Returns
    /// The global points growth value
    public fun points_growth_global(manager: &RewarderManager): u128 {
        manager.points_growth_global
    }

    /// Gets the total points released from the manager.
    /// 
    /// # Arguments
    /// * `manager` - Reference to the rewarder manager
    /// 
    /// # Returns
    /// The total points released
    public fun points_released(manager: &RewarderManager): u128 {
        manager.points_released
    }

    /// Gets the reward coin type from a rewarder.
    /// 
    /// # Arguments
    /// * `rewarder` - Reference to the rewarder configuration
    /// 
    /// # Returns
    /// The type name of the reward coin
    public fun reward_coin(rewarder: &Rewarder): std::type_name::TypeName {
        rewarder.reward_coin
    }

    /// Gets the index of a rewarder in the manager.
    /// 
    /// # Arguments
    /// * `manager` - Reference to the rewarder manager
    /// 
    /// # Returns
    /// Option containing the index if found, none otherwise
    public fun rewarder_index<RewardCoinType>(manager: &RewarderManager): std::option::Option<u64> {
        let mut index = 0;
        while (index < std::vector::length<Rewarder>(&manager.rewarders)) {
            if (std::vector::borrow<Rewarder>(&manager.rewarders, index).reward_coin == std::type_name::get<RewardCoinType>()) {
                return std::option::some<u64>(index)
            };
            index = index + 1;
        };
        std::option::none<u64>()
    }

    /// Gets all rewarders from the manager.
    /// 
    /// # Arguments
    /// * `manager` - Reference to the rewarder manager
    /// 
    /// # Returns
    /// Vector of all rewarder configurations
    public fun rewarders(manager: &RewarderManager): vector<Rewarder> {
        manager.rewarders
    }

    /// Gets the global growth values for all rewarders.
    /// 
    /// # Arguments
    /// * `manager` - Reference to the rewarder manager
    /// 
    /// # Returns
    /// Vector of global growth values for each rewarder
    public fun rewards_growth_global(manager: &RewarderManager): vector<u128> {
        let mut index = 0;
        let mut rewards = std::vector::empty<u128>();
        while (index < std::vector::length<Rewarder>(&manager.rewarders)) {
            std::vector::push_back<u128>(&mut rewards, std::vector::borrow<Rewarder>(&manager.rewarders, index).growth_global);
            index = index + 1;
        };
        rewards
    }

    /// Settles reward calculations based on time elapsed and liquidity.
    /// 
    /// # Arguments
    /// * `manager` - Mutable reference to the rewarder manager
    /// * `liquidity` - Current liquidity value
    /// * `current_time` - Current timestamp
    /// 
    /// # Abort Conditions
    /// * If current time is less than last update time (error code: 3)
    public(package) fun settle(manager: &mut RewarderManager, liquidity: u128, current_time: u64) {
        let last_time = manager.last_updated_time;
        manager.last_updated_time = current_time;
        assert!(last_time <= current_time, 3);
        if (liquidity == 0 || last_time == current_time) {
            return
        };
        let time_delta = current_time - last_time;
        let mut index = 0;
        while (index < std::vector::length<Rewarder>(&manager.rewarders)) {
            std::vector::borrow_mut<Rewarder>(&mut manager.rewarders, index).growth_global = std::vector::borrow<Rewarder>(
                &manager.rewarders,
                index
            ).growth_global + integer_mate::full_math_u128::mul_div_floor(
                time_delta as u128,
                std::vector::borrow<Rewarder>(&manager.rewarders, index).emissions_per_second,
                liquidity
            );
            index = index + 1;
        };
        manager.points_released = manager.points_released + (time_delta as u128) * 18446744073709551616000000;
        manager.points_growth_global = manager.points_growth_global + integer_mate::full_math_u128::mul_div_floor(
            time_delta as u128,
            18446744073709551616000000,
            liquidity
        );
    }

    /// Updates the emission rate for a specific reward token.
    /// 
    /// # Arguments
    /// * `rewarder_vault` - Reference to the rewarder global vault
    /// * `rewarder_manager` - Mutable reference to the rewarder manager
    /// * `liquidity` - Current liquidity value
    /// * `emission_rate` - New emission rate (already shifted by 64 bits)
    /// * `current_time` - Current timestamp
    /// 
    /// # Abort Conditions
    /// * If the reward token is not found in the vault (error code: 5)
    /// * If the emission rate exceeds available balance (error code: 4)
    public(package) fun update_emission<RewardCoinType>(
        rewarder_vault: &RewarderGlobalVault,
        rewarder_manager: &mut RewarderManager,
        liquidity: u128,
        emission_rate: u128,
        current_time: u64
    ) {
        settle(rewarder_manager, liquidity, current_time);
        if (emission_rate > 0) {
            let reward_type = std::type_name::get<RewardCoinType>();
            assert!(sui::bag::contains<std::type_name::TypeName>(&rewarder_vault.balances, reward_type), 5);
            assert!(
                (sui::balance::value<RewardCoinType>(
                    sui::bag::borrow<std::type_name::TypeName, sui::balance::Balance<RewardCoinType>>(&rewarder_vault.balances, reward_type)
                ) as u128) >= (86400 * emission_rate >> 64),
                4
            );
        };
        borrow_mut_rewarder<RewardCoinType>(rewarder_manager).emissions_per_second = emission_rate;
    }

    /// Withdraws reward tokens from the vault.
    /// 
    /// # Arguments
    /// * `rewarder_vault` - Mutable reference to the rewarder global vault
    /// * `amount` - Amount of tokens to withdraw
    /// 
    /// # Returns
    /// Balance of withdrawn reward tokens
    public(package) fun withdraw_reward<RewardCoinType>(
        rewarder_vault: &mut RewarderGlobalVault,
        amount: u64
    ): sui::balance::Balance<RewardCoinType> {
        sui::balance::split<RewardCoinType>(
            sui::bag::borrow_mut<std::type_name::TypeName, sui::balance::Balance<RewardCoinType>>(
                &mut rewarder_vault.balances,
                std::type_name::get<RewardCoinType>()
            ),
            amount
        )
    }

    #[test_only]
    public fun test_init(ctx: &mut sui::tx_context::TxContext) {
        let vault = RewarderGlobalVault {
            id: sui::object::new(ctx),
            balances: sui::bag::new(ctx),
        };
        sui::transfer::share_object(vault);
    }

    #[test]
    fun test_init_fun() {
        let admin = @0x123;
        let mut scenario = sui::test_scenario::begin(admin);
        {
            init(scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            let vault = scenario.take_shared<RewarderGlobalVault>();
            assert!(sui::bag::is_empty(&vault.balances), 1);
            sui::test_scenario::return_shared(vault);
        };

        scenario.end();
    }
}

