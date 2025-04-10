/// Partner module for the CLMM (Concentrated Liquidity Market Maker) pool system.
/// This module provides functionality for:
/// * Managing partner relationships and permissions
/// * Handling partner registration and validation
/// * Managing partner-specific settings and configurations
/// * Controlling partner access to pool operations
/// 
/// The module implements:
/// * Partner registration and management
/// * Partner permission control
/// * Partner-specific fee handling
/// * Partner access validation
/// 
/// # Key Concepts
/// * Partner Registration - Process of adding a new partner to the system
/// * Partner Permissions - Access rights and capabilities granted to partners
/// * Partner Fees - Fee structures and calculations specific to partners
/// * Partner Access - Validation and control of partner operations
/// 
/// # Events
/// * Partner registration events
/// * Partner permission update events
/// * Partner fee update events
/// * Partner access control events
module clmm_pool::partner {
    /// Represents the collection of registered partners in the system.
    /// This structure maintains a mapping of partner names to their unique identifiers.
    /// 
    /// # Fields
    /// * `id` - Unique identifier for the partners collection
    /// * `partners` - Vector map containing partner names and their corresponding IDs
    public struct Partners has key {
        id: sui::object::UID,
        partners: sui::vec_map::VecMap<std::string::String, sui::object::ID>,
    }

    /// Represents the capability object for a partner.
    /// This structure is used to control partner access and permissions.
    /// 
    /// # Fields
    /// * `id` - Unique identifier for the capability object
    /// * `name` - Name of the partner
    /// * `partner_id` - ID of the associated partner
    public struct PartnerCap has store, key {
        id: sui::object::UID,
        name: std::string::String,
        partner_id: sui::object::ID,
    }

    /// Represents a partner in the system with their settings and balances.
    /// This structure contains all partner-specific data and configurations.
    /// 
    /// # Fields
    /// * `id` - Unique identifier for the partner
    /// * `name` - Name of the partner
    /// * `ref_fee_rate` - Referral fee rate (in basis points)
    /// * `start_time` - Start time of partner's active period
    /// * `end_time` - End time of partner's active period
    /// * `balances` - Collection of token balances for the partner
    public struct Partner has store, key {
        id: sui::object::UID,
        name: std::string::String,
        ref_fee_rate: u64,
        start_time: u64,
        end_time: u64,
        balances: sui::bag::Bag,
    }

    /// Event emitted when the partner system is initialized.
    /// 
    /// # Fields
    /// * `partners_id` - ID of the created partners collection
    public struct InitPartnerEvent has copy, drop {
        partners_id: sui::object::ID,
    }

    /// Event emitted when a new partner is created.
    /// 
    /// # Fields
    /// * `recipient` - Address of the partner capability recipient
    /// * `partner_id` - ID of the created partner
    /// * `partner_cap_id` - ID of the created partner capability
    /// * `ref_fee_rate` - Initial referral fee rate
    /// * `name` - Name of the partner
    /// * `start_time` - Start time of partner's active period
    /// * `end_time` - End time of partner's active period
    public struct CreatePartnerEvent has copy, drop {
        recipient: address,
        partner_id: sui::object::ID,
        partner_cap_id: sui::object::ID,
        ref_fee_rate: u64,
        name: std::string::String,
        start_time: u64,
        end_time: u64,
    }

    /// Event emitted when a partner's referral fee rate is updated.
    /// 
    /// # Fields
    /// * `partner_id` - ID of the partner
    /// * `old_fee_rate` - Previous referral fee rate
    /// * `new_fee_rate` - New referral fee rate
    public struct UpdateRefFeeRateEvent has copy, drop {
        partner_id: sui::object::ID,
        old_fee_rate: u64,
        new_fee_rate: u64,
    }

    /// Event emitted when a partner's time range is updated.
    /// 
    /// # Fields
    /// * `partner_id` - ID of the partner
    /// * `start_time` - New start time of partner's active period
    /// * `end_time` - New end time of partner's active period
    public struct UpdateTimeRangeEvent has copy, drop {
        partner_id: sui::object::ID,
        start_time: u64,
        end_time: u64,
    }

    /// Event emitted when a partner receives referral fees.
    /// 
    /// # Fields
    /// * `partner_id` - ID of the partner
    /// * `amount` - Amount of fees received
    /// * `type_name` - Type of token for the fees
    public struct ReceiveRefFeeEvent has copy, drop {
        partner_id: sui::object::ID,
        amount: u64,
        type_name: std::string::String,
    }

