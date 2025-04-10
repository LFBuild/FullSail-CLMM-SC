#[test_only]
module clmm_pool::acl_tests {
    use clmm_pool::acl::{Self, ACL, Member};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::object;
    #[test_only]
    public struct TestACL has store, key {
        id: sui::object::UID,
        acl: ACL,
    }

    #[test]
    fun test_acl_creation() {
        let mut ctx = tx_context::dummy();
        let test_acl = TestACL {
            id: object::new(&mut ctx),
            acl: acl::new(&mut ctx),
        };
        assert!(std::vector::length(&acl::get_members(&test_acl.acl)) == 0, 0);
        transfer::share_object(test_acl);
    }

    #[test]
    fun test_add_and_check_role() {
        let mut ctx = tx_context::dummy();
        let mut test_acl = TestACL {
            id: object::new(&mut ctx),
            acl: acl::new(&mut ctx),
        };
        let member = @0x2;

        // Adding role 0 (Pool Manager)
        acl::add_role(&mut test_acl.acl, member, 0);
        assert!(acl::has_role(&test_acl.acl, member, 0), 1);
        assert!(!acl::has_role(&test_acl.acl, member, 1), 2);
        transfer::share_object(test_acl);
    }

    #[test]
    fun test_remove_role() {
        let mut ctx = tx_context::dummy();
        let mut test_acl = TestACL {
            id: object::new(&mut ctx),
            acl: acl::new(&mut ctx),
        };
        let member = @0x2;

        // Adding and then removing role
        acl::add_role(&mut test_acl.acl, member, 0);
        assert!(acl::has_role(&test_acl.acl, member, 0), 1);
        acl::remove_role(&mut test_acl.acl, member, 0);
        assert!(!acl::has_role(&test_acl.acl, member, 0), 2);
        transfer::share_object(test_acl);
    }

    #[test]
    fun test_multiple_roles() {
        let mut ctx = tx_context::dummy();
        let mut test_acl = TestACL {
            id: object::new(&mut ctx),
            acl: acl::new(&mut ctx),
        };
        let member = @0x2;

        // Adding multiple roles
        acl::add_role(&mut test_acl.acl, member, 0);
        acl::add_role(&mut test_acl.acl, member, 1);
        acl::add_role(&mut test_acl.acl, member, 2);

        assert!(acl::has_role(&test_acl.acl, member, 0), 1);
        assert!(acl::has_role(&test_acl.acl, member, 1), 2);
        assert!(acl::has_role(&test_acl.acl, member, 2), 3);
        transfer::share_object(test_acl);
    }

    #[test]
    fun test_remove_member() {
        let mut ctx = tx_context::dummy();
        let mut test_acl = TestACL {
            id: object::new(&mut ctx),
            acl: acl::new(&mut ctx),
        };
        let member = @0x2;

        // Adding roles and removing member
        acl::add_role(&mut test_acl.acl, member, 0);
        acl::add_role(&mut test_acl.acl, member, 1);
        assert!(acl::has_role(&test_acl.acl, member, 0), 1);
        assert!(acl::has_role(&test_acl.acl, member, 1), 2);

        acl::remove_member(&mut test_acl.acl, member);
        assert!(!acl::has_role(&test_acl.acl, member, 0), 3);
        assert!(!acl::has_role(&test_acl.acl, member, 1), 4);
        transfer::share_object(test_acl);
    }

    #[test]
    fun test_set_roles() {
        let mut ctx = tx_context::dummy();
        let mut test_acl = TestACL {
            id: object::new(&mut ctx),
            acl: acl::new(&mut ctx),
        };
        let member = @0x2;

        // Setting roles via bitmask
        let permission = 1 << 0 | 1 << 1; // Roles 0 and 1
        acl::set_roles(&mut test_acl.acl, member, permission);

        assert!(acl::has_role(&test_acl.acl, member, 0), 1);
        assert!(acl::has_role(&test_acl.acl, member, 1), 2);
        assert!(!acl::has_role(&test_acl.acl, member, 2), 3);
        transfer::share_object(test_acl);
    }

    #[test]
    fun test_get_members() {
        let mut ctx = tx_context::dummy();
        let mut test_acl = TestACL {
            id: object::new(&mut ctx),
            acl: acl::new(&mut ctx),
        };
        let member1 = @0x2;
        let member2 = @0x3;

        // Adding two members with different roles
        acl::add_role(&mut test_acl.acl, member1, 0);
        acl::add_role(&mut test_acl.acl, member2, 1);

        let members = acl::get_members(&test_acl.acl);
        assert!(std::vector::length(&members) == 2, 1);

        // Checking member permissions
        assert!(acl::get_permission(&test_acl.acl, member1) == 1 << 0, 2);
        assert!(acl::get_permission(&test_acl.acl, member2) == 1 << 1, 3);
        transfer::share_object(test_acl);
    }

