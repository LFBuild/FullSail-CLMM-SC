/// Configuration module for the CLMM (Concentrated Liquidity Market Maker) pool system.
/// This module provides core configuration structures and functions for:
/// * Managing global pool settings
/// * Handling protocol fees
/// * Managing admin capabilities
/// * Controlling access to pool management functions
/// 
/// The module implements:
/// * Global configuration management
/// * Protocol fee collection and distribution
/// * Access control for administrative functions
/// * Version control for protocol upgrades
/// * Fee rate management and validation
/// 
/// # Capabilities
/// * AdminCap - Controls administrative functions and protocol settings
/// * ProtocolFeeClaimCap - Controls protocol fee collection and distribution
/// 
/// # Roles
/// * Pool Manager - Can manage pool settings and parameters
/// * Fee Manager - Can manage fee rates and fee-related settings
/// * Emergency Manager - Can pause/unpause pools in emergency situations
/// * Protocol Manager - Can manage protocol-level settings
module clmm_pool::config {
    /// Capability for administrative functions in the protocol.
    /// This capability is required for managing global settings and protocol parameters.
    /// 
    /// # Fields
    /// * `id` - Unique identifier for the capability
    public struct AdminCap has store, key {
        id: sui::object::UID,
    }

    /// Capability for claiming protocol fees.
    /// This capability is required for collecting and distributing protocol fees.
    /// 
    /// # Fields
    /// * `id` - Unique identifier for the capability
    public struct ProtocolFeeClaimCap has store, key {
        id: sui::object::UID,
    }

    /// Represents a fee tier configuration for the pool.
    /// Defines the tick spacing and fee rate for a specific tier.
    /// 
    /// # Fields
    /// * `tick_spacing` - The minimum distance between initialized ticks
    /// * `fee_rate` - The fee rate for this tier (in basis points)
    public struct FeeTier has copy, drop, store {
        tick_spacing: u32,
        fee_rate: u64,
    }

    /// Global configuration for the CLMM protocol.
    /// Contains all protocol-wide settings and parameters.
    /// 
    /// # Fields
    /// * `id` - Unique identifier for the configuration
    /// * `protocol_fee_rate` - Fee rate collected by the protocol
    /// * `unstaked_liquidity_fee_rate` - Fee rate for unstaked liquidity positions
    /// * `fee_tiers` - Map of fee tiers indexed by tick spacing
    /// * `acl` - Access control list for protocol roles
    /// * `package_version` - Current version of the protocol package
    /// * `alive_gauges` - Set of active gauge IDs
    public struct GlobalConfig has store, key {
        id: sui::object::UID,
        protocol_fee_rate: u64,
        unstaked_liquidity_fee_rate: u64,
        fee_tiers: sui::vec_map::VecMap<u32, FeeTier>,
        acl: clmm_pool::acl::ACL,
        package_version: u64,
        alive_gauges: sui::vec_set::VecSet<sui::object::ID>,
    }

    /// Event emitted when the configuration is initialized.
    /// 
    /// # Fields
    /// * `admin_cap_id` - ID of the created admin capability
    /// * `global_config_id` - ID of the created global configuration
    public struct InitConfigEvent has copy, drop {
        admin_cap_id: sui::object::ID,
        global_config_id: sui::object::ID,
    }

    /// Event emitted when the protocol fee rate is updated.
    /// 
    /// # Fields
    /// * `old_fee_rate` - Previous protocol fee rate
    /// * `new_fee_rate` - New protocol fee rate
    public struct UpdateFeeRateEvent has copy, drop {
        old_fee_rate: u64,
        new_fee_rate: u64,
    }

    /// Event emitted when the unstaked liquidity fee rate is updated.
    /// 
    /// # Fields
    /// * `old_fee_rate` - Previous unstaked liquidity fee rate
    /// * `new_fee_rate` - New unstaked liquidity fee rate
    public struct UpdateUnstakedLiquidityFeeRateEvent has copy, drop {
        old_fee_rate: u64,
        new_fee_rate: u64,
    }

