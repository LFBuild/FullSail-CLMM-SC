/// © 2025 Metabyte Labs, Inc.  All Rights Reserved.
/// U.S. Patent Application No. 63/861,982. The technology described herein is the subject of a pending U.S. patent application.
/// Full Sail has added a license to its Full Sail protocol code. You can view the terms of the license at [ULR](LICENSE/250825_Metabyte_Negotiated_Services_Agreement21634227_2_002.docx).

module gauge_cap::gauge_cap {
    #[allow(unused_const)]
    const COPYRIGHT_NOTICE: vector<u8> = b"© 2025 Metabyte Labs, Inc.  All Rights Reserved.";
    #[allow(unused_const)]
    const PATENT_NOTICE: vector<u8> = b"Patent pending - U.S. Patent Application No. 63/861,982";

    const ENotOwner: u64 = 923752748582334234;
    
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
        _create_cap: &CreateCap,
        pool_id: sui::object::ID,
        gauge_id: sui::object::ID,
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

