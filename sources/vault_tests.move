#[test_only]
module eip7540::vault_tests {
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, MintCapability};
    use eip7540::vault::{Self, Vault, Oracle};

    struct TestCoin {}

    fun setup_test(): (signer, signer, signer) {
        let admin = account::create_account_for_test(@eip7540);
        let user = account::create_account_for_test(@0x123);
        let fee_collector = account::create_account_for_test(@0x456);
        
        // Register TestCoin
        coin::register<TestCoin>(&admin);
        
        // Mint some test coins to the user
        let mint_cap = coin::mint_capability<TestCoin>(&admin);
        coin::mint<TestCoin>(&mint_cap, 1000, &user);
        
        (admin, user, fee_collector)
    }

    #[test(admin = @eip7540, user = @0x123, fee_collector = @0x456)]
    fun test_vault_operations(admin: &signer, user: &signer, fee_collector: &signer) {
        // Initialize vault and oracle
        vault::initialize<TestCoin>(admin, 100, @0x456); // 1% fee
        vault::initialize_oracle(admin, 100, 3600, 8); // Initial price 100, update interval 1 hour
        
        // Test deposit with fee
        vault::deposit<TestCoin>(user, 500);
        assert!(vault::get_vault_balance<TestCoin>(@eip7540) == 495, 1); // 500 - 1% fee
        assert!(vault::get_total_supply<TestCoin>(@eip7540) == 495, 2);
        
        // Test withdraw with fee
        vault::withdraw<TestCoin>(user, 200);
        assert!(vault::get_vault_balance<TestCoin>(@eip7540) == 295, 3); // 495 - 200
        assert!(vault::get_total_supply<TestCoin>(@eip7540) == 295, 4);
        
        // Test oracle price update
        vault::update_oracle_price(admin, 150);
        assert!(vault::get_oracle_price(@eip7540) == 150, 5);
        
        // Test pause functionality
        vault::set_paused<TestCoin>(admin, true);
        assert!(vault::is_paused<TestCoin>(@eip7540), 6);
        
        // Test fee update
        vault::update_fee<TestCoin>(admin, 200); // Update to 2% fee
        assert!(vault::get_fee<TestCoin>(@eip7540) == 200, 7);
    }

    #[test(admin = @eip7540, user = @0x123, fee_collector = @0x456)]
    #[expected_failure(abort_code = vault::EINSUFFICIENT_BALANCE)]
    fun test_withdraw_insufficient_balance(admin: &signer, user: &signer, fee_collector: &signer) {
        vault::initialize<TestCoin>(admin, 100, @0x456);
        vault::withdraw<TestCoin>(user, 1000); // Should fail as vault is empty
    }

    #[test(admin = @eip7540, user = @0x123, fee_collector = @0x456)]
    #[expected_failure(abort_code = vault::EINVALID_AMOUNT)]
    fun test_deposit_zero_amount(admin: &signer, user: &signer, fee_collector: &signer) {
        vault::initialize<TestCoin>(admin, 100, @0x456);
        vault::deposit<TestCoin>(user, 0); // Should fail as amount is zero
    }

    #[test(admin = @eip7540, user = @0x123, fee_collector = @0x456)]
    #[expected_failure(abort_code = vault::EPAUSED)]
    fun test_operations_when_paused(admin: &signer, user: &signer, fee_collector: &signer) {
        vault::initialize<TestCoin>(admin, 100, @0x456);
        vault::set_paused<TestCoin>(admin, true);
        vault::deposit<TestCoin>(user, 100); // Should fail as vault is paused
    }

    #[test(admin = @eip7540, user = @0x123, fee_collector = @0x456)]
    #[expected_failure(abort_code = vault::ENOT_ADMIN)]
    fun test_unauthorized_admin_operations(admin: &signer, user: &signer, fee_collector: &signer) {
        vault::initialize<TestCoin>(admin, 100, @0x456);
        vault::update_fee<TestCoin>(user, 200); // Should fail as user is not admin
    }

    #[test(admin = @eip7540, user = @0x123, fee_collector = @0x456)]
    #[expected_failure(abort_code = vault::EINVALID_FEE)]
    fun test_invalid_fee(admin: &signer, user: &signer, fee_collector: &signer) {
        vault::initialize<TestCoin>(admin, 10001, @0x456); // Should fail as fee > 100%
    }
} 