    /// Event emitted when a new fee tier is added.
    /// 
    /// # Fields
    /// * `tick_spacing` - The tick spacing for the new tier
    /// * `fee_rate` - The fee rate for the new tier
    public struct AddFeeTierEvent has copy, drop {
        tick_spacing: u32,
        fee_rate: u64,
    }

    /// Event emitted when a fee tier is updated.
    /// 
    /// # Fields
    /// * `tick_spacing` - The tick spacing of the updated tier
    /// * `old_fee_rate` - Previous fee rate
    /// * `new_fee_rate` - New fee rate
    public struct UpdateFeeTierEvent has copy, drop {
        tick_spacing: u32,
        old_fee_rate: u64,
        new_fee_rate: u64,
    }

    /// Event emitted when a fee tier is deleted.
    /// 
    /// # Fields
    /// * `tick_spacing` - The tick spacing of the deleted tier
    /// * `fee_rate` - The fee rate of the deleted tier
    public struct DeleteFeeTierEvent has copy, drop {
        tick_spacing: u32,
        fee_rate: u64,
    }

    /// Event emitted when roles are set for a member.
    /// 
    /// # Fields
    /// * `member` - The address of the member
    /// * `roles` - The new roles bitmap
    public struct SetRolesEvent has copy, drop {
        member: address,
        roles: u128,
    }

    /// Event emitted when a role is added to a member.
    /// 
    /// # Fields
    /// * `member` - The address of the member
    /// * `role` - The added role ID
    public struct AddRoleEvent has copy, drop {
        member: address,
        role: u8,
    }

    /// Event emitted when a role is removed from a member.
    /// 
    /// # Fields
    /// * `member` - The address of the member
    /// * `role` - The removed role ID
    public struct RemoveRoleEvent has copy, drop {
        member: address,
        role: u8,
    }

    /// Event emitted when a member is removed from the ACL.
    /// 
    /// # Fields
    /// * `member` - The address of the removed member
    public struct RemoveMemberEvent has copy, drop {
        member: address,
    }

    /// Event emitted when the package version is updated.
    /// 
    /// # Fields
    /// * `new_version` - The new package version
    /// * `old_version` - The previous package version
    public struct SetPackageVersion has copy, drop {
        new_version: u64,
        old_version: u64,
    }

    /// Returns a reference to the ACL from the global configuration.
    /// 
    /// # Arguments
    /// * `config` - Reference to the global configuration
    /// 
    /// # Returns
    /// Reference to the ACL
    public fun acl(config: &GlobalConfig): &clmm_pool::acl::ACL {
        &config.acl
    }

    /// Adds a role to a member in the ACL.
    /// 
    /// # Arguments
    /// * `_admin_cap` - Reference to the admin capability
    /// * `config` - Mutable reference to the global configuration
    /// * `member_addr` - Address of the member
    /// * `role_id` - ID of the role to add
    public fun add_role(
        _admin_cap: &AdminCap,
        config: &mut GlobalConfig,
        member_addr: address,
        role_id: u8
    ) {
        checked_package_version(config);
        clmm_pool::acl::add_role(&mut config.acl, member_addr, role_id);
        let event = AddRoleEvent {
            member: member_addr,
            role: role_id,
        };
        sui::event::emit<AddRoleEvent>(event);
    }

    /// Returns the list of members in the ACL.
    /// 
    /// # Arguments
    /// * `config` - Reference to the global configuration
    /// 
    /// # Returns
    /// Vector of members
    public fun get_members(config: &GlobalConfig): vector<clmm_pool::acl::Member> {
        clmm_pool::acl::get_members(&config.acl)
    }

