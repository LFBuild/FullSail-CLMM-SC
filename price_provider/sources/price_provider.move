/// © 2025 Metabyte Labs, Inc.  All Rights Reserved.
/// U.S. Patent Application No. 63/861,982. The technology described herein is the subject of a pending U.S. patent application.
/// Full Sail has added a license to its Full Sail protocol code. You can view the terms of the license at [ULR](LICENSE/250825_Metabyte_Negotiated_Services_Agreement21634227_2_002.docx).

// Initial version of a price oracle contract with basic price feed functionality.
// This is a work in progress and will be enhanced in future versions.
// NOT FOR AUDIT
module price_provider::price_provider {
    #[allow(unused_const)]
    const COPYRIGHT_NOTICE: vector<u8> = b"© 2025 Metabyte Labs, Inc.  All Rights Reserved.";
    #[allow(unused_const)]
    const PATENT_NOTICE: vector<u8> = b"Patent pending - U.S. Patent Application No. 63/861,982";
    use sui::table::{Self, Table};

    /// Error codes for the price provider module
    const ENotAuthorized: u64 = 0;
    const EInvalidPrice: u64 = 1;

    const VERSION: u64 = 1;

    /// The main structure that represents a price provider for different feeds.
    /// This structure maintains the state of price feeds and their current values.
    /// 
    /// # Fields
    /// * `id` - The unique identifier for this shared object
    /// * `admins` - Addresses of the admins
    /// * `prices` - Table mapping feed addresses to their prices (u64 with 8 decimal places)
    public struct PriceProvider has key, store {
        id: UID,
        /// Owner who can update prices
        admins: Table<address, bool>,
        /// Table mapping feed names to their prices
        /// Price is stored as u64 with 8 decimal places
        /// e.g. 1.5 USD = 150_000_000
        prices: Table<address, u64>
    }

    /// Initializes a new PriceProvider contract
    /// Creates a shared object that can be accessed by anyone
    /// The sender becomes the admin of the contract
    fun init(ctx: &mut sui::tx_context::TxContext) {
        let mut admins = table::new(ctx);
        table::add(&mut admins, tx_context::sender(ctx), true);
        let provider = PriceProvider {
            id: sui::object::new(ctx),
            admins,
            prices: table::new(ctx),
        };
        sui::transfer::share_object<PriceProvider>(provider);
    }

    /// Updates the price for a specific feed
    /// Only the admins can update prices.
    /// 
    /// # Arguments
    /// * `provider` - Reference to the PriceProvider object
    /// * `feed` - Address of the price feed to update
    /// * `price` - New price value (u64 with 8 decimal places)
    /// * `ctx` - Transaction context
    /// 
    /// # Errors
    /// * `ENotAuthorized` - If caller is not the admin
    /// * `EInvalidPrice` - If price is 0 or negative
    public fun update_price(
        provider: &mut PriceProvider,
        feed: address,
        price: u64,
        ctx: &TxContext
    ) {
        assert!(table::contains(&provider.admins, tx_context::sender(ctx)), ENotAuthorized);
        assert!(price > 0, EInvalidPrice);
        
        if (table::contains(&provider.prices, feed)) {
            table::remove(&mut provider.prices, feed);
        };
        table::add(&mut provider.prices, feed, price);
    }

    /// Adds a new admin to the price provider
    /// Only the current admins can add new admins
    /// 
    /// # Arguments
    /// * `provider` - Reference to the PriceProvider object
    /// * `new_admin` - Address of the new admin to add
    /// * `ctx` - Transaction context
    public fun add_admin(
        provider: &mut PriceProvider,
        new_admin: address,
        ctx: &TxContext
    ) {
        assert!(table::contains(&provider.admins, tx_context::sender(ctx)), ENotAuthorized);
        table::add(&mut provider.admins, new_admin, true);
    }

    /// Retrieves the current price for a specific feed
    /// 
    /// # Arguments
    /// * `provider` - Reference to the PriceProvider object
    /// * `feed` - Address of the price feed to query
    /// 
    /// # Returns
    /// * `u64` - Current price value (0 if feed doesn't exist)
    public fun get_price(provider: &PriceProvider, feed: address): u64 {
        if (table::contains(&provider.prices, feed)) {
            *table::borrow(&provider.prices, feed)
        } else {
            0
        }
    }

    /// Checks if a price feed exists in the provider
    /// 
    /// # Arguments
    /// * `provider` - Reference to the PriceProvider object
    /// * `feed` - Address of the price feed to check
    /// 
    /// # Returns
    /// * `bool` - true if feed exists, false otherwise
    public fun has_feed(provider: &PriceProvider, feed: address): bool {
        table::contains(&provider.prices, feed)
    }

    #[test_only]
    public fun init_test(ctx: &mut sui::tx_context::TxContext) {
        let mut admins = table::new(ctx);
        table::add(&mut admins, tx_context::sender(ctx), true);
        let provider = PriceProvider {
            id: sui::object::new(ctx),
            admins,
            prices: table::new(ctx),
        };
        sui::transfer::share_object<PriceProvider>(provider);
    }
}


