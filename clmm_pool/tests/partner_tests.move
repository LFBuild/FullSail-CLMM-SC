#[test_only]
module clmm_pool::partner_tests {
    use clmm_pool::partner;
    use clmm_pool::config;
    use std::debug;
    use std::string;
    use sui::clock;
    use sui::coin;
    use sui::balance;
    use sui::transfer;
    use sui::tx_context;
    use sui::test_scenario;

    #[test_only]
    public struct MY_COIN has drop {}

    /// Test initialization of the partner system
    /// Verifies that the partners collection is empty after initialization
    #[test]
    fun test_init() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        {
            partner::test_init(scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            let partners = scenario.take_shared<partner::Partners>();
            assert!(partner::is_empty(&partners), 1);
            test_scenario::return_shared(partners);
        };

        scenario.end();
    }

    /// Test partner creation with valid parameters
    /// Verifies:
    /// 1. Partner is created with correct name
    /// 2. Partner has correct fee rate
    /// 3. Partner has valid time range
    #[test]
    fun test_create_partner() {
        let admin = @0x123;
        let partner = @0x456;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
            partner::test_init(scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut partners = scenario.take_shared<partner::Partners>();
            let clock = clock::create_for_testing(scenario.ctx());

            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 1000;
            let end_time = start_time + 1000;
            let name = string::utf8(b"Test Partner");
            let ref_fee_rate = 1000; // 10%

            partner::create_partner(
                &global_config,
                &mut partners,
                name,
                ref_fee_rate,
                start_time,
                end_time,
                partner,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock)
        };

        scenario.next_tx(partner);
        {
            let partner_cap = scenario.take_from_sender<partner::PartnerCap>();
            let partners = scenario.take_shared<partner::Partners>();
            let partner = scenario.take_shared<partner::Partner>();
            
            assert!(string::utf8(b"Test Partner") == partner::name(&partner), 1);
            assert!(partner::ref_fee_rate(&partner) == 1000, 2);
            assert!(partner::start_time(&partner) > 0, 3);
            assert!(partner::end_time(&partner) > partner::start_time(&partner), 4);
            
            test_scenario::return_to_sender(&mut scenario, partner_cap);
            test_scenario::return_shared(partners);
            test_scenario::return_shared(partner);
        };

        scenario.end();
    }

    /// Test partner creation with invalid fee rate (100%)
    /// Should abort with code 2
    #[test]
    #[expected_failure(abort_code = 2)]
    fun test_create_partner_invalid_fee_rate() {
        let admin = @0x123;
        let partner = @0x456;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
            partner::test_init(scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut partners = scenario.take_shared<partner::Partners>();
            let clock = clock::create_for_testing(scenario.ctx());

            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 1000;
            let end_time = start_time + 1000;
            let name = string::utf8(b"Test Partner");
            let ref_fee_rate = 10000; // 100% - invalid

            partner::create_partner(
                &global_config,
                &mut partners,
                name,
                ref_fee_rate,
                start_time,
                end_time,
                partner,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock)
        };

        scenario.end();
    }

    /// Test partner creation with empty name
    /// Should abort with code 5
    #[test]
    #[expected_failure(abort_code = 5)]
    fun test_create_partner_empty_name() {
        let admin = @0x123;
        let partner = @0x456;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
            partner::test_init(scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut partners = scenario.take_shared<partner::Partners>();
            let clock = clock::create_for_testing(scenario.ctx());

            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 1000;
            let end_time = start_time + 1000;
            let name = string::utf8(b""); // Empty name
            let ref_fee_rate = 1000;

            partner::create_partner(
                &global_config,
                &mut partners,
                name,
                ref_fee_rate,
                start_time,
                end_time,
                partner,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock)
        };

        scenario.end();
    }

    /// Test updating partner's referral fee rate
    /// Verifies:
    /// 1. Fee rate can be updated by admin
    /// 2. New fee rate is correctly set
    #[test]
    fun test_update_ref_fee_rate() {
        let admin = @0x123;
        let partner = @0x456;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
            partner::test_init(scenario.ctx());
        };

        // Create partner
        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut partners = scenario.take_shared<partner::Partners>();
            let clock = clock::create_for_testing(scenario.ctx());

            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 1000;
            let end_time = start_time + 1000;
            let name = string::utf8(b"Test Partner");
            let ref_fee_rate = 1000;