    /// Removes a member from the ACL.
    /// 
    /// # Arguments
    /// * `_admin_cap` - Reference to the admin capability
    /// * `config` - Mutable reference to the global configuration
    /// * `member_addr` - Address of the member to remove
    public fun remove_member(_admin_cap: &AdminCap, config: &mut GlobalConfig, member_addr: address) {
        checked_package_version(config);
        clmm_pool::acl::remove_member(&mut config.acl, member_addr);
        let event = RemoveMemberEvent { member: member_addr };
        sui::event::emit<RemoveMemberEvent>(event);
    }

    /// Removes a role from a member in the ACL.
    /// 
    /// # Arguments
    /// * `_admin_cap` - Reference to the admin capability
    /// * `config` - Mutable reference to the global configuration
    /// * `member_addr` - Address of the member
    /// * `role_id` - ID of the role to remove
    public fun remove_role(_admin_cap: &AdminCap, config: &mut GlobalConfig, member_addr: address, role_id: u8) {
        checked_package_version(config);
        clmm_pool::acl::remove_role(&mut config.acl, member_addr, role_id);
        let event = RemoveRoleEvent {
            member: member_addr,
            role: role_id,
        };
        sui::event::emit<RemoveRoleEvent>(event);
    }

    /// Sets roles for a member in the ACL.
    /// 
    /// # Arguments
    /// * `admin_cap` - Reference to the admin capability
    /// * `config` - Mutable reference to the global configuration
    /// * `member` - Address of the member
    /// * `roles` - Bitmap of roles to set
    public fun set_roles(admin_cap: &AdminCap, config: &mut GlobalConfig, member: address, roles: u128) {
        checked_package_version(config);
        clmm_pool::acl::set_roles(&mut config.acl, member, roles);
        let event = SetRolesEvent {
            member,
            roles,
        };
        sui::event::emit<SetRolesEvent>(event);
    }

    /// Adds a new fee tier to the global configuration.
    /// 
    /// # Arguments
    /// * `config` - Mutable reference to the global configuration
    /// * `tick_spacing` - The tick spacing for the new tier
    /// * `fee_rate` - The fee rate for the new tier
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Abort Conditions
    /// * If the fee rate exceeds the maximum allowed rate (error code: 3)
    /// * If a fee tier with the same tick spacing already exists (error code: 1)
    /// * If the caller does not have fee tier manager role
    public fun add_fee_tier(config: &mut GlobalConfig, tick_spacing: u32, fee_rate: u64, ctx: &mut sui::tx_context::TxContext) {
        assert!(fee_rate <= max_fee_rate(), 3);
        assert!(!sui::vec_map::contains<u32, FeeTier>(&config.fee_tiers, &tick_spacing), 1);
        checked_package_version(config);
        check_fee_tier_manager_role(config, sui::tx_context::sender(ctx));
        let fee_tier = FeeTier {
            tick_spacing,
            fee_rate,
        };
        sui::vec_map::insert<u32, FeeTier>(&mut config.fee_tiers, tick_spacing, fee_tier);
        let event = AddFeeTierEvent {
            tick_spacing,
            fee_rate,
        };
        sui::event::emit<AddFeeTierEvent>(event);
    }

    /// Checks if an address has the fee tier manager role.
    /// 
    /// # Arguments
    /// * `config` - Reference to the global configuration
    /// * `member` - Address to check
    /// 
    /// # Abort Conditions
    /// * If the address does not have the fee tier manager role (error code: 6)
    public fun check_fee_tier_manager_role(config: &GlobalConfig, member: address) {
        assert!(clmm_pool::acl::has_role(&config.acl, member, 1), 6);
    }

    /// Checks if an address has the partner manager role.
    /// 
    /// # Arguments
    /// * `config` - Reference to the global configuration
    /// * `member` - Address to check
    /// 
    /// # Abort Conditions
    /// * If the address does not have the partner manager role (error code: 7)
    public fun check_partner_manager_role(config: &GlobalConfig, member: address) {
        assert!(clmm_pool::acl::has_role(&config.acl, member, 3), 7);
    }