    #[test]
    fun test_get_permission() {
        let mut ctx = tx_context::dummy();
        let mut test_acl = TestACL {
            id: object::new(&mut ctx),
            acl: acl::new(&mut ctx),
        };
        let member = @0x2;

        // Checking permission retrieval for a nonexistent member
        assert!(acl::get_permission(&test_acl.acl, member) == 0, 1);

        // Adding roles and checking permissions
        acl::add_role(&mut test_acl.acl, member, 0);
        acl::add_role(&mut test_acl.acl, member, 1);
        assert!(acl::get_permission(&test_acl.acl, member) == (1 << 0 | 1 << 1), 2);
        transfer::share_object(test_acl);
    }

    #[test]
    #[expected_failure(abort_code = 1)]
    fun test_invalid_role() {
        let mut ctx = tx_context::dummy();
        let mut test_acl = TestACL {
            id: object::new(&mut ctx),
            acl: acl::new(&mut ctx),
        };
        let member = @0x2;

        // Trying to add an invalid role (>= 128)
        acl::add_role(&mut test_acl.acl, member, 128);
        transfer::share_object(test_acl);
    }

    #[test]
    fun test_remove_nonexistent_role() {
        let mut ctx = tx_context::dummy();
        let mut test_acl = TestACL {
            id: object::new(&mut ctx),
            acl: acl::new(&mut ctx),
        };
        let member = @0x2;

        // Trying to remove a nonexistent role
        acl::remove_role(&mut test_acl.acl, member, 0);
        assert!(!acl::has_role(&test_acl.acl, member, 0), 1);
        transfer::share_object(test_acl);
    }

    #[test]
    fun test_remove_nonexistent_member() {
        let mut ctx = tx_context::dummy();
        let mut test_acl = TestACL {
            id: object::new(&mut ctx),
            acl: acl::new(&mut ctx),
        };
        let member = @0x2;

        // Trying to remove a nonexistent member
        acl::remove_member(&mut test_acl.acl, member);
        assert!(!acl::has_role(&test_acl.acl, member, 0), 1);
        transfer::share_object(test_acl);
    }

    #[test]
    fun test_set_roles_overwrite() {
        let mut ctx = tx_context::dummy();
        let mut test_acl = TestACL {
            id: object::new(&mut ctx),
            acl: acl::new(&mut ctx),
        };
        let member = @0x2;

        // Setting initial roles
        let initial_permission = 1 << 0 | 1 << 1;
        acl::set_roles(&mut test_acl.acl, member, initial_permission);
        assert!(acl::get_permission(&test_acl.acl, member) == initial_permission, 1);

        // Overwriting roles
        let new_permission = 1 << 2 | 1 << 3;
        acl::set_roles(&mut test_acl.acl, member, new_permission);
        assert!(acl::get_permission(&test_acl.acl, member) == new_permission, 2);
        assert!(!acl::has_role(&test_acl.acl, member, 0), 3);
        assert!(!acl::has_role(&test_acl.acl, member, 1), 4);
        assert!(acl::has_role(&test_acl.acl, member, 2), 5);
        assert!(acl::has_role(&test_acl.acl, member, 3), 6);
        transfer::share_object(test_acl);
    }

    #[test]
    fun test_has_role_nonexistent_member() {
        let mut ctx = tx_context::dummy();
        let mut test_acl = TestACL {
            id: object::new(&mut ctx),
            acl: acl::new(&mut ctx),
        };
        let member = @0x2;

        // Checking role for a nonexistent member
        assert!(!acl::has_role(&test_acl.acl, member, 0), 1);
        transfer::share_object(test_acl);
    }

    #[test]
    fun test_add_role_to_existing_member() {
        let mut ctx = tx_context::dummy();
        let mut test_acl = TestACL {
            id: object::new(&mut ctx),
            acl: acl::new(&mut ctx),
        };
        let member = @0x2;

        // Adding the first role
        acl::add_role(&mut test_acl.acl, member, 0);
        assert!(acl::has_role(&test_acl.acl, member, 0), 1);

        // Adding a second role to the same member
        acl::add_role(&mut test_acl.acl, member, 1);
        assert!(acl::has_role(&test_acl.acl, member, 0), 2);
        assert!(acl::has_role(&test_acl.acl, member, 1), 3);
        assert!(acl::get_permission(&test_acl.acl, member) == (1 << 0 | 1 << 1), 4);
        transfer::share_object(test_acl);
    }
}
