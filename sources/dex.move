module dex::dex {
    use std::option;
    use sui::transfer;
    use sui::sui::SUI;
    use sui::clock::Clock;
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::dynamic_field as df;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, TreasuryCap, Coin};
    use sui::event::{Self, emit};
    use std::string::{Self, String};
    //use sui::url;
   use dex::eth::ETH;
    use dex::naira::NAIRA;

    const MIN_COLLATERAL_RATIO: u64 = 150; // 150% collateral
    const FLOAT_SCALING: u64 = 1_000_000_000; // Scaling for decimal handling
    const ETH_TO_NAIRA_RATE: u64 = 30_000 * FLOAT_SCALING; // 1 ETH = 30,000 NAIRA

    public struct DEX has drop {}
   //  public struct ETH has drop {}
   //    public struct NAIRA has drop{}

    public struct LendingPool has key, store {
        id: UID,
        eth_supply: Balance<ETH>,
        naira_supply: Balance<NAIRA>,
        treasury_cap_naira: TreasuryCap<NAIRA>,
        treasury_cap_eth: TreasuryCap<ETH>,
        treasury_cap_dex: TreasuryCap<DEX>,
    }

    public struct WithdrawalEvent has copy, drop {
        message: vector<u8>
    }

    public struct DepositEvent has copy, drop {
        message: vector<u8>
    }

    public struct TransferEvent has copy, drop {
        message: vector<u8>
    }

    public struct RewardEvent has copy, drop {
        message: vector<u8>
    }

    public struct CollateralAccount has key {
        id: UID,
        eth_collateral: Balance<ETH>,
        naira_collateral: Balance<NAIRA>,
        borrowed_naira: Balance<NAIRA>,
        borrowed_eth: Balance<ETH>,
    }


    public struct NairaDepositEvent has copy, drop {
        depositor: address,
        amount: u64,
    }

   // public struct DEXTreasuryCap has key, store {
      //  id: UID,
    //    cap: TreasuryCap<DEX>,
    //}

    fun init(witness: DEX, ctx: &mut TxContext) {
    // let eth_witness = ETH {};
     //let naira_witness = NAIRA{};

        //let eth_witness = dex::eth::ETH { };

        //let treasury_cap_naira = naira_witnessS;
        //let treasury_cap_eth = dex::eth::create_eth_treasury(ctx);
        //let treasury_cap_dex = (witness ctx);

         // Create the ETH treasury cap
   /* let (treasury_cap_eth, eth_metadata) = coin::create_currency<ETH>(
        eth_witness,
       9, 
        b"ETH",
        b"ETH Coin", 
        b"Coin of SUI ETH", 
        option::some(url::new_unsafe_from_bytes(b"https://s2.coinmarketcap.com/static/img/coins/64x64/1027.png")),
        ctx
    );

      let (treasury_cap_naira, naira_metadata) = coin::create_currency<NAIRA>(
            naira_witness, 
            9, // Decimals of the coin
            b"Naira", // Symbol of the coin
            b"Naira", // Name of the coin
            b"A Fiat issued by Circle", // Description of the coin
            option::some(url::new_unsafe_from_bytes(b"https://s3.coinmarketcap.com/static-gravity/image/5a8229787b5e4c809b5914eef709b59a.png")), // An image of the Coin
            ctx
        );*/

        let (treasury_cap, metadata) = coin::create_currency<DEX>(
            witness, 
            9, 
            b"DEX",
            b"DEX Coin", 
            b"Coin of SUI DEX", 
            option::none(), 
            ctx
        );

     /*   let pool = LendingPool {
            id: object::new(ctx),
            treasury_cap_naira,
            treasury_cap_eth,
            treasury_cap_dex,
            eth_supply: balance::zero<ETH>(),
            naira_supply: balance::zero<NAIRA>(),
        };
        transfer::public_transfer(pool, tx_context::sender(ctx));

        let new_object = DEXTreasuryCap {
            id: object::new(ctx),
            cap: treasury_cap_dex,
        };*/
      transfer::public_transfer(treasury_cap, tx_context::sender(ctx));
        //transfer::public_transfer(treasury_cap_eth, tx_context::sender(ctx));
        //transfer::public_transfer(treasury_cap_naira, tx_context::sender(ctx));

        transfer::public_share_object(metadata);
       // transfer::public_share_object(eth_metadata);
        //transfer::public_share_object(naira_metadata);
    }

    
    public fun mint_naira(cap: &mut TreasuryCap<NAIRA>, ctx: &mut TxContext, amount: u64): Coin<NAIRA> {
    let minted_coin = coin::mint(cap, amount * FLOAT_SCALING, ctx);
     //transfer::public_transfer(minted_coin, tx_context::sender(ctx));
    event::emit(DepositEvent {
        message: b"NAIRA deposited successfully",
    });
    minted_coin
}



    public fun mint_sui(cap: &mut TreasuryCap<SUI>, ctx: &mut TxContext, amount: u64): Coin<SUI> {
    let minted = coin::mint(cap, amount * FLOAT_SCALING, ctx);
    minted
}




    public fun mint_eth(cap: &mut TreasuryCap<ETH>, ctx: &mut TxContext, amount: u64): Coin<ETH>{
    let minted_coin = coin::mint(cap, amount * FLOAT_SCALING, ctx);
   // transfer::public_transfer(minted_coin, tx_context::sender(ctx));
    minted_coin
}


    public fun deposit_eth(account: &mut CollateralAccount, eth_coin: Coin<ETH>) {
        balance::join(&mut account.eth_collateral, coin::into_balance(eth_coin));
    }

    public fun deposit_naira(account: &mut CollateralAccount, naira_coin: Coin<NAIRA>) {
        balance::join(&mut account.naira_collateral, coin::into_balance(naira_coin));
    }

    public fun convert_eth_to_naira(eth_amount: u64): u64 {
        eth_amount * ETH_TO_NAIRA_RATE / FLOAT_SCALING
    }

    public fun convert_naira_to_eth(naira_amount: u64): u64 {
        naira_amount * FLOAT_SCALING / ETH_TO_NAIRA_RATE
    }

    public fun borrow_naira(
        account: &mut CollateralAccount,
        pool: &mut LendingPool,
        naira_amount: u64,
        ctx: &mut TxContext
    ) {
        let eth_collateral_value = balance::value(&account.eth_collateral);
        let required_collateral = convert_naira_to_eth(naira_amount) * MIN_COLLATERAL_RATIO / 100;

        assert!(eth_collateral_value >= required_collateral, 1);

        if (balance::value(&pool.naira_supply) < naira_amount * FLOAT_SCALING) {
            let mint_amount = (naira_amount * FLOAT_SCALING) - balance::value(&pool.naira_supply);
            let minted_coin = coin::mint(&mut pool.treasury_cap_naira, mint_amount, ctx);
            balance::join(&mut pool.naira_supply, coin::into_balance(minted_coin));
        };

        let naira_borrowed = coin::take(&mut pool.naira_supply, naira_amount * FLOAT_SCALING, ctx);
        balance::join(&mut account.borrowed_naira, coin::into_balance(naira_borrowed));

        reward_user_with_dex(&mut pool.treasury_cap_dex, ctx);
    }

    public fun borrow_eth(
        account: &mut CollateralAccount,
        pool: &mut LendingPool,
        eth_amount: u64,
        ctx: &mut TxContext
    ) {
        let naira_collateral_value = balance::value(&account.naira_collateral);
        let required_collateral = convert_eth_to_naira(eth_amount) * MIN_COLLATERAL_RATIO / 100;

        assert!(naira_collateral_value >= required_collateral, 1);

        if (balance::value(&pool.eth_supply) < eth_amount * FLOAT_SCALING) {
            let mint_amount = (eth_amount * FLOAT_SCALING) - balance::value(&pool.eth_supply);
            let minted_coin = coin::mint(&mut pool.treasury_cap_eth, mint_amount, ctx);
            balance::join(&mut pool.eth_supply, coin::into_balance(minted_coin));
        };

        let eth_borrowed = coin::take(&mut pool.eth_supply, eth_amount * FLOAT_SCALING, ctx);
        balance::join(&mut account.borrowed_eth, coin::into_balance(eth_borrowed));

        reward_user_with_dex(&mut pool.treasury_cap_dex, ctx);
    }
