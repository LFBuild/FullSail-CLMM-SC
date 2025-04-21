#[test_only]
module price_provider::price_provider_tests;

use price_provider::price_provider;
use sui::test_scenario;

const ADMIN: address = @0x123;
const USER: address = @0x456;
const FEED: address = @0x789;

#[test_only]
fun setup_test_scenario(): test_scenario::Scenario {
    let mut scenario = test_scenario::begin(ADMIN);
    price_provider::init_test(scenario.ctx());
    test_scenario::next_tx(&mut scenario, ADMIN);
    scenario
}

#[test]
fun test_update_price() {
    let mut scenario = setup_test_scenario();
    
    // Admin can update price
    test_scenario::next_tx(&mut scenario, ADMIN);
    let mut provider = test_scenario::take_shared<price_provider::PriceProvider>(&scenario);
    price_provider::update_price(
        &mut provider,
        FEED,
        150_000_000, // 1.5 USD
        scenario.ctx()
    );
    test_scenario::return_shared(provider);
    
    // Verify price was updated
    test_scenario::next_tx(&mut scenario, ADMIN);
    let provider = test_scenario::take_shared<price_provider::PriceProvider>(&scenario);
    let price = price_provider::get_price(&provider, FEED);
    test_scenario::return_shared(provider);
    assert!(price == 150_000_000, 0);
    
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = price_provider::ENotAuthorized)]
fun test_update_price_unauthorized() {
    let mut scenario = setup_test_scenario();
    
    // Non-admin cannot update price
    test_scenario::next_tx(&mut scenario, USER);
    let mut provider = test_scenario::take_shared<price_provider::PriceProvider>(&scenario);
    price_provider::update_price(
        &mut provider,
        FEED,
        150_000_000,
        scenario.ctx()
    );

    test_scenario::return_shared(provider);

    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = price_provider::EInvalidPrice)]
fun test_update_price_invalid() {
    let mut scenario = setup_test_scenario();
    
    // Cannot set zero price
    let mut provider = test_scenario::take_shared<price_provider::PriceProvider>(&scenario);
    price_provider::update_price(
        &mut provider,
        FEED,
        0,
        scenario.ctx()
    );

    test_scenario::return_shared(provider);

    test_scenario::end(scenario);
}

#[test]
fun test_add_admin() {
    let mut scenario = setup_test_scenario();
    
    // Admin can add new admin
    test_scenario::next_tx(&mut scenario, ADMIN);
    let mut provider = test_scenario::take_shared<price_provider::PriceProvider>(&scenario);
    price_provider::add_admin(
        &mut provider,
        USER,
        scenario.ctx()
    );
    
    // New admin can update price
    test_scenario::next_tx(&mut scenario, USER);
    price_provider::update_price(
        &mut provider,
        FEED,
        150_000_000,
        scenario.ctx()
    );
    test_scenario::return_shared(provider);
    
    test_scenario::end(scenario);
}

#[test, expected_failure(abort_code = price_provider::ENotAuthorized)]
fun test_add_admin_unauthorized() {
    let mut scenario = setup_test_scenario();
    
    // Non-admin cannot add new admin
    test_scenario::next_tx(&mut scenario, USER);
    let mut provider = test_scenario::take_shared<price_provider::PriceProvider>(&scenario);
    price_provider::add_admin(
        &mut provider,
        USER,
        scenario.ctx()
    );

    test_scenario::return_shared(provider);

    test_scenario::end(scenario);
}

#[test]
fun test_has_feed() {
    let mut scenario = setup_test_scenario();
    
    // Initially feed doesn't exist
    test_scenario::next_tx(&mut scenario, ADMIN);
    let mut provider = test_scenario::take_shared<price_provider::PriceProvider>(&scenario);
    let has_feed = price_provider::has_feed(&provider, FEED);
    assert!(!has_feed, 0);
    
    // Add feed
    test_scenario::next_tx(&mut scenario, ADMIN);
    price_provider::update_price(
        &mut provider,
        FEED,
        150_000_000,
        scenario.ctx()
    );
    
    // Verify feed exists
    test_scenario::next_tx(&mut scenario, ADMIN);
    let has_feed = price_provider::has_feed(&provider, FEED);
    test_scenario::return_shared(provider);
    assert!(has_feed, 0);
    
    test_scenario::end(scenario);
}

#[test]
fun test_get_price_nonexistent() {
    let mut scenario = setup_test_scenario();
    
    // Get price for non-existent feed returns 0
    test_scenario::next_tx(&mut scenario, ADMIN);
    let provider = test_scenario::take_shared<price_provider::PriceProvider>(&scenario);
    let price = price_provider::get_price(&provider, FEED);
    test_scenario::return_shared(provider);
    assert!(price == 0, 0);
    
    test_scenario::end(scenario);
}
