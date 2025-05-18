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
    use std::unit_test::assert_eq;

    /// Error codes for the rewarder module
    const EMaxRewardersExceeded: u64 = 934062834076983206;
    const ERewarderAlreadyExists: u64 = 934862304673206987;
    const EInvalidTime: u64 = 923872347632063063;
    const EInsufficientBalance: u64 = 928307230473046907;
    const ERewarderNotFound: u64 = 923867923457032960;
    const EOverflowBalance: u64 = 92394823577283472;
    const EIncorrectWithdrawAmount: u64 = 94368340613806333;

    const SECONDS_PER_DAY: u64 = 86400;

    /// Points per second rate (Q64.64)
    const POINTS_PER_SECOND: u128 = 1000000 << 64;

    /// Points growth multiplier for precision in calculations (Q64.64)
    const POINTS_GROWTH_MULTIPLIER: u128 = 1000000 << 64;

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
    /// * `available_balance` - Table tracking available reward balances in Q64 format, used to monitor and control reward distribution
    public struct RewarderGlobalVault has store, key {
        id: sui::object::UID,
        balances: sui::bag::Bag,
        available_balance: sui::table::Table<std::type_name::TypeName, u128>,
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
    /// * If the rewarder already exists (error code: ERewarderAlreadyExists)
    /// * If the maximum number of rewarders (3) is exceeded (error code: EMaxRewardersExceeded)
    public(package) fun add_rewarder<RewardCoinType>(rewarder_manager: &mut RewarderManager) {
        let rewarder_idx = rewarder_index<RewardCoinType>(rewarder_manager);
        assert!(std::option::is_none<u64>(&rewarder_idx), ERewarderAlreadyExists);
        assert!(std::vector::length<Rewarder>(&rewarder_manager.rewarders) <= 2, EMaxRewardersExceeded);
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
    /// * If the rewarder is not found (error code: ERewarderNotFound)
    public(package) fun borrow_mut_rewarder<RewardCoinType>(manager: &mut RewarderManager): &mut Rewarder {
        let mut index = 0;
        while (index < std::vector::length<Rewarder>(&manager.rewarders)) {
            if (std::vector::borrow<Rewarder>(&manager.rewarders, index).reward_coin == std::type_name::get<RewardCoinType>()) {
                return std::vector::borrow_mut<Rewarder>(&mut manager.rewarders, index)
            };
            index = index + 1;
        };
        abort ERewarderNotFound
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
    /// * If the rewarder is not found (error code: ERewarderNotFound)
    public fun borrow_rewarder<RewardCoinType>(manager: &RewarderManager): &Rewarder {
        let mut index = 0;
        while (index < std::vector::length<Rewarder>(&manager.rewarders)) {
            if (std::vector::borrow<Rewarder>(&manager.rewarders, index).reward_coin == std::type_name::get<RewardCoinType>()) {
                return std::vector::borrow<Rewarder>(&manager.rewarders, index)
            };
            index = index + 1;
        };
        abort ERewarderNotFound
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
        if (!sui::table::contains<std::type_name::TypeName, u128>(&vault.available_balance, reward_type)) {
            vault.available_balance.add(reward_type, (deposit_amount as u128)<<64);
        } else {
            let available_balance = vault.available_balance.remove(reward_type);
            let (new_available_balance, overflow) = integer_mate::math_u128::overflowing_add(available_balance, (deposit_amount as u128)<<64);
            if (overflow) {
                abort EOverflowBalance
            };
            vault.available_balance.add(reward_type, new_available_balance);
        };
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
        _admin_cap: &clmm_pool::config::AdminCap,
        global_config: &clmm_pool::config::GlobalConfig,
        rewarder_vault: &mut RewarderGlobalVault,
        withdraw_amount: u64
    ): sui::balance::Balance<RewardCoinType> {
        clmm_pool::config::checked_package_version(global_config);

        let reward_type = std::type_name::get<RewardCoinType>();
        assert!(((withdraw_amount as u128)<<64) <= *rewarder_vault.available_balance.borrow(reward_type), EIncorrectWithdrawAmount);

        let available_balance = rewarder_vault.available_balance.remove(reward_type);
        rewarder_vault.available_balance.add(reward_type, available_balance - ((withdraw_amount as u128)<<64));

        let event = EmergentWithdrawEvent {
            reward_type: std::type_name::get<RewardCoinType>(),
            withdraw_amount: withdraw_amount,
            after_amount: balance_of<RewardCoinType>(rewarder_vault),
        };
        sui::event::emit<EmergentWithdrawEvent>(event);
        withdraw_reward<RewardCoinType>(rewarder_vault, withdraw_amount)
    }

    /// Gets the available balance for a specific reward token.
    /// 
    /// # Arguments
    /// * `rewarder_vault` - Reference to the rewarder global vault
    /// 
    /// # Returns
    /// The available balance for the specified reward token (Q64.64)
    public fun get_available_balance<RewardCoinType>(rewarder_vault: &RewarderGlobalVault): u128 {
        *rewarder_vault.available_balance.borrow(std::type_name::get<RewardCoinType>())
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
            available_balance: sui::table::new(ctx),
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
    /// * If current time is less than last update time (error code: EInvalidTime)
    public(package) fun settle(
        vault: &mut RewarderGlobalVault,
        manager: &mut RewarderManager, 
        liquidity: u128, 
        current_time: u64
    ) {
        let last_time = manager.last_updated_time;
        manager.last_updated_time = current_time;
        assert!(last_time <= current_time, EInvalidTime);
        if (liquidity == 0 || last_time == current_time) {
            return
        };
        let time_delta = current_time - last_time;
        let mut index = 0;
        while (index < std::vector::length<Rewarder>(&manager.rewarders)) {
            let rewarder = std::vector::borrow_mut<Rewarder>(&mut manager.rewarders, index);
            if (!vault.available_balance.contains(rewarder.reward_coin) || 
                rewarder.emissions_per_second == 0) {
    
                index = index + 1;
                continue
            };
            let mut add_growth_global = integer_mate::full_math_u128::mul_div_floor(
                time_delta as u128,
                rewarder.emissions_per_second,
                liquidity
            );
            let available_balance = vault.available_balance.remove(rewarder.reward_coin);
            if (available_balance <= add_growth_global * liquidity) {
                rewarder.emissions_per_second = 0;
                
                add_growth_global = integer_mate::full_math_u128::mul_div_floor(
                    available_balance,
                    1,
                    liquidity
                );
                vault.available_balance.add(rewarder.reward_coin, 0);
            } else {
                vault.available_balance.add(rewarder.reward_coin, available_balance - (add_growth_global * liquidity));
            };
            std::vector::borrow_mut<Rewarder>(&mut manager.rewarders, index).growth_global = std::vector::borrow<Rewarder>(
                &manager.rewarders,
                index
            ).growth_global + add_growth_global;
            
            index = index + 1;
        };
        manager.points_released = manager.points_released + (time_delta as u128) * POINTS_PER_SECOND;
        manager.points_growth_global = manager.points_growth_global + integer_mate::full_math_u128::mul_div_floor(
            time_delta as u128,
            POINTS_GROWTH_MULTIPLIER,
            liquidity
        );
    }

    /// Updates the emission rate for a specific reward token.
    /// 
    /// # Arguments
    /// * `rewarder_vault` - Reference to the rewarder global vault
    /// * `rewarder_manager` - Mutable reference to the rewarder manager
    /// * `liquidity` - Current liquidity value
    /// * `emission_rate` - New emission rate Q64.64
    /// * `current_time` - Current timestamp
    /// 
    /// # Abort Conditions
    /// * If the reward token is not found in the vault (error code: ERewarderNotFound)
    /// * If the emission rate exceeds available balance (error code: EInsufficientBalance)
    public(package) fun update_emission<RewardCoinType>(
        rewarder_vault: &mut RewarderGlobalVault,
        rewarder_manager: &mut RewarderManager,
        liquidity: u128,
        emission_rate: u128,
        current_time: u64
    ) {
        settle(rewarder_vault, rewarder_manager, liquidity, current_time);
        if (emission_rate > 0) {
            let reward_type = std::type_name::get<RewardCoinType>();
            assert!(sui::bag::contains<std::type_name::TypeName>(&rewarder_vault.balances, reward_type), ERewarderNotFound);
            assert!(*rewarder_vault.available_balance.borrow(reward_type) >= 
                integer_mate::full_math_u128::mul_shr((SECONDS_PER_DAY as u128)<<64, emission_rate, 64), EInsufficientBalance);
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
            available_balance: sui::table::new(ctx),
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
            assert!(sui::bag::is_empty(&vault.balances), EMaxRewardersExceeded);
            sui::test_scenario::return_shared(vault);
        };

        scenario.end();
    }
}