    /// Checks if an address has the pool manager role.
    /// 
    /// # Arguments
    /// * `config` - Reference to the global configuration
    /// * `member` - Address to check
    /// 
    /// # Abort Conditions
    /// * If the address does not have the pool manager role (error code: 5)
    public fun check_pool_manager_role(config: &GlobalConfig, member: address) {
        assert!(clmm_pool::acl::has_role(&config.acl, member, 0), 5);
    }

    /// Checks if an address has the protocol fee claim role.
    /// 
    /// # Arguments
    /// * `config` - Reference to the global configuration
    /// * `member` - Address to check
    /// 
    /// # Abort Conditions
    /// * If the address does not have the protocol fee claim role (error code: 9)
    public fun check_protocol_fee_claim_role(config: &GlobalConfig, member: address) {
        assert!(clmm_pool::acl::has_role(&config.acl, member, 2), 9);
    }

    /// Checks if an address has the rewarder manager role.
    /// 
    /// # Arguments
    /// * `config` - Reference to the global configuration
    /// * `member` - Address to check
    /// 
    /// # Abort Conditions
    /// * If the address does not have the rewarder manager role (error code: 8)
    public fun check_rewarder_manager_role(config: &GlobalConfig, member: address) {
        assert!(clmm_pool::acl::has_role(&config.acl, member, 4), 8);
    }

    /// Checks if the package version matches the expected version.
    /// 
    /// # Arguments
    /// * `config` - Reference to the global configuration
    /// 
    /// # Abort Conditions
    /// * If the package version is not 1 (error code: 10)
    public fun checked_package_version(config: &GlobalConfig) {
        assert!(config.package_version == 1, 10);
    }

    /// Returns the default unstaked fee rate.
    /// 
    /// # Returns
    /// The default unstaked fee rate as a u64
    public fun default_unstaked_fee_rate(): u64 {
        72057594037927935
    }

    /// Deletes a fee tier from the global configuration.
    /// 
    /// # Arguments
    /// * `config` - Mutable reference to the global configuration
    /// * `tick_spacing` - The tick spacing of the tier to delete
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Abort Conditions
    /// * If the fee tier does not exist (error code: 2)
    /// * If the caller does not have fee tier manager role
    public fun delete_fee_tier(config: &mut GlobalConfig, tick_spacing: u32, ctx: &mut sui::tx_context::TxContext) {
        assert!(sui::vec_map::contains<u32, FeeTier>(&config.fee_tiers, &tick_spacing), 2);
        checked_package_version(config);
        check_fee_tier_manager_role(config, sui::tx_context::sender(ctx));
        let (_, fee_tier) = sui::vec_map::remove<u32, FeeTier>(&mut config.fee_tiers, &tick_spacing);
        let removed_tier = fee_tier;
        let event = DeleteFeeTierEvent {
            tick_spacing,
            fee_rate: removed_tier.fee_rate,
        };
        sui::event::emit<DeleteFeeTierEvent>(event);
    }

    /// Returns the fee rate of a fee tier.
    /// 
    /// # Arguments
    /// * `fee_tier` - Reference to the fee tier
    /// 
    /// # Returns
    /// The fee rate as a u64
    public fun fee_rate(fee_tier: &FeeTier): u64 {
        fee_tier.fee_rate
    }

    /// Returns the denominator used for fee rate calculations.
    /// 
    /// # Returns
    /// The fee rate denominator (1000000)
    public fun fee_rate_denom(): u64 {
        1000000
    }

    /// Returns a reference to the fee tiers map.
    /// 
    /// # Arguments
    /// * `config` - Reference to the global configuration
    /// 
    /// # Returns
    /// Reference to the fee tiers map
    public fun fee_tiers(config: &GlobalConfig): &sui::vec_map::VecMap<u32, FeeTier> {
        &config.fee_tiers
    }