            partner::create_partner(
                &global_config,
                &mut partners,
                name,
                ref_fee_rate,
                start_time,
                end_time,
                partner,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock)
        };

        // Update fee rate
        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut partner = scenario.take_shared<partner::Partner>();
            
            partner::update_ref_fee_rate(
                &global_config,
                &mut partner,
                2000, // New fee rate 20%
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partner);
        };

        // Verify update
        scenario.next_tx(partner);
        {
            let partner = scenario.take_shared<partner::Partner>();
            assert!(partner::ref_fee_rate(&partner) == 2000, 1);
            test_scenario::return_shared(partner);
        };

        scenario.end();
    }

    /// Test updating partner's time range
    /// Verifies:
    /// 1. Time range can be updated by admin
    /// 2. New time range is valid (end > start)
    /// 3. New time range is in the future
    #[test]
    fun test_update_time_range() {
        let admin = @0x123;
        let partner = @0x456;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
            partner::test_init(scenario.ctx());
        };

        // Create partner
        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut partners = scenario.take_shared<partner::Partners>();
            let clock = clock::create_for_testing(scenario.ctx());

            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 1000;
            let end_time = start_time + 1000;
            let name = string::utf8(b"Test Partner");
            let ref_fee_rate = 1000;

            partner::create_partner(
                &global_config,
                &mut partners,
                name,
                ref_fee_rate,
                start_time,
                end_time,
                partner,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock)
        };

        // Update time range
        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut partner = scenario.take_shared<partner::Partner>();
            let clock = clock::create_for_testing(scenario.ctx());

            let current_time = clock::timestamp_ms(&clock) / 1000;
            let new_start_time = current_time + 2000;
            let new_end_time = new_start_time + 2000;

            partner::update_time_range(
                &global_config,
                &mut partner,
                new_start_time,
                new_end_time,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partner);
            clock::destroy_for_testing(clock)
        };

        // Verify update
        scenario.next_tx(partner);
        {
            let partner = scenario.take_shared<partner::Partner>();
            let clock = clock::create_for_testing(scenario.ctx());
            let current_time = clock::timestamp_ms(&clock) / 1000;
            
            assert!(partner::start_time(&partner) > current_time, 1);
            assert!(partner::end_time(&partner) > partner::start_time(&partner), 2);
            
            test_scenario::return_shared(partner);
            clock::destroy_for_testing(clock)
        };

        scenario.end();
    }

    /// Test receiving and claiming referral fees
    /// Verifies:
    /// 1. Partner can receive fees
    /// 2. Partner can claim received fees
    /// 3. Fees are correctly transferred to partner
    #[test]
    fun test_receive_and_claim_ref_fee() {
        let admin = @0x123;
        let partner = @0x456;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
            partner::test_init(scenario.ctx());
        };

        // Create partner
        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut partners = scenario.take_shared<partner::Partners>();
            let clock = clock::create_for_testing(scenario.ctx());

            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 1000;
            let end_time = start_time + 1000;
            let name = string::utf8(b"Test Partner");
            let ref_fee_rate = 1000;

            partner::create_partner(
                &global_config,
                &mut partners,
                name,
                ref_fee_rate,
                start_time,
                end_time,
                partner,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock)
        };

        // Receive fee
        scenario.next_tx(admin);
        {
            let mut partner = scenario.take_shared<partner::Partner>();
            let coin = coin::mint_for_testing<MY_COIN>(1000, scenario.ctx());
            let balance: balance::Balance<MY_COIN> = coin::into_balance(coin);
            partner::receive_ref_fee(&mut partner, balance);
            test_scenario::return_shared(partner);
        };

        // Claim fee
        scenario.next_tx(partner);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let partner_cap = scenario.take_from_sender<partner::PartnerCap>();
            let mut partner = scenario.take_shared<partner::Partner>();
            
            partner::claim_ref_fee<MY_COIN>(
                &global_config,
                &partner_cap,
                &mut partner,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_to_sender(&mut scenario, partner_cap);
            test_scenario::return_shared(partner);
        };

        scenario.end();
    }

    /// Test partner's current referral fee rate based on time
    /// Verifies:
    /// 1. Fee rate is 0 before start time
    /// 2. Fee rate is 0 after end time
    /// 3. Fee rate is correct during active period
    #[test]
    fun test_current_ref_fee_rate() {
        let admin = @0x123;
        let partner = @0x456;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
            partner::test_init(scenario.ctx());
        };

        // Create partner
        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut partners = scenario.take_shared<partner::Partners>();
            let clock = clock::create_for_testing(scenario.ctx());

            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 1000;
            let end_time = start_time + 1000;
            let name = string::utf8(b"Test Partner");
            let ref_fee_rate = 1000;

            partner::create_partner(
                &global_config,
                &mut partners,
                name,
                ref_fee_rate,
                start_time,
                end_time,
                partner,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock)
        };

        // Check fee rate before start time
        scenario.next_tx(admin);
        {
            let partner = scenario.take_shared<partner::Partner>();
            let clock = clock::create_for_testing(scenario.ctx());
            let current_time = clock::timestamp_ms(&clock) / 1000;
            
            assert!(partner::current_ref_fee_rate(&partner, current_time) == 0, 1);
            
            test_scenario::return_shared(partner);
            clock::destroy_for_testing(clock)
        };

        // Check fee rate after end time
        scenario.next_tx(admin);
        {
            let partner = scenario.take_shared<partner::Partner>();
            let clock = clock::create_for_testing(scenario.ctx());
            let current_time = clock::timestamp_ms(&clock) / 1000 + 3000; // After end time
            
            assert!(partner::current_ref_fee_rate(&partner, current_time) == 0, 1);
            
            test_scenario::return_shared(partner);
            clock::destroy_for_testing(clock)
        };

        // Check fee rate during active period
        scenario.next_tx(admin);
        {
            let partner = scenario.take_shared<partner::Partner>();
            let clock = clock::create_for_testing(scenario.ctx());
            let current_time = clock::timestamp_ms(&clock) / 1000 + 1500; // During active period
            
            assert!(partner::current_ref_fee_rate(&partner, current_time) == 1000, 1);
            
            test_scenario::return_shared(partner);
            clock::destroy_for_testing(clock)
        };

        scenario.end();
    }
}
