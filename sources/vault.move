module eip7540::vault {
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;
    use aptos_framework::event::{Self, EventHandle};

    /// Errors
    const ENOT_AUTHORIZED: u64 = 1;
    const EINSUFFICIENT_BALANCE: u64 = 2;
    const EINVALID_AMOUNT: u64 = 3;
    const EINVALID_ORACLE: u64 = 4;
    const EPAUSED: u64 = 5;
    const ENOT_ADMIN: u64 = 6;
    const EINVALID_FEE: u64 = 7;

    /// Events
    struct DepositEvent has drop, store {
        depositor: address,
        amount: u64,
        fee: u64,
        timestamp: u64,
    }

    struct WithdrawEvent has drop, store {
        withdrawer: address,
        amount: u64,
        fee: u64,
        timestamp: u64,
    }

    struct PauseEvent has drop, store {
        paused: bool,
        timestamp: u64,
    }

    struct FeeUpdateEvent has drop, store {
        new_fee: u64,
        timestamp: u64,
    }

    /// Vault resource
    struct Vault<phantom CoinType> has key {
        balance: Coin<CoinType>,
        total_supply: u64,
        admin: address,
        paused: bool,
        fee: u64,
        fee_collector: address,
        deposit_events: EventHandle<DepositEvent>,
        withdraw_events: EventHandle<WithdrawEvent>,
        pause_events: EventHandle<PauseEvent>,
        fee_events: EventHandle<FeeUpdateEvent>,
    }

    /// Oracle resource
    struct Oracle has key {
        price: u64,
        last_update: u64,
        update_interval: u64,
        admin: address,
        decimals: u8,
    }

    /// Initialize a new vault
    public entry fun initialize<CoinType>(
        account: &signer,
        fee: u64,
        fee_collector: address,
    ) {
        let account_addr = signer::address_of(account);
        assert!(!exists<Vault<CoinType>>(account_addr), ENOT_AUTHORIZED);
        assert!(fee <= 10000, EINVALID_FEE); // Max fee 100% (10000 basis points)
        
        move_to(account, Vault<CoinType> {
            balance: coin::zero<CoinType>(),
            total_supply: 0,
            admin: account_addr,
            paused: false,
            fee,
            fee_collector,
            deposit_events: account::new_event_handle<DepositEvent>(account),
            withdraw_events: account::new_event_handle<WithdrawEvent>(account),
            pause_events: account::new_event_handle<PauseEvent>(account),
            fee_events: account::new_event_handle<FeeUpdateEvent>(account),
        });
    }

    /// Initialize a new oracle
    public entry fun initialize_oracle(
        account: &signer,
        initial_price: u64,
        update_interval: u64,
        decimals: u8,
    ) {
        let account_addr = signer::address_of(account);
        assert!(!exists<Oracle>(account_addr), ENOT_AUTHORIZED);
        
        move_to(account, Oracle {
            price: initial_price,
            last_update: timestamp::now_seconds(),
            update_interval,
            admin: account_addr,
            decimals,
        });
    }

    /// Deposit coins into the vault
    public entry fun deposit<CoinType>(
        account: &signer,
        amount: u64,
    ) acquires Vault {
        let account_addr = signer::address_of(account);
        let vault = borrow_global_mut<Vault<CoinType>>(account_addr);
        
        assert!(!vault.paused, EPAUSED);
        assert!(amount > 0, EINVALID_AMOUNT);
        
        let coins = coin::withdraw<CoinType>(account, amount);
        let fee_amount = (amount * vault.fee) / 10000;
        let deposit_amount = amount - fee_amount;
        
        // Handle fee collection
        if (fee_amount > 0) {
            let fee_coins = coin::extract(&mut coins, fee_amount);
            coin::deposit(vault.fee_collector, fee_coins);
        };
        
        vault.balance = coin::merge(vault.balance, coins);
        vault.total_supply = vault.total_supply + deposit_amount;
        
        event::emit_event(
            &mut vault.deposit_events,
            DepositEvent {
                depositor: account_addr,
                amount: deposit_amount,
                fee: fee_amount,
                timestamp: timestamp::now_seconds(),
            },
        );
    }

    /// Withdraw coins from the vault
    public entry fun withdraw<CoinType>(
        account: &signer,
        amount: u64,
    ) acquires Vault {
        let account_addr = signer::address_of(account);
        let vault = borrow_global_mut<Vault<CoinType>>(account_addr);
        
        assert!(!vault.paused, EPAUSED);
        assert!(amount > 0, EINVALID_AMOUNT);
        assert!(coin::value(&vault.balance) >= amount, EINSUFFICIENT_BALANCE);
        
        let coins = coin::extract(&mut vault.balance, amount);
        let fee_amount = (amount * vault.fee) / 10000;
        let withdraw_amount = amount - fee_amount;
        
        // Handle fee collection
        if (fee_amount > 0) {
            let fee_coins = coin::extract(&mut coins, fee_amount);
            coin::deposit(vault.fee_collector, fee_coins);
        };
        
        vault.total_supply = vault.total_supply - withdraw_amount;
        coin::deposit(account_addr, coins);
        
        event::emit_event(
            &mut vault.withdraw_events,
            WithdrawEvent {
                withdrawer: account_addr,
                amount: withdraw_amount,
                fee: fee_amount,
                timestamp: timestamp::now_seconds(),
            },
        );
    }

    /// Update oracle price
    public entry fun update_oracle_price(
        account: &signer,
        new_price: u64,
    ) acquires Oracle {
        let account_addr = signer::address_of(account);
        let oracle = borrow_global_mut<Oracle>(account_addr);
        
        assert!(signer::address_of(account) == oracle.admin, ENOT_ADMIN);
        let current_time = timestamp::now_seconds();
        
        assert!(
            current_time >= oracle.last_update + oracle.update_interval,
            EINVALID_ORACLE
        );
        
        oracle.price = new_price;
        oracle.last_update = current_time;
    }

    /// Pause/unpause the vault
    public entry fun set_paused<CoinType>(
        account: &signer,
        paused: bool,
    ) acquires Vault {
        let account_addr = signer::address_of(account);
        let vault = borrow_global_mut<Vault<CoinType>>(account_addr);
        
        assert!(signer::address_of(account) == vault.admin, ENOT_ADMIN);
        vault.paused = paused;
        
        event::emit_event(
            &mut vault.pause_events,
            PauseEvent {
                paused,
                timestamp: timestamp::now_seconds(),
            },
        );
    }

    /// Update vault fee
    public entry fun update_fee<CoinType>(
        account: &signer,
        new_fee: u64,
    ) acquires Vault {
        let account_addr = signer::address_of(account);
        let vault = borrow_global_mut<Vault<CoinType>>(account_addr);
        
        assert!(signer::address_of(account) == vault.admin, ENOT_ADMIN);
        assert!(new_fee <= 10000, EINVALID_FEE);
        
        vault.fee = new_fee;
        
        event::emit_event(
            &mut vault.fee_events,
            FeeUpdateEvent {
                new_fee,
                timestamp: timestamp::now_seconds(),
            },
        );
    }

    /// Get current oracle price
    public fun get_oracle_price(account_addr: address): u64 acquires Oracle {
        let oracle = borrow_global<Oracle>(account_addr);
        oracle.price
    }

    /// Get vault balance
    public fun get_vault_balance<CoinType>(account_addr: address): u64 acquires Vault {
        let vault = borrow_global<Vault<CoinType>>(account_addr);
        coin::value(&vault.balance)
    }

    /// Get total supply
    public fun get_total_supply<CoinType>(account_addr: address): u64 acquires Vault {
        let vault = borrow_global<Vault<CoinType>>(account_addr);
        vault.total_supply
    }

    /// Get vault fee
    public fun get_fee<CoinType>(account_addr: address): u64 acquires Vault {
        let vault = borrow_global<Vault<CoinType>>(account_addr);
        vault.fee
    }

    /// Check if vault is paused
    public fun is_paused<CoinType>(account_addr: address): bool acquires Vault {
        let vault = borrow_global<Vault<CoinType>>(account_addr);
        vault.paused
    }
} 