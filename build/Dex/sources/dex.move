module dex::dex {
  use std::option;
  use std::type_name::{get, TypeName};

  use sui::transfer;
  use sui::sui::SUI;
  use sui::clock::{Clock};
  use sui::balance::{Self, Supply};
  use sui::object::{Self, UID};
  use sui::table::{Self, Table};
  use sui::dynamic_field as df;
  use sui::tx_context::{Self, TxContext};
  use sui::coin::{Self, TreasuryCap, Coin};

  use deepbook::clob_v2::{Self as clob, Pool};
  use deepbook::custodian_v2::AccountCap;

  use dex::eth::ETH;
  use dex::usdc::USDC;

  const CLIENT_ID: u64 = 122227;
  const MAX_U64: u64 = 18446744073709551615;
  const NO_RESTRICTION: u8 = 0;
  const FLOAT_SCALING: u64 = 1_000_000_000; 

  const EAlreadyMintedThisEpoch: u64 = 0;

  struct DEX has drop {}

  struct Data<phantom CoinType> has store {
    cap: TreasuryCap<CoinType>,
    faucet_lock: Table<address, u64>
  }

  struct Storage has key {
    id: UID,
    dex_supply: Supply<DEX>,
    swaps: Table<address, u64>,
    account_cap: AccountCap,
    client_id: u64
  }

  #[allow(unused_function)]
  fun init(witness: DEX, ctx: &mut TxContext) { 

  let (treasury_cap, metadata) = coin::create_currency<DEX>(
            witness, 
            9, 
            b"DEX",
            b"DEX Coin", 
            b"Coin of SUI DEX", 
            option::none(), 
            ctx
        );
    
    transfer::public_freeze_object(metadata);    

		transfer::share_object(Storage { 
      id: object::new(ctx), 
      dex_supply: coin::treasury_into_supply(treasury_cap), 
      swaps: table::new(ctx),
      account_cap: clob::create_account(ctx),
      client_id: CLIENT_ID
    });
  }

  public fun user_last_mint_epoch<CoinType>(self: &Storage, user: address): u64 {
    let data = df::borrow<TypeName, Data<CoinType>>(&self.id, get<CoinType>());

    if (table::contains(&data.faucet_lock, user)) return *table::borrow(&data.faucet_lock, user);

    0 
  }

  public fun user_swap_count(self: &Storage, user: address): u64 {
    if (table::contains(&self.swaps, user)) return *table::borrow(&self.swaps, user);

    0
  }

  public fun entry_place_market_order(
    self: &mut Storage,
    pool: &mut Pool<ETH, USDC>,
    account_cap: &AccountCap,
    quantity: u64,
    is_bid: bool,
    base_coin: Coin<ETH>,
    quote_coin: Coin<USDC>,
    c: &Clock,
    ctx: &mut TxContext,   
  ) {
    let (eth, usdc, coin_dex) = place_market_order(self, pool, account_cap, quantity, is_bid, base_coin, quote_coin, c, ctx);
    let sender = tx_context::sender(ctx);

    transfer_coin(eth, sender);
    transfer_coin(usdc, sender);
    transfer_coin(coin_dex, sender);
  }

  public fun place_market_order(
    self: &mut Storage,
    pool: &mut Pool<ETH, USDC>,
    account_cap: &AccountCap,
    quantity: u64,
    is_bid: bool,
    base_coin: Coin<ETH>,
    quote_coin: Coin<USDC>,
    c: &Clock,
    ctx: &mut TxContext,    
  ): (Coin<ETH>, Coin<USDC>, Coin<DEX>) {
  let sender = tx_context::sender(ctx);  

  let client_order_id = 0;
  let dex_coin = coin::zero(ctx);

  if (table::contains(&self.swaps, sender)) {
    let total_swaps = table::borrow_mut(&mut self.swaps, sender);
    let new_total_swap = *total_swaps + 1;
    *total_swaps = new_total_swap;
    client_order_id = new_total_swap;

    if ((new_total_swap % 2) == 0) {
      coin::join(&mut dex_coin, coin::from_balance(balance::increase_supply(&mut self.dex_supply, FLOAT_SCALING), ctx));
    };
  } else {
    table::add(&mut self.swaps, sender, 1);
  };
  
  let (eth_coin, usdc_coin) = clob::place_market_order<ETH, USDC>(
    pool, 
    account_cap, 
    client_order_id, 
    quantity,
    is_bid,
    base_coin,
    quote_coin,
    c,
    ctx
    );

    (eth_coin, usdc_coin, dex_coin)
  }
  
  public fun create_pool(fee: Coin<SUI>, ctx: &mut TxContext) {

    clob::create_pool<ETH, USDC>(1 * FLOAT_SCALING, 1, fee, ctx);
  }

  public fun fill_pool(
    self: &mut Storage,
    pool: &mut Pool<ETH, USDC>, 
    c: &Clock, 
    ctx: &mut TxContext
  ) {
    
    create_ask_orders(self, pool, c, ctx);
    create_bid_orders(self, pool, c, ctx);
  }

  public fun create_state(
    self: &mut Storage, 
    eth_cap: TreasuryCap<ETH>, 
    usdc_cap: TreasuryCap<USDC>, 
    ctx: &mut TxContext
  ) {

    df::add(&mut self.id, get<ETH>(), Data { cap: eth_cap, faucet_lock: table::new(ctx) });
    df::add(&mut self.id, get<USDC>(), Data { cap: usdc_cap, faucet_lock: table::new(ctx) });
  }

  public fun mint_coin<CoinType>(self: &mut Storage, ctx: &mut TxContext): Coin<CoinType> {
    let sender = tx_context::sender(ctx);
    let current_epoch = tx_context::epoch(ctx);
    let type = get<CoinType>();
    let data = df::borrow_mut<TypeName, Data<CoinType>>(&mut self.id, type);

    if (table::contains(&data.faucet_lock, sender)){

      let last_mint_epoch = table::borrow(&data.faucet_lock, tx_context::sender(ctx));

      assert!(current_epoch > *last_mint_epoch, EAlreadyMintedThisEpoch);
    } else {

      table::add(&mut data.faucet_lock, sender, 0);
    };

    let last_mint_epoch = table::borrow_mut(&mut data.faucet_lock, sender);
    *last_mint_epoch = tx_context::epoch(ctx);
    coin::mint(&mut data.cap, if (type == get<USDC>()) 100 * FLOAT_SCALING else 1 * FLOAT_SCALING, ctx)
  }

  fun create_ask_orders(
    self: &mut Storage,
    pool: &mut Pool<ETH, USDC>, 
    c: &Clock, 
    ctx: &mut TxContext
  ) {

    let eth_data = df::borrow_mut<TypeName, Data<ETH>>(&mut self.id, get<ETH>());

    clob::deposit_base<ETH, USDC>(pool, coin::mint(&mut eth_data.cap, 60000000000000, ctx), &self.account_cap);

    clob::place_limit_order(
      pool,
      self.client_id,
     120 * FLOAT_SCALING, 
     60000000000000,
      NO_RESTRICTION,
      false,
      MAX_U64,
      NO_RESTRICTION,
      c,
      &self.account_cap,
      ctx
    );

    self.client_id = self.client_id + 1;
  }

  fun create_bid_orders(
    self: &mut Storage,
    pool: &mut Pool<ETH, USDC>,
    c: &Clock,
    ctx: &mut TxContext
  ) {

    let usdc_data = df::borrow_mut<TypeName, Data<USDC>>(&mut self.id, get<USDC>());

    clob::deposit_quote<ETH, USDC>(pool, coin::mint(&mut usdc_data.cap, 6000000000000000, ctx), &self.account_cap);

    clob::place_limit_order(
      pool,
      self.client_id, 
      100 * FLOAT_SCALING, 
      60000000000000,
      NO_RESTRICTION,
      true,
      MAX_U64,
      NO_RESTRICTION,
      c,
      &self.account_cap,
      ctx
    );
    self.client_id = self.client_id + 1;
  }

  fun transfer_coin<CoinType>(c: Coin<CoinType>, sender: address) {
    
    if (coin::value(&c) == 0) {
      coin::destroy_zero(c);
    } else {
    
    transfer::public_transfer(c, sender);
    }; 
  }

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init( DEX {}, ctx);
  }
}