    /// Returns the fee rate for a given tick spacing.
    /// 
    /// # Arguments
    /// * `tick_spacing` - The tick spacing to get the fee rate for
    /// * `config` - Reference to the global configuration
    /// 
    /// # Returns
    /// The fee rate as a u64
    /// 
    /// # Abort Conditions
    /// * If the fee tier does not exist (error code: 2)
    public fun get_fee_rate(tick_spacing: u32, config: &GlobalConfig): u64 {
        assert!(sui::vec_map::contains<u32, FeeTier>(&config.fee_tiers, &tick_spacing), 2);
        sui::vec_map::get<u32, FeeTier>(&config.fee_tiers, &tick_spacing).fee_rate
    }

    /// Returns the protocol fee rate.
    /// 
    /// # Arguments
    /// * `config` - Reference to the global configuration
    /// 
    /// # Returns
    /// The protocol fee rate as a u64
    public fun get_protocol_fee_rate(config: &GlobalConfig): u64 {
        config.protocol_fee_rate
    }

    /// Initializes the global configuration and creates the admin capability.
    /// 
    /// # Arguments
    /// * `ctx` - Mutable reference to the transaction context
    fun init(ctx: &mut sui::tx_context::TxContext) {
        let mut global_config = GlobalConfig {
            id: sui::object::new(ctx),
            protocol_fee_rate : 2000, 
            unstaked_liquidity_fee_rate : 0, 
            fee_tiers: sui::vec_map::empty<u32, FeeTier>(),
            acl: clmm_pool::acl::new(ctx),
            package_version: 1,
            alive_gauges: sui::vec_set::empty<sui::object::ID>(),
        };
        let admin_cap = AdminCap { id: sui::object::new(ctx) };
        set_roles(&admin_cap, &mut global_config, sui::tx_context::sender(ctx), 27);
        let init_event = InitConfigEvent {
            admin_cap_id: sui::object::id<AdminCap>(&admin_cap),
            global_config_id: sui::object::id<GlobalConfig>(&global_config),
        };
        sui::transfer::transfer<AdminCap>(admin_cap, sui::tx_context::sender(ctx));
        sui::transfer::share_object<GlobalConfig>(global_config);
        sui::event::emit<InitConfigEvent>(init_event);
    }

    /// Checks if a gauge is currently active.
    /// 
    /// # Arguments
    /// * `config` - Reference to the global configuration
    /// * `gauge_id` - The ID of the gauge to check
    /// 
    /// # Returns
    /// True if the gauge is active, false otherwise
    public fun is_gauge_alive(config: &GlobalConfig, gauge_id: sui::object::ID): bool {
        sui::vec_set::contains<sui::object::ID>(&config.alive_gauges, &gauge_id)
    }

    /// Returns the maximum allowed fee rate.
    /// 
    /// # Returns
    /// The maximum fee rate as a u64 (200000)
    public fun max_fee_rate(): u64 {
        200000
    }

    /// Returns the maximum allowed protocol fee rate.
    /// 
    /// # Returns
    /// The maximum protocol fee rate as a u64 (3000)
    public fun max_protocol_fee_rate(): u64 {
        3000
    }

    /// Returns the maximum allowed unstaked liquidity fee rate.
    /// 
    /// # Returns
    /// The maximum unstaked liquidity fee rate as a u64 (10000)
    public fun max_unstaked_liquidity_fee_rate(): u64 {
        10000
    }

    /// Returns the protocol fee rate.
    /// 
    /// # Arguments
    /// * `config` - Reference to the global configuration
    /// 
    /// # Returns
    /// The protocol fee rate as a u64
    public fun protocol_fee_rate(config: &GlobalConfig): u64 {
        config.protocol_fee_rate
    }

    /// Returns the denominator used for protocol fee rate calculations.
    /// 
    /// # Returns
    /// The protocol fee rate denominator (10000)
    public fun protocol_fee_rate_denom(): u64 {
        10000
    }

    /// Returns the tick spacing of a fee tier.
    /// 
    /// # Arguments
    /// * `fee_tier` - Reference to the fee tier
    /// 
    /// # Returns
    /// The tick spacing as a u32
    public fun tick_spacing(fee_tier: &FeeTier): u32 {
        fee_tier.tick_spacing
    }