    /// Event emitted when a partner claims their referral fees.
    /// 
    /// # Fields
    /// * `partner_id` - ID of the partner
    /// * `amount` - Amount of fees claimed
    /// * `type_name` - Type of token for the fees
    public struct ClaimRefFeeEvent has copy, drop {
        partner_id: sui::object::ID,
        amount: u64,
        type_name: std::string::String,
    }
    
    /// Returns a reference to the partner's token balances.
    /// This function provides access to the partner's balance collection.
    /// 
    /// # Arguments
    /// * `partner` - Reference to the partner structure
    /// 
    /// # Returns
    /// Reference to the partner's balance collection
    public fun balances(partner: &Partner): &sui::bag::Bag {
        &partner.balances
    }

    /// Claims accumulated referral fees for a specific token type.
    /// This function allows a partner to withdraw their earned referral fees.
    /// 
    /// # Arguments
    /// * `global_config` - Reference to the global configuration
    /// * `partner_cap` - Reference to the partner's capability object
    /// * `partner` - Mutable reference to the partner structure
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Abort Conditions
    /// * If the package version check fails
    /// * If the partner capability ID doesn't match the partner ID (error code: 3)
    /// * If the partner doesn't have a balance for the specified token type (error code: 4)
    /// 
    /// # Events
    /// * Emits ClaimRefFeeEvent with the claimed amount and token type
    public fun claim_ref_fee<CoinType>(
        global_config: &clmm_pool::config::GlobalConfig,
        partner_cap: &PartnerCap,
        partner: &mut Partner,
        ctx: &mut sui::tx_context::TxContext
    ) {
        clmm_pool::config::checked_package_version(global_config);
        assert!(partner_cap.partner_id == sui::object::id<Partner>(partner), 3);
        let type_name = std::string::from_ascii(std::type_name::into_string(std::type_name::get<CoinType>()));
        assert!(sui::bag::contains<std::string::String>(&partner.balances, type_name), 4);
        let balance = sui::bag::remove<std::string::String, sui::balance::Balance<CoinType>>(&mut partner.balances, type_name);
        let amount = sui::balance::value<CoinType>(&balance);
        sui::transfer::public_transfer<sui::coin::Coin<CoinType>>(
            sui::coin::from_balance<CoinType>(balance, ctx),
            sui::tx_context::sender(ctx)
        );
        let event = ClaimRefFeeEvent {
            partner_id: sui::object::id<Partner>(partner),
            amount,
            type_name,
        };
        sui::event::emit<ClaimRefFeeEvent>(event);
    }
    
    /// Creates a new partner in the system with specified parameters.
    /// This function initializes a new partner with their settings and creates necessary capability objects.
    /// 
    /// # Arguments
    /// * `global_config` - Reference to the global configuration
    /// * `partners` - Mutable reference to the partners collection
    /// * `name` - Name of the new partner
    /// * `ref_fee_rate` - Referral fee rate in basis points (1/10000)
    /// * `start_time` - Start time of partner's active period
    /// * `end_time` - End time of partner's active period
    /// * `recipient` - Address to receive the partner capability object
    /// * `clock` - Reference to the Sui clock
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Abort Conditions
    /// * If the package version check fails
    /// * If the caller doesn't have the partner manager role
    /// * If end_time is less than or equal to start_time (error code: 6)
    /// * If start_time is less than current time (error code: 7)
    /// * If ref_fee_rate is greater than or equal to 10000 (error code: 2)
    /// * If name is empty (error code: 5)
    /// * If a partner with the same name already exists (error code: 5)
    /// 
    /// # Events
    /// * Emits CreatePartnerEvent with the new partner's details
    /// 
    /// # Details
    /// * Creates a new Partner object with empty balances
    /// * Creates a PartnerCap object for access control
    /// * Shares the Partner object
    /// * Transfers the PartnerCap to the specified recipient
    public fun create_partner(
        global_config: &clmm_pool::config::GlobalConfig,
        partners: &mut Partners,
        name: std::string::String,
        ref_fee_rate: u64,
        start_time: u64,
        end_time: u64,
        recipient: address,
        clock: &sui::clock::Clock,
        ctx: &mut sui::tx_context::TxContext
    ) {
        assert!(end_time > start_time, 6);
        assert!(start_time >= sui::clock::timestamp_ms(clock) / 1000, 7);
        assert!(ref_fee_rate < 10000, 2);
        assert!(!std::string::is_empty(&name), 5);
        assert!(!sui::vec_map::contains<std::string::String, sui::object::ID>(&partners.partners, &name), 5);
        clmm_pool::config::checked_package_version(global_config);
        clmm_pool::config::check_partner_manager_role(global_config, sui::tx_context::sender(ctx));
        let partner = Partner {
            id: sui::object::new(ctx),
            name,
            ref_fee_rate,
            start_time,
            end_time,
            balances: sui::bag::new(ctx),
        };
        let partner_id = sui::object::id<Partner>(&partner);
        let partner_cap = PartnerCap {
            id: sui::object::new(ctx),
            name,
            partner_id: partner_id,
        };
        sui::vec_map::insert<std::string::String, sui::object::ID>(&mut partners.partners, name, partner_id);
        sui::transfer::share_object<Partner>(partner);
        let partner_cap_id = sui::object::id<PartnerCap>(&partner_cap);
        sui::transfer::transfer<PartnerCap>(partner_cap, recipient);
        let create_event = CreatePartnerEvent {
            recipient,
            partner_id: partner_id,
            partner_cap_id,
            ref_fee_rate,
            name,
            start_time,
            end_time,
        };
        sui::event::emit<CreatePartnerEvent>(create_event);
    }

