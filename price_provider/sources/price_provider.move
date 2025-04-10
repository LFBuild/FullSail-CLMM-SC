// TODO
module price_provider::price_provider {
    use std::string::{Self, String};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::table::{Self, Table};

    /// Error codes
    const ENotAuthorized: u64 = 0;
    const EInvalidPrice: u64 = 1;

    /// Stores price data for different feeds
    public struct PriceProvider has key, store {
        id: UID,
        /// Owner who can update prices
        owner: address,
        /// Table mapping feed names to their prices
        /// Price is stored as u64 with 8 decimal places
        /// e.g. 1.5 USD = 150_000_000
        prices: Table<address, u64>
    }

    /// Creates a new price storage with the creator as owner
    public fun new(ctx: &mut TxContext) {
        let storage = PriceProvider {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            prices: table::new(ctx)
        };
        transfer::share_object(storage);
    }

    /// Updates price for a specific feed
    /// Only owner can update prices
    public fun update_price(
        provider: &mut PriceProvider,
        feed: address,
        price: u64,
        ctx: &TxContext
    ) {
        assert!(provider.owner == tx_context::sender(ctx), ENotAuthorized);
        assert!(price > 0, EInvalidPrice);
        
        if (table::contains(&provider.prices, feed)) {
            let stored_price = table::remove(&mut provider.prices, feed);
            table::add(&mut provider.prices, feed, price);
        } else {
            table::add(&mut provider.prices, feed, price);
        }
    }

    /// Gets price for a specific feed
    /// Returns 0 if feed doesn't exist
    public fun get_price(provider: &PriceProvider, feed: address): u64 {
        if (table::contains(&provider.prices, feed)) {
            *table::borrow(&provider.prices, feed)
        } else {
            0
        }
    }

    /// Checks if a feed exists
    public fun has_feed(provider: &PriceProvider, feed: address): bool {
        table::contains(&provider.prices, feed)
    }
}


