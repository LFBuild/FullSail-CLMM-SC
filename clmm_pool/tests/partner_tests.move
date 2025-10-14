/// © 2025 Metabyte Labs, Inc.  All Rights Reserved.
/// U.S. Patent Application No. 63/861,982. The technology described herein is the subject of a pending U.S. patent application.
/// Full Sail has added a license to its Full Sail protocol code. You can view the terms of the license at [ULR](LICENSE/250825_Metabyte_Negotiated_Services_Agreement21634227_2_002.docx).

#[test_only]
module clmm_pool::partner_tests {
    #[allow(unused_const)]
    const COPYRIGHT_NOTICE: vector<u8> = b"© 2025 Metabyte Labs, Inc.  All Rights Reserved.";
    #[allow(unused_const)]
    const PATENT_NOTICE: vector<u8> = b"Patent pending - U.S. Patent Application No. 63/861,982";

    use clmm_pool::partner;
    use clmm_pool::config;
    use std::string;
    use sui::clock;
    use sui::coin;
    use sui::balance;
    use sui::test_scenario;

    #[test_only]
    public struct MY_COIN has drop {}

    #[test_only]
    public struct ANOTHER_COIN has drop {}

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
            assert!(partner::balances(&partner).is_empty(), 5);
            
            test_scenario::return_to_sender(&scenario, partner_cap);
            test_scenario::return_shared(partners);
            test_scenario::return_shared(partner);
        };

        scenario.end();
    }

    /// Test partner creation with invalid fee rate (100%)
    /// Should abort with code EInvalidFeeRate
    #[test]
    #[expected_failure(abort_code = partner::EInvalidFeeRate)]
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
    /// Should abort with code EInvalidName
    #[test]
    #[expected_failure(abort_code = partner::EInvalidName)]
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

    /// Test partner creation with invalid start time
    /// Should abort with code EInvalidStartTime
    #[test]
    #[expected_failure(abort_code = partner::EInvalidStartTime)]
    fun test_create_partner_invalid_start_time() {
        let admin = @0x123;
        let partner = @0x456;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
            partner::test_init(scenario.ctx());
        };
        let mut clock = clock::create_for_testing(scenario.ctx());

        clock.increment_for_testing(10_000);

        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut partners = scenario.take_shared<partner::Partners>();

            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time - 1; // Invalid start time in the past
            let end_time = current_time + 1000;
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
        };

        clock::destroy_for_testing(clock);
        scenario.end();
    }

    /// Test partner creation with invalid time range
    /// Should abort with code EInvalidTimeRange
    #[test]
    #[expected_failure(abort_code = partner::EInvalidTimeRange)]
    fun test_create_partner_invalid_time_range() {
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
            let end_time = start_time; // Invalid end time
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

        scenario.end();
    }

    /// Test partner creation with a name that is already taken
    /// Should abort with code EInvalidName
    #[test]
    #[expected_failure(abort_code = partner::EInvalidName)]
    fun test_create_partner_duplicate_name() {
        let admin = @0x123;
        let partner1 = @0x456;
        let partner2 = @0x789;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
            partner::test_init(scenario.ctx());
        };

        // Create the first partner
        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut partners = scenario.take_shared<partner::Partners>();
            let clock = clock::create_for_testing(scenario.ctx());
            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 1000;
            let end_time = start_time + 1000;
            let name = string::utf8(b"Duplicate Partner");
            let ref_fee_rate = 1000;

            partner::create_partner(
                &global_config,
                &mut partners,
                name,
                ref_fee_rate,
                start_time,
                end_time,
                partner1,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock);
        };

        // Attempt to create a second partner with the same name
        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut partners = scenario.take_shared<partner::Partners>();
            let clock = clock::create_for_testing(scenario.ctx());
            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 1000;
            let end_time = start_time + 1000;
            let name = string::utf8(b"Duplicate Partner");
            let ref_fee_rate = 1500;

            partner::create_partner(
                &global_config,
                &mut partners,
                name,
                ref_fee_rate,
                start_time,
                end_time,
                partner2,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock);
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

    /// Test updating partner's referral fee rate with a value higher than max
    /// Should abort with code EInvalidFeeRate
    #[test]
    #[expected_failure(abort_code = partner::EInvalidFeeRate)]
    fun test_update_ref_fee_rate_too_high() {
        let admin = @0x123;
        let partner_addr = @0x456;
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
                partner_addr,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock);
        };

        // Attempt to update fee rate to a value higher than max
        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut partner = scenario.take_shared<partner::Partner>();

            partner::update_ref_fee_rate(
                &global_config,
                &mut partner,
                partner::max_ref_fee_rate() + 1, // Invalid fee rate
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
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

    /// Test updating partner's time range with an invalid range
    /// Should abort with code EInvalidTimeRange
    #[test]
    #[expected_failure(abort_code = partner::EInvalidTimeRange)]
    fun test_update_time_range_invalid_range() {
        let admin = @0x123;
        let partner_addr = @0x456;
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
                partner_addr,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock);
        };

        // Attempt to update to an invalid time range
        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut partner = scenario.take_shared<partner::Partner>();
            let clock = clock::create_for_testing(scenario.ctx());

            let current_time = clock::timestamp_ms(&clock) / 1000;
            let new_start_time = current_time + 2000;
            let new_end_time = new_start_time; // Invalid: end_time must be > start_time

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
            clock::destroy_for_testing(clock);
        };

        scenario.end();
    }

    /// Test updating partner's time range with an invalid end time
    /// Should abort with code EInvalidTimeRange
    #[test]
    #[expected_failure(abort_code = partner::EInvalidTimeRange)]
    fun test_update_time_range_invalid_end_time() {
        let admin = @0x123;
        let partner_addr = @0x456;
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
                partner_addr,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock);
        };

        // Attempt to update to an invalid time range
        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut partner = scenario.take_shared<partner::Partner>();
            let mut clock = clock::create_for_testing(scenario.ctx());
            
            // Increment the clock to make the original end time in the past
            sui::clock::increment_for_testing(&mut clock, 3000 * 1000);

            let new_start_time = sui::clock::timestamp_ms(&clock) / 1000 + 1000;
            let new_end_time = sui::clock::timestamp_ms(&clock) / 1000 - 1; // Invalid end time in the past

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
            clock::destroy_for_testing(clock);
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
            test_scenario::return_to_sender(&scenario, partner_cap);
            test_scenario::return_shared(partner);
        };

        scenario.end();
    }

    /// Test receiving referral fees twice for the same coin
    /// Verifies that the balance is correctly updated
    #[test]
    fun test_receive_ref_fee_twice_single_coin() {
        let admin = @0x123;
        let partner_addr = @0x456;
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
                partner_addr,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock);
        };

        // Receive two fees
        scenario.next_tx(admin);
        {
            let mut partner = scenario.take_shared<partner::Partner>();
            
            let coin1 = coin::mint_for_testing<MY_COIN>(1000, scenario.ctx());
            partner::receive_ref_fee(&mut partner, coin::into_balance(coin1));

            let coin2 = coin::mint_for_testing<MY_COIN>(500, scenario.ctx());
            partner::receive_ref_fee(&mut partner, coin::into_balance(coin2));

            test_scenario::return_shared(partner);
        };

        scenario.end();
    }

    /// Test claiming referral fees with wrong partner capability
    /// Verifies that the transaction aborts with EPartnerIdMismatch
    #[test]
    #[expected_failure(abort_code = partner::EPartnerIdMismatch)]
    fun test_claim_ref_fee_wrong_partner_id() {
        let admin = @0x123;
        let partner1_addr = @0x456;
        let partner2_addr = @0x789;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
            partner::test_init(scenario.ctx());
        };

        // Create partner 1
        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut partners = scenario.take_shared<partner::Partners>();
            let clock = clock::create_for_testing(scenario.ctx());

            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 1000;
            let end_time = start_time + 1000;
            let name = string::utf8(b"Partner 1");
            let ref_fee_rate = 1000;

            partner::create_partner(
                &global_config,
                &mut partners,
                name,
                ref_fee_rate,
                start_time,
                end_time,
                partner1_addr,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock)
        };

        // Create partner 2
        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let mut partners = scenario.take_shared<partner::Partners>();
            let clock = clock::create_for_testing(scenario.ctx());

            let current_time = clock::timestamp_ms(&clock) / 1000;
            let start_time = current_time + 1000;
            let end_time = start_time + 1000;
            let name = string::utf8(b"Partner 2");
            let ref_fee_rate = 1000;

            partner::create_partner(
                &global_config,
                &mut partners,
                name,
                ref_fee_rate,
                start_time,
                end_time,
                partner2_addr,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock)
        };

        // Add fee to partner 2
        scenario.next_tx(admin);
        {
            let mut p1 = scenario.take_shared<partner::Partner>();
            let mut p2 = scenario.take_shared<partner::Partner>();

            if (partner::name(&p1) == string::utf8(b"Partner 2")) {
                let coin = coin::mint_for_testing<MY_COIN>(1000, scenario.ctx());
                let balance = coin::into_balance(coin);
                partner::receive_ref_fee(&mut p1, balance);
            } else {
                assert!(partner::name(&p2) == string::utf8(b"Partner 2"), 0);
                let coin = coin::mint_for_testing<MY_COIN>(1000, scenario.ctx());
                let balance = coin::into_balance(coin);
                partner::receive_ref_fee(&mut p2, balance);
            };
            
            test_scenario::return_shared(p1);
            test_scenario::return_shared(p2);
        };
        
        // Attempt to claim from partner 2 with partner 1's cap
        scenario.next_tx(partner1_addr);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let partner1_cap = scenario.take_from_sender<partner::PartnerCap>();
            
            let mut p1 = scenario.take_shared<partner::Partner>();
            let mut p2 = scenario.take_shared<partner::Partner>();

            if (partner::name(&p1) == string::utf8(b"Partner 2")) {
                partner::claim_ref_fee<MY_COIN>(
                    &global_config,
                    &partner1_cap,
                    &mut p1, // partner 2 object
                    scenario.ctx()
                );
            } else {
                assert!(partner::name(&p2) == string::utf8(b"Partner 2"), 0);
                partner::claim_ref_fee<MY_COIN>(
                    &global_config,
                    &partner1_cap,
                    &mut p2, // partner 2 object
                    scenario.ctx()
                );
            };

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(p1);
            test_scenario::return_shared(p2);
            test_scenario::return_to_sender(&scenario, partner1_cap);
        };

        scenario.end();
    }

    /// Test claiming referral fees with wrong token type
    /// Verifies that the transaction aborts with ENoBalance
    #[test]
    #[expected_failure(abort_code = partner::ENoBalance)]
    fun test_claim_ref_fee_wrong_token() {
        let admin = @0x123;
        let partner_addr = @0x456;
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
                partner_addr,
                &clock,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_shared(partners);
            clock::destroy_for_testing(clock)
        };

        // Receive fee in MY_COIN
        scenario.next_tx(admin);
        {
            let mut partner = scenario.take_shared<partner::Partner>();
            let coin = coin::mint_for_testing<MY_COIN>(1000, scenario.ctx());
            let balance = coin::into_balance(coin);
            partner::receive_ref_fee(&mut partner, balance);
            test_scenario::return_shared(partner);
        };

        // Attempt to claim fee in ANOTHER_COIN
        scenario.next_tx(partner_addr);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            let partner_cap = scenario.take_from_sender<partner::PartnerCap>();
            let mut partner = scenario.take_shared<partner::Partner>();
            
            partner::claim_ref_fee<ANOTHER_COIN>(
                &global_config,
                &partner_cap,
                &mut partner,
                scenario.ctx()
            );

            test_scenario::return_shared(global_config);
            test_scenario::return_to_sender(&scenario, partner_cap);
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

    #[test]
    fun test_max_ref_fee_rate() {
        assert!(partner::max_ref_fee_rate() == 80 * config::protocol_fee_rate_denom() / 100, 1);
    }
}
