module gauge_cap::gauge_cap {
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
        _arg0: &CreateCap,
        arg1: sui::object::ID,
        arg2: sui::object::ID,
        arg3: &mut sui::tx_context::TxContext
    ): GaugeCap {
        GaugeCap {
            id: sui::object::new(arg3),
            gauge_id: arg2,
            pool_id: arg1,
        }
    }

    public fun get_gauge_id(arg0: &GaugeCap): sui::object::ID {
        arg0.gauge_id
    }

    public fun get_pool_id(arg0: &GaugeCap): sui::object::ID {
        arg0.pool_id
    }

    public fun grant_create_cap(_arg0: &sui::package::Publisher, arg1: address, arg2: &mut sui::tx_context::TxContext) {
        let v0 = CreateCap { id: sui::object::new(arg2) };
        sui::transfer::public_transfer<CreateCap>(v0, arg1);
    }

    fun init(arg0: GAUGE_CAP, arg1: &mut sui::tx_context::TxContext) {
        sui::package::claim_and_keep<GAUGE_CAP>(arg0, arg1);
        let v0 = CreateCap { id: sui::object::new(arg1) };
        sui::transfer::public_transfer<CreateCap>(v0, sui::tx_context::sender(arg1));
    }

    // decompiled from Move bytecode v6
}