    /// Returns the current referral fee rate for a partner based on the current time.
    /// This function checks if the partner is currently active and returns their fee rate.
    /// 
    /// # Arguments
    /// * `partner` - Reference to the partner structure
    /// * `current_time` - Current timestamp to check against partner's time range
    /// 
    /// # Returns
    /// * The partner's referral fee rate if they are currently active
    /// * 0 if the partner is not active (outside their time range)
    public fun current_ref_fee_rate(partner: &Partner, current_time: u64): u64 {
        if (partner.start_time > current_time || partner.end_time <= current_time) {
            return 0
        };
        partner.ref_fee_rate
    }

    /// Returns the end time of a partner's active period.
    /// 
    /// # Arguments
    /// * `partner` - Reference to the partner structure
    /// 
    /// # Returns
    /// The timestamp when the partner's active period ends
    public fun end_time(partner: &Partner): u64 {
        partner.end_time
    }

    /// Initializes the partner system by creating the initial partners collection.
    /// This function is called once during module deployment.
    /// 
    /// # Arguments
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Events
    /// * Emits InitPartnerEvent with the ID of the created partners collection
    /// 
    /// # Details
    /// * Creates a new Partners structure with empty vector map
    /// * Shares the Partners object
    fun init(ctx: &mut sui::tx_context::TxContext) {
        let partners = Partners {
            id: sui::object::new(ctx),
            partners: sui::vec_map::empty<std::string::String, sui::object::ID>(),
        };
        let partners_id = sui::object::id<Partners>(&partners);
        sui::transfer::share_object<Partners>(partners);
        let event = InitPartnerEvent { partners_id };
        sui::event::emit<InitPartnerEvent>(event);
    }

    /// Returns the name of a partner.
    /// 
    /// # Arguments
    /// * `partner` - Reference to the partner structure
    /// 
    /// # Returns
    /// The partner's name as a string
    public fun name(partner: &Partner): std::string::String {
        partner.name
    }

    /// Adds referral fees to a partner's balance for a specific token type.
    /// This function handles both new and existing token balances.
    /// 
    /// # Arguments
    /// * `partner` - Mutable reference to the partner structure
    /// * `balance` - Balance of tokens to add to the partner's fees
    /// 
    /// # Events
    /// * Emits ReceiveRefFeeEvent with the received amount and token type
    /// 
    /// # Details
    /// * If the token type already exists in the partner's balances, adds to existing balance
    /// * If the token type is new, creates a new balance entry
    public fun receive_ref_fee<CoinType>(partner: &mut Partner, balance: sui::balance::Balance<CoinType>) {
        let type_name = std::string::from_ascii(std::type_name::into_string(std::type_name::get<CoinType>()));
        let amount = sui::balance::value<CoinType>(&balance);
        if (sui::bag::contains<std::string::String>(&partner.balances, type_name)) {
            sui::balance::join<CoinType>(
                sui::bag::borrow_mut<std::string::String, sui::balance::Balance<CoinType>>(&mut partner.balances, type_name),
                balance
            );
        } else {
            sui::bag::add<std::string::String, sui::balance::Balance<CoinType>>(&mut partner.balances, type_name, balance);
        };
        let event = ReceiveRefFeeEvent {
            partner_id: sui::object::id<Partner>(partner),
            amount,
            type_name,
        };
        sui::event::emit<ReceiveRefFeeEvent>(event);
    }

