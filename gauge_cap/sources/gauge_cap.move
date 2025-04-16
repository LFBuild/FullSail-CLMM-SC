module gauge_cap::gauge_cap {

    const ENotOwner: u64 = 0;
    
    public struct GAUGE_CAP has drop {}

    public struct CreateCap has store, key {
        id: sui::object::UID,
    }

    public struct GaugeCap has store, key {
        id: sui::object::UID,
        gauge_id: sui::object::ID,
        pool_id: sui::object::ID,
    }

    public fun create_gauge_cap(
        create_cap: &CreateCap,
        gauge_id: sui::object::ID,
        pool_id: sui::object::ID,
        tx_context: &mut sui::tx_context::TxContext
    ): GaugeCap {
        GaugeCap {
            id: sui::object::new(tx_context),
            gauge_id: gauge_id,
            pool_id: pool_id,
        }
    }
    public fun get_gauge_id(gauge_cap: &GaugeCap): sui::object::ID {
        gauge_cap.gauge_id
    }

    public fun get_pool_id(gauge_cap: &GaugeCap): sui::object::ID {
        gauge_cap.pool_id
    }

    public fun grant_create_cap(publisher: &sui::package::Publisher, recipient: address, ctx: &mut sui::tx_context::TxContext) {
        assert!(publisher.from_module<CreateCap>(), ENotOwner);
        let new_cap = CreateCap { id: sui::object::new(ctx) };
        sui::transfer::public_transfer<CreateCap>(new_cap, recipient);
    }

    fun init(gauge_cap_instance: GAUGE_CAP, ctx: &mut sui::tx_context::TxContext) {
        sui::package::claim_and_keep<GAUGE_CAP>(gauge_cap_instance, ctx);
        let new_cap = CreateCap { id: sui::object::new(ctx) };
        sui::transfer::public_transfer<CreateCap>(new_cap, sui::tx_context::sender(ctx));
    }

    #[test_only]
    public fun init_test(ctx: &mut sui::tx_context::TxContext) {
        let new_cap = CreateCap { id: sui::object::new(ctx) };
        sui::transfer::public_transfer<CreateCap>(new_cap, sui::tx_context::sender(ctx));
    }
}

