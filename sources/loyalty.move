module dex::loyalty {

  use sui::clock::Clock;
  use sui::object::{Self, UID};
  use sui::coin::{Self, Coin};
  use sui::tx_context::TxContext;
  use sui::balance::{Self, Balance};

  use dex::dex::{DEX};

  const ENeeds5Points: u64 = 0;

  public struct LoyaltyAccount has key, store {
    id: UID,
    // Amount of DEX Coin staked in the program
    stake: Balance<DEX>,
    // Amount of points accumulated per staking action
    points: u64
  }

 public struct NFT has key, store {
    id: UID
  }

  /// @dev Creates a new loyalty account for tracking user's stake and points
  public fun create_account(ctx: &mut TxContext): LoyaltyAccount {
    LoyaltyAccount {
      id: object::new(ctx),
      stake: balance::zero(),
      points: 0
    }
  }

  /// @dev Returns the amount of DEX coins staked in a loyalty account
  public fun loyalty_account_stake(account: &LoyaltyAccount): u64 {
    balance::value(&account.stake)
  }

  /// @dev Returns the number of points in a loyalty account
  public fun loyalty_account_points(account: &LoyaltyAccount): u64 {
    account.points
  }

 // @dev It mints an NFT to the user in exchange for 5 points
  public fun get_reward(account: &mut LoyaltyAccount, ctx: &mut TxContext): NFT {
    // Make sure he has at least 5 points
    assert!(account.points >= 5, ENeeds5Points);

    // Deduct 5 points
    let points_ref = &mut account.points;
    *points_ref = *points_ref - 5;

    // Mint the reward
    NFT {
      id: object::new(ctx)
    }
  }
  /// @dev Allows a user to stake DEX tokens and earn points (3 points per stake)
  public fun stake(
    account: &mut LoyaltyAccount,
    stake: Coin<DEX>
  ) {
    // Add the staked DEX to the user's balance in the contract
    balance::join(&mut account.stake, coin::into_balance(stake));

    // Add 3 points to the user's account for this staking
   account.points = account.points + 3;
  }

  /// @dev Allows a user to unstake their DEX tokens
  public fun unstake(
    account: &mut LoyaltyAccount,
    ctx: &mut TxContext
  ): Coin<DEX> {
    // Get the total balance amount
    let value = loyalty_account_stake(account);

    // Unstake the balance and return it as a coin
    coin::take(&mut account.stake, value, ctx)
  }

  /// @dev Destroys the loyalty account for testing purposes
  #[test_only]
  public fun destroy_account_for_testing(account: LoyaltyAccount) {
    let LoyaltyAccount { id, stake, points: _ } = account;
    balance::destroy_for_testing(stake);
    object::delete(id);
  }

  /// @dev Destroys the NFT for testing purposes
  #[test_only]
  public fun destroy_nft_for_testing(nft: NFT) {
    let NFT { id } = nft;
    object::delete(id);
  }
}