    /// Returns the unstaked liquidity fee rate.
    /// 
    /// # Arguments
    /// * `config` - Reference to the global configuration
    /// 
    /// # Returns
    /// The unstaked liquidity fee rate as a u64
    public fun unstaked_liquidity_fee_rate(config: &GlobalConfig): u64 {
        config.unstaked_liquidity_fee_rate
    }

    /// Returns the denominator used for unstaked liquidity fee rate calculations.
    /// 
    /// # Returns
    /// The unstaked liquidity fee rate denominator (10000)
    public fun unstaked_liquidity_fee_rate_denom(): u64 {
        10000
    }

    /// Updates a fee tier in the global configuration.
    /// 
    /// # Arguments
    /// * `global_config` - Mutable reference to the global configuration
    /// * `tick_spacing` - The tick spacing of the tier to update
    /// * `new_fee_rate` - The new fee rate
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Abort Conditions
    /// * If the fee tier does not exist (error code: 2)
    /// * If the new fee rate exceeds the maximum allowed rate (error code: 3)
    /// * If the caller does not have fee tier manager role
    public fun update_fee_tier(
        global_config: &mut GlobalConfig,
        tick_spacing: u32,
        new_fee_rate: u64,
        ctx: &mut sui::tx_context::TxContext
    ) {
        assert!(sui::vec_map::contains<u32, FeeTier>(&global_config.fee_tiers, &tick_spacing), 2);
        assert!(new_fee_rate <= max_fee_rate(), 3);
        checked_package_version(global_config);
        check_fee_tier_manager_role(global_config, sui::tx_context::sender(ctx));
        let fee_tier = sui::vec_map::get_mut<u32, FeeTier>(&mut global_config.fee_tiers, &tick_spacing);
        fee_tier.fee_rate = new_fee_rate;
        let event = UpdateFeeTierEvent {
            tick_spacing,
            old_fee_rate: fee_tier.fee_rate,
            new_fee_rate,
        };
        sui::event::emit<UpdateFeeTierEvent>(event);
    }

    /// Updates the liveness status of gauges.
    /// 
    /// # Arguments
    /// * `global_config` - Mutable reference to the global configuration
    /// * `gauge_ids` - Vector of gauge IDs to update
    /// * `is_alive` - Whether the gauges should be marked as alive
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Abort Conditions
    /// * If the gauge IDs vector is empty
    /// * If the caller does not have pool manager role
    public fun update_gauge_liveness(
        global_config: &mut GlobalConfig,
        gauge_ids: vector<sui::object::ID>,
        is_alive: bool,
        ctx: &mut sui::tx_context::TxContext
    ) {
        let mut index = 0;
        let length = std::vector::length<sui::object::ID>(&gauge_ids);
        checked_package_version(global_config);
        check_pool_manager_role(global_config, sui::tx_context::sender(ctx));
        assert!(length > 0, 9223373316755030015);

        if (is_alive) {
            while (index < length) {
                if (!sui::vec_set::contains<sui::object::ID>(
                    &global_config.alive_gauges,
                    std::vector::borrow<sui::object::ID>(&gauge_ids, index)
                )) {
                    let gauge_id = *std::vector::borrow<sui::object::ID>(&gauge_ids, index);
                    sui::vec_set::insert<sui::object::ID>(&mut global_config.alive_gauges, gauge_id);
                };
                index = index + 1;
            };
        } else {
            while (index < length) {
                if (sui::vec_set::contains<sui::object::ID>(
                    &global_config.alive_gauges,
                    std::vector::borrow<sui::object::ID>(&gauge_ids, index)
                )) {
                    let gauge_id = std::vector::borrow<sui::object::ID>(&gauge_ids, index);
                    sui::vec_set::remove<sui::object::ID>(&mut global_config.alive_gauges, gauge_id);
                };
                index = index + 1;
            };
        };
    }

