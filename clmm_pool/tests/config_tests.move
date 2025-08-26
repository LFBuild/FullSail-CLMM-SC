/// © 2025 Metabyte Labs, Inc.  All Rights Reserved.
/// U.S. Patent Application No. 63/861,982. The technology described herein is the subject of a pending U.S. patent application.
/// Full Sail has added a license to its Full Sail protocol code. You can view the terms of the license at [ULR](LICENSE/250825_Metabyte_Negotiated_Services_Agreement21634227_2_002.docx).

#[test_only]
module clmm_pool::config_tests {
    #[allow(unused_const)]
    const COPYRIGHT_NOTICE: vector<u8> = b"© 2025 Metabyte Labs, Inc.  All Rights Reserved.";
    #[allow(unused_const)]
    const PATENT_NOTICE: vector<u8> = b"Patent pending - U.S. Patent Application No. 63/861,982";

    use clmm_pool::config;
    use sui::test_scenario;
    use sui::transfer;
    use sui::object;
    use std::vector;

    #[test]
    fun test_fee_and_role_management() {
        let admin = @0x123;
        let user = @0x456;
        let mut scenario = test_scenario::begin(admin);
        {
            // Initialize the test environment
            config::test_init(scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            let global_config = scenario.take_shared<config::GlobalConfig>();
            assert!(config::protocol_fee_rate(&global_config) == 2000, 1);
            assert!(config::unstaked_liquidity_fee_rate(&global_config) == 0, 2);
            test_scenario::return_shared(global_config);
        };

        // Update fees
        test_scenario::next_tx(&mut scenario, admin);
        {
            let admin_cap = test_scenario::take_from_sender<config::AdminCap>(&scenario);
            let mut global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            config::update_protocol_fee_rate(&mut global_config, 3000, scenario.ctx());
            config::update_unstaked_liquidity_fee_rate(&mut global_config, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };

        // Check updated fee values
        test_scenario::next_tx(&mut scenario, admin);
        {
            let global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            assert!(config::protocol_fee_rate(&global_config) == 3000, 3);
            assert!(config::unstaked_liquidity_fee_rate(&global_config) == 1000, 4);
            test_scenario::return_shared(global_config);
        };

        // Check role management
        test_scenario::next_tx(&mut scenario, admin);
        {
            let admin_cap = test_scenario::take_from_sender<config::AdminCap>(&scenario);
            let mut global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            config::add_role(&admin_cap, &mut global_config, user, 0);
            assert!(clmm_pool::acl::has_role(config::acl(&global_config), user, 0), 5);
            config::remove_role(&admin_cap, &mut global_config, user, 0);
            assert!(!clmm_pool::acl::has_role(config::acl(&global_config), user, 0), 6);
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_fee_tier_management() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
        };

        // Add a new fee tier
        test_scenario::next_tx(&mut scenario, admin);
        {
            let admin_cap = test_scenario::take_from_sender<config::AdminCap>(&scenario);
            let mut global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            config::add_fee_tier(&mut global_config, 10, 1000, scenario.ctx());
            assert!(config::get_fee_rate(10, &global_config) == 1000, 1);
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };

        // Update fee tier
        test_scenario::next_tx(&mut scenario, admin);
        {
            let admin_cap = test_scenario::take_from_sender<config::AdminCap>(&scenario);
            let mut global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            config::update_fee_tier(&mut global_config, 10, 2000, scenario.ctx());
            assert!(config::get_fee_rate(10, &global_config) == 2000, 2);
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };

        // Delete fee tier
        test_scenario::next_tx(&mut scenario, admin);
        {
            let admin_cap = test_scenario::take_from_sender<config::AdminCap>(&scenario);
            let mut global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            config::delete_fee_tier(&mut global_config, 10, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_fee_rate_constants() {
        assert!(config::fee_rate_denom() == 1000000, 1);
        assert!(config::protocol_fee_rate_denom() == 10000, 2);
        assert!(config::unstaked_liquidity_fee_rate_denom() == 10000, 3);
        assert!(config::max_fee_rate() == 200000, 4);
        assert!(config::max_protocol_fee_rate() == 3000, 5);
        assert!(config::max_unstaked_liquidity_fee_rate() == 10000, 6);
        assert!(config::default_unstaked_fee_rate() == 72057594037927935, 7);
    }

    #[test]
    #[expected_failure(abort_code = config::EFeeRateExceedsMax)]
    fun test_fee_tier_validation() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
        };

        // Test adding fee tier with invalid fee rate
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 10, config::max_fee_rate() + 1, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = config::EFeeTierAlreadyExists)]
    fun test_fee_tier_duplicate_validation() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
        };

        // Add first fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 10, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };

        // Try to add duplicate fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 10, 2000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = config::EFeeTierNotFound)]
    fun test_fee_tier_not_exists_validation() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
        };

        // Try to delete non-existent fee tier
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::delete_fee_tier(&mut global_config, 10, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = config::EFeeTierManagerRole)]
    fun test_fee_tier_manager_role_validation() {
        let admin = @0x123;
        let user = @0x456;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
        };

        // Try to add fee tier without fee tier manager role
        scenario.next_tx(user);
        {
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 10, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = config::EPackageVersionMismatch)]
    fun test_package_version_validation() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
        };

        // Update package version
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::update_package_version(&admin_cap, &mut global_config, 2);
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };

        // Try to perform operation with wrong package version
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<config::AdminCap>();
            let mut global_config = scenario.take_shared<config::GlobalConfig>();
            config::add_fee_tier(&mut global_config, 10, 1000, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = config::EProtocolFeeRateExceedsMax)]
    fun test_protocol_fee_rate_validation() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
        };

        // Test updating protocol fee rate with invalid value
        test_scenario::next_tx(&mut scenario, admin);
        {
            let admin_cap = test_scenario::take_from_sender<config::AdminCap>(&scenario);
            let mut global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            config::update_protocol_fee_rate(&mut global_config, config::max_protocol_fee_rate() + 1, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = config::EUnstakedLiquidityFeeRateExceedsMax)]
    fun test_unstaked_liquidity_fee_rate_validation() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
        };

        // Test updating unstaked liquidity fee rate with invalid value
        test_scenario::next_tx(&mut scenario, admin);
        {
            let admin_cap = test_scenario::take_from_sender<config::AdminCap>(&scenario);
            let mut global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            config::update_unstaked_liquidity_fee_rate(&mut global_config, config::max_unstaked_liquidity_fee_rate() + 1, scenario.ctx());
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = clmm_pool::acl::EInvalidRole)]
    fun test_role_management_validation() {
        let admin = @0x123;
        let user = @0x456;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
        };

        // Test adding role with invalid role ID
        test_scenario::next_tx(&mut scenario, admin);
        {
            let admin_cap = test_scenario::take_from_sender<config::AdminCap>(&scenario);
            let mut global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            config::add_role(&admin_cap, &mut global_config, user, 255);
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_package_version_management() {
        let admin = @0x123;
        let mut scenario = test_scenario::begin(admin);
        {
            config::test_init(scenario.ctx());
        };

        // Test updating package version
        test_scenario::next_tx(&mut scenario, admin);
        {
            let admin_cap = test_scenario::take_from_sender<config::AdminCap>(&scenario);
            let mut global_config = test_scenario::take_shared<config::GlobalConfig>(&scenario);
            config::update_package_version(&admin_cap, &mut global_config, 2);
            test_scenario::return_shared(global_config);
            transfer::public_transfer(admin_cap, admin);
        };

        test_scenario::end(scenario);
    }
}