public fun repay_naira(account: &mut CollateralAccount, pool: &mut LendingPool, repayment: Coin<NAIRA>, ctx: &mut TxContext) {
    let repaid_amount = coin::value(&repayment);
    balance::join(&mut pool.naira_supply, coin::into_balance(repayment));
    
    // Use the correct value type for balance::split
    let remaining_balance = coin::take(&mut account.borrowed_naira, repaid_amount, ctx);
    // Handle the remaining_balance if necessary
    balance::join(&mut account.borrowed_naira, coin::into_balance(remaining_balance));


    reward_user_with_dex(&mut pool.treasury_cap_dex, ctx);
}

public fun repay_eth(account: &mut CollateralAccount, pool: &mut LendingPool, repayment: Coin<ETH>, ctx: &mut TxContext) {
    let repaid_amount = coin::value(&repayment);
    balance::join(&mut pool.eth_supply, coin::into_balance(repayment));
    
    // Use the correct value type for balance::split
    let remaining_balance = coin::take(&mut account.borrowed_eth, repaid_amount, ctx);
    // Handle the remaining_balance if necessary
      balance::join(&mut account.borrowed_eth, coin::into_balance(remaining_balance));


    reward_user_with_dex(&mut pool.treasury_cap_dex, ctx);
}


 public fun send_eth_receive_naira(
        pool: &mut LendingPool,
        recipient: address,
        eth_amount: u64,
        ctx: &mut TxContext
    ) {
        let naira_equivalent = convert_eth_to_naira(eth_amount);

        let naira_supply = balance::value(&pool.naira_supply);
        if (naira_supply < naira_equivalent) {
            let mint_amount = naira_equivalent - naira_supply;
            let minted_coin = coin::mint(&mut pool.treasury_cap_naira, mint_amount, ctx);
            balance::join(&mut pool.naira_supply, coin::into_balance(minted_coin));
        };

        let eth_coin = coin::take(&mut pool.eth_supply, eth_amount * FLOAT_SCALING, ctx);
        //transfer::public_transfer(eth_coin, sender); 
         coin::burn(&mut pool.treasury_cap_eth, eth_coin);
        

        let naira_coin = coin::take(&mut pool.naira_supply, naira_equivalent, ctx);
        transfer::public_transfer(naira_coin, recipient);

        reward_user_with_dex(&mut pool.treasury_cap_dex, ctx);

        emit(WithdrawalEvent {
            message: b"ETH sent, NAIRA received successfully. DEX token reward granted.",
        });
    }

    public fun send_naira_receive_eth(
        pool: &mut LendingPool,
        recipient: address,
        naira_amount: u64,
        ctx: &mut TxContext
    ) {
        let eth_equivalent = convert_naira_to_eth(naira_amount);

        let eth_supply = balance::value(&pool.eth_supply);
        if (eth_supply < eth_equivalent) {
            let mint_amount = eth_equivalent - eth_supply;
            let minted_coin = coin::mint(&mut pool.treasury_cap_eth, mint_amount, ctx);
            balance::join(&mut pool.eth_supply, coin::into_balance(minted_coin));
        };

        let naira_coin = coin::take(&mut pool.naira_supply, naira_amount * FLOAT_SCALING, ctx);
        //transfer::public_transfer(naira_coin, sender);
         coin::burn(&mut pool.treasury_cap_naira, naira_coin);

        let eth_coin = coin::take(&mut pool.eth_supply, eth_equivalent, ctx);
        transfer::public_transfer(eth_coin, recipient);

        reward_user_with_dex(&mut pool.treasury_cap_dex, ctx);

        emit(WithdrawalEvent {
            message: b"Transfer successful: NAIRA sent, ETH received. DEX token reward granted.",
        });
    }

    fun reward_user_with_dex(cap: &mut TreasuryCap<DEX>, ctx: &mut TxContext) {
        let dex_reward_amount = 2 * FLOAT_SCALING;
        let dex_reward = coin::mint(cap, dex_reward_amount, ctx);

        let sender = tx_context::sender(ctx);
        transfer::public_transfer(dex_reward, sender);

        emit(RewardEvent {
            message: b"DEX token reward granted",
        });
    }

    public fun withdraw_naira(
        user: address,
        account_number: u64, 
        bank_name: vector<u8>, 
        amount: u64,
        pool: &mut LendingPool, 
        ctx: &mut TxContext
    ) {
        assert!(account_number >= 1_000_000_000 && account_number <= 9_999_999_999, 1);
        assert!(!vector::is_empty(&bank_name), 2);

        let scaled_amount = amount * FLOAT_SCALING;
        let naira_to_burn = coin::take(&mut pool.naira_supply, scaled_amount, ctx);
        coin::burn(&mut pool.treasury_cap_naira, naira_to_burn);

        emit(WithdrawalEvent {
            message: b"Withdrawal successful",
        });
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext): (LendingPool, DEXTreasuryCap) {
        let pool = init(DEX {}, ctx);
        let dex_token_cap = DEXTreasuryCap {
            id: object::new(ctx),
            cap: pool.treasury_cap,
        };
        (pool, dex_token_cap)
    }
}