    /// Updates the package version.
    /// 
    /// # Arguments
    /// * `admin_cap` - Reference to the admin capability
    /// * `global_config` - Mutable reference to the global configuration
    /// * `new_version` - The new package version
    public fun update_package_version(admin_cap: &AdminCap, global_config: &mut GlobalConfig, new_version: u64) {
        global_config.package_version = new_version;
        let event = SetPackageVersion {
            new_version,
            old_version: global_config.package_version,
        };
        sui::event::emit<SetPackageVersion>(event);
    }

    /// Updates the protocol fee rate.
    /// 
    /// # Arguments
    /// * `global_config` - Mutable reference to the global configuration
    /// * `new_fee_rate` - The new protocol fee rate
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Abort Conditions
    /// * If the new fee rate exceeds the maximum allowed rate (error code: 4)
    /// * If the caller does not have pool manager role
    public fun update_protocol_fee_rate(global_config: &mut GlobalConfig, new_fee_rate: u64, ctx: &mut sui::tx_context::TxContext) {
        assert!(new_fee_rate <= 3000, 4);
        checked_package_version(global_config);
        check_pool_manager_role(global_config, sui::tx_context::sender(ctx));
        global_config.protocol_fee_rate = new_fee_rate;
        let event = UpdateFeeRateEvent {
            old_fee_rate: global_config.protocol_fee_rate,
            new_fee_rate,
        };
        sui::event::emit<UpdateFeeRateEvent>(event);
    }

    /// Updates the unstaked liquidity fee rate.
    /// 
    /// # Arguments
    /// * `global_config` - Mutable reference to the global configuration
    /// * `new_fee_rate` - The new unstaked liquidity fee rate
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Abort Conditions
    /// * If the new fee rate exceeds the maximum allowed rate (error code: 11)
    /// * If the caller does not have pool manager role
    public fun update_unstaked_liquidity_fee_rate(
        global_config: &mut GlobalConfig,
        new_fee_rate: u64,
        ctx: &mut sui::tx_context::TxContext
    ) {
        assert!(new_fee_rate <= max_unstaked_liquidity_fee_rate(), 11);
        checked_package_version(global_config);
        check_pool_manager_role(global_config, sui::tx_context::sender(ctx));
        global_config.unstaked_liquidity_fee_rate = new_fee_rate;
        let event = UpdateUnstakedLiquidityFeeRateEvent {
            old_fee_rate: global_config.unstaked_liquidity_fee_rate,
            new_fee_rate,
        };
        sui::event::emit<UpdateUnstakedLiquidityFeeRateEvent>(event);
    }

    #[test_only]
    public fun test_init(ctx: &mut sui::tx_context::TxContext) {
        let mut global_config = GlobalConfig {
            id: sui::object::new(ctx),
            protocol_fee_rate: 2000,
            unstaked_liquidity_fee_rate: 0,
            fee_tiers: sui::vec_map::empty<u32, FeeTier>(),
            acl: clmm_pool::acl::new(ctx),
            package_version: 1,
            alive_gauges: sui::vec_set::empty<sui::object::ID>(),
        };
        let admin_cap = AdminCap { id: sui::object::new(ctx) };
        set_roles(&admin_cap, &mut global_config, sui::tx_context::sender(ctx), 27);
        sui::transfer::share_object(global_config);
        sui::transfer::transfer(admin_cap, sui::tx_context::sender(ctx));
    }

    #[test]
    fun test_init_fun() {
        let admin = @0x123;
        let mut scenario = sui::test_scenario::begin(admin);
        {
            init(scenario.ctx());
        };

       scenario.next_tx( admin);
        {
            let global_config = scenario.take_shared<GlobalConfig>();
            assert!(protocol_fee_rate(&global_config) == 2000, 1);
            assert!(unstaked_liquidity_fee_rate(&global_config) == 0, 2);
            sui::test_scenario::return_shared(global_config);
        };

        scenario.end();
    }
}

