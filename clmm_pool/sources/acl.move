/// Access Control List (ACL) module for managing permissions and roles in the CLMM pool system.
/// This module provides functionality for managing access control through a linked table structure
/// that maps addresses to their permission bitmaps.
/// 
/// The module supports:
/// * Creating new ACL instances
/// * Adding and removing roles for members
/// * Checking role permissions
/// * Managing multiple roles per address through a bitmap
/// 
/// # Roles
/// * 0: Pool Manager - Can manage pool settings and parameters
/// * 1: Fee Manager - Can manage fee rates and fee-related settings
/// * 2: Emergency Manager - Can pause/unpause pools in emergency situations
/// * 3: Protocol Manager - Can manage protocol-level settings
/// * 4: Gauge Manager - Can manage gauge-related settings
/// * 5: Reward Manager - Can manage reward distribution settings
/// * 6: Position Manager - Can manage position-related settings
/// * 7: Liquidity Manager - Can manage liquidity-related settings
module clmm_pool::acl {
    /// Structure representing the Access Control List.
    /// Uses a linked table to store address-to-permission mappings.
    /// 
    /// # Fields
    /// * `permissions` - A linked table mapping addresses to their permission bitmaps
    public struct ACL has store {
        permissions: move_stl::linked_table::LinkedTable<address, u128>,
    }

    /// Structure representing a member with their address and permission bitmap.
    /// Used for returning member information in queries.
    /// 
    /// # Fields
    /// * `address` - The member's address
    /// * `permission` - The member's permission bitmap
    public struct Member has copy, drop, store {
        address: address,
        permission: u128,
    }

    /// Creates a new ACL instance.
    /// 
    /// # Arguments
    /// * `ctx` - Mutable reference to the transaction context
    /// 
    /// # Returns
    /// A new ACL instance with an empty permissions table
    public fun new(ctx: &mut sui::tx_context::TxContext): ACL {
        ACL { permissions: move_stl::linked_table::new<address, u128>(ctx) }
    }

    /// Adds a role to a member's permission set.
    /// 
    /// # Arguments
    /// * `acl` - Mutable reference to the ACL
    /// * `member_addr` - Address of the member to add the role to
    /// * `role` - Role to add (0-127)
    /// 
    /// # Aborts
    /// * If the role is >= 128 (error code: 1)
    public fun add_role(acl: &mut ACL, member_addr: address, role: u8) {
        assert!(role < 128, 1);
        if (move_stl::linked_table::contains<address, u128>(&acl.permissions, member_addr)) {
            let permission = move_stl::linked_table::borrow_mut<address, u128>(&mut acl.permissions, member_addr);
            *permission = *permission | (1 << role);
        } else {
            move_stl::linked_table::push_back<address, u128>(&mut acl.permissions, member_addr, 1 << role);
        };
    }

    /// Returns a vector of all members in the ACL with their addresses and permission bitmaps.
    /// 
    /// # Arguments
    /// * `acl` - Reference to the ACL
    /// 
    /// # Returns
    /// A vector of Member structs containing all members' addresses and their permission bitmaps
    public fun get_members(acl: &ACL): vector<Member> {
        let mut members = std::vector::empty<Member>();
        let mut current_addr = move_stl::linked_table::head<address, u128>(&acl.permissions);
        while (std::option::is_some<address>(&current_addr)) {
            let addr = *std::option::borrow<address>(&current_addr);
            let node = move_stl::linked_table::borrow_node<address, u128>(&acl.permissions, addr);
            let member = Member {
                address: addr,
                permission: *move_stl::linked_table::borrow_value<address, u128>(node),
            };
            std::vector::push_back<Member>(&mut members, member);
            current_addr = move_stl::linked_table::next<address, u128>(node);
        };
        members
    }

    /// Returns the permission bitmap for a specific member address.
    /// Returns 0 if the member is not found in the ACL.
    /// 
    /// # Arguments
    /// * `acl` - Reference to the ACL
    /// * `member_addr` - Address of the member to get permissions for
    /// 
    /// # Returns
    /// The permission bitmap for the member, or 0 if the member is not found
    public fun get_permission(acl: &ACL, member_addr: address): u128 {
        if (!move_stl::linked_table::contains<address, u128>(&acl.permissions, member_addr)) {
            0
        } else {
            *move_stl::linked_table::borrow<address, u128>(&acl.permissions, member_addr)
        }
    }
    
    /// Checks if a member has a specific role.
    /// 
    /// # Arguments
    /// * `acl` - Reference to the ACL
    /// * `member_addr` - Address of the member to check
    /// * `role` - Role to check for (0-127)
    /// 
    /// # Returns
    /// True if the member has the specified role, false otherwise
    /// 
    /// # Aborts
    /// * If the role is >= 128 (error code: 1)
    public fun has_role(acl: &ACL, member_addr: address, role: u8): bool {
        assert!(role < 128, 1);
        move_stl::linked_table::contains<address, u128>(
            &acl.permissions,
            member_addr
        ) && (*move_stl::linked_table::borrow<address, u128>(&acl.permissions, member_addr) & (1 << role) > 0)
    }

    /// Removes a member and all their roles from the ACL.
    /// 
    /// # Arguments
    /// * `acl` - Mutable reference to the ACL
    /// * `member_addr` - Address of the member to remove
    public fun remove_member(acl: &mut ACL, member_addr: address) {
        if (move_stl::linked_table::contains<address, u128>(&acl.permissions, member_addr)) {
            move_stl::linked_table::remove<address, u128>(&mut acl.permissions, member_addr);
        };
    }

    /// Removes a specific role from a member's permission set.
    /// 
    /// # Arguments
    /// * `acl` - Mutable reference to the ACL
    /// * `member_addr` - Address of the member to remove the role from
    /// * `role` - Role to remove (0-127)
    /// 
    /// # Aborts
    /// * If the role is >= 128 (error code: 1)
    public fun remove_role(acl: &mut ACL, member_addr: address, role: u8) {
        assert!(role < 128, 1);
        if (move_stl::linked_table::contains<address, u128>(&acl.permissions, member_addr)) {
            let permission = move_stl::linked_table::borrow_mut<address, u128>(&mut acl.permissions, member_addr);
            if ((*permission & (1 << role)) > 0) {
                *permission = *permission - (1 << role);
            };
        };
    }

    /// Sets all roles for a member using a permission bitmap.
    /// If the member exists, their permissions are updated. If not, they are added with the specified permissions.
    /// 
    /// # Arguments
    /// * `acl` - Mutable reference to the ACL
    /// * `member_addr` - Address of the member to set roles for
    /// * `permission` - Permission bitmap to set for the member
    public fun set_roles(acl: &mut ACL, member_addr: address, permission: u128) {
        if (move_stl::linked_table::contains<address, u128>(&acl.permissions, member_addr)) {
            *move_stl::linked_table::borrow_mut<address, u128>(&mut acl.permissions, member_addr) = permission;
        } else {
            move_stl::linked_table::push_back<address, u128>(&mut acl.permissions, member_addr, permission);
        };
    }
}

