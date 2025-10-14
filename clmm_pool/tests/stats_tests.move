/// © 2025 Metabyte Labs, Inc.  All Rights Reserved.
/// U.S. Patent Application No. 63/861,982. The technology described herein is the subject of a pending U.S. patent application.
/// Full Sail has added a license to its Full Sail protocol code. You can view the terms of the license at [ULR](LICENSE/250825_Metabyte_Negotiated_Services_Agreement21634227_2_002.docx).

#[test_only]
module clmm_pool::stats_tests {
    #[allow(unused_const)]
    const COPYRIGHT_NOTICE: vector<u8> = b"© 2025 Metabyte Labs, Inc.  All Rights Reserved.";
    #[allow(unused_const)]
    const PATENT_NOTICE: vector<u8> = b"Patent pending - U.S. Patent Application No. 63/861,982";

    use sui::test_scenario;
    use clmm_pool::stats;

    #[test]
    fun test_init_and_get_total_volume() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize stats using the test-only function
        stats::init_test(scenario.ctx());
        
        // Check initial state in a new transaction
        scenario.next_tx(admin);
        {
            let stats = scenario.take_shared<stats::Stats>();
            let total_volume = stats::get_total_volume(&stats);
            assert!(total_volume == 0, 0);
            test_scenario::return_shared(stats);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_add_total_volume_internal() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);

        // Initialize stats
        stats::init_test(scenario.ctx());

        scenario.next_tx(admin);
        {
            let mut stats = scenario.take_shared<stats::Stats>();
            
            // Add first amount
            let amount1: u256 = 100;
            stats::add_total_volume_internal(&mut stats, amount1);
            let total_volume = stats::get_total_volume(&stats);
            assert!(total_volume == amount1, 1);

            // Add second amount
            let amount2: u256 = 50;
            stats::add_total_volume_internal(&mut stats, amount2);
            let total_volume = stats::get_total_volume(&stats);
            let expected_total = amount1 + amount2;
            assert!(total_volume == expected_total, 2);
            
            test_scenario::return_shared(stats);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 932523069343634633)]
    fun test_add_total_volume_internal_overflow() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);
        
        // Initialize stats
        stats::init_test(scenario.ctx());

        scenario.next_tx(admin);
        {
            let mut stats = scenario.take_shared<stats::Stats>();
            let max_val: u256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
            stats::add_total_volume_internal(&mut stats, max_val);
            
            let one: u256 = 1;
            // This should overflow and abort
            stats::add_total_volume_internal(&mut stats, one); 
            
            test_scenario::return_shared(stats);
        };
        
        test_scenario::end(scenario);
    }
}