    /// Returns the referral fee rate of a partner.
    /// 
    /// # Arguments
    /// * `partner` - Reference to the partner structure
    /// 
    /// # Returns
    /// The partner's referral fee rate in basis points
    public fun ref_fee_rate(partner: &Partner): u64 {
        partner.ref_fee_rate
    }

    /// Returns the start time of a partner's active period.
    /// 
    /// # Arguments
    /// * `partner` - Reference to the partner structure
    /// 
    /// # Returns
    /// The timestamp when the partner's active period starts
    public fun start_time(partner: &Partner): u64 {
        partner.start_time
    }

    /// Updates a partner's referral fee rate.
    /// This function can only be called by an account with the partner manager role.
    /// 
    /// # Arguments
    /// * `global_config` - Reference to the global configuration
    /// * `partner` - Mutable reference to the partner structure
    /// * `new_fee_rate` - New referral fee rate in basis points
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Abort Conditions
    /// * If the package version check fails
    /// * If the caller doesn't have the partner manager role
    /// * If new_fee_rate is greater than or equal to 10000 (error code: 2)
    /// 
    /// # Events
    /// * Emits UpdateRefFeeRateEvent with the old and new fee rates
    public fun update_ref_fee_rate(
        global_config: &clmm_pool::config::GlobalConfig,
        partner: &mut Partner,
        new_fee_rate: u64,
        ctx: &mut sui::tx_context::TxContext
    ) {
        assert!(new_fee_rate < 10000, 2);
        clmm_pool::config::checked_package_version(global_config);
        clmm_pool::config::check_partner_manager_role(global_config, sui::tx_context::sender(ctx));
        partner.ref_fee_rate = new_fee_rate;
        let event = UpdateRefFeeRateEvent {
            partner_id: sui::object::id<Partner>(partner),
            old_fee_rate: partner.ref_fee_rate,
            new_fee_rate,
        };
        sui::event::emit<UpdateRefFeeRateEvent>(event);
    }

    /// Updates a partner's active time range.
    /// This function can only be called by an account with the partner manager role.
    /// 
    /// # Arguments
    /// * `global_config` - Reference to the global configuration
    /// * `partner` - Mutable reference to the partner structure
    /// * `start_time` - New start time of partner's active period
    /// * `end_time` - New end time of partner's active period
    /// * `clock` - Reference to the Sui clock
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Abort Conditions
    /// * If the package version check fails
    /// * If the caller doesn't have the partner manager role
    /// * If end_time is less than or equal to start_time (error code: 6)
    /// * If end_time is less than current time (error code: 6)
    /// 
    /// # Events
    /// * Emits UpdateTimeRangeEvent with the new time range
    public fun update_time_range(
        global_config: &clmm_pool::config::GlobalConfig,
        partner: &mut Partner,
        start_time: u64,
        end_time: u64,
        clock: &sui::clock::Clock,
        ctx: &mut sui::tx_context::TxContext
    ) {
        assert!(end_time > start_time, 6);
        assert!(end_time > sui::clock::timestamp_ms(clock) / 1000, 6);
        clmm_pool::config::checked_package_version(global_config);
        clmm_pool::config::check_partner_manager_role(global_config, sui::tx_context::sender(ctx));
        partner.start_time = start_time;
        partner.end_time = end_time;
        let event = UpdateTimeRangeEvent {
            partner_id: sui::object::id<Partner>(partner),
            start_time,
            end_time,
        };
        sui::event::emit<UpdateTimeRangeEvent>(event);
    }

    /// Returns whether the partners collection is empty.
    /// 
    /// # Arguments
    /// * `partners` - Reference to the partners collection
    /// 
    /// # Returns
    /// True if the collection is empty, false otherwise
    public fun is_empty(partners: &Partners): bool {
        sui::vec_map::is_empty(&partners.partners)
    }

    #[test_only]
    public fun test_init(ctx: &mut sui::tx_context::TxContext) {
        let partners = Partners {
            id: sui::object::new(ctx),
            partners: sui::vec_map::empty<std::string::String, sui::object::ID>(),
        };
        sui::transfer::share_object(partners);
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
            let partners = scenario.take_shared<Partners>();
            
            // Check that partners collection is empty
            assert!(sui::vec_map::is_empty(&partners.partners), 1);
            
            sui::test_scenario::return_shared(partners);
        };

        scenario.end();
    }
}
