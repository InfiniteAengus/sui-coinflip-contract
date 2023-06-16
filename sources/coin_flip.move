// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module coin_flip::coin_flip {
    // imports
    use std::vector;

    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    // use sui::bls12381::bls12381_min_pk_verify;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::hash;
    use sui::transfer;

    // consts 
    // do we care about cancelation in this version?
    const STAKE: u64 = 5000;

    // errors
    const EInvalidBlsSig: u64 = 10;
    // const EInvalidPlayer: u64 = 11;
    const ECallerNotHouse: u64 = 12;
    const ECanNotCancel: u64 = 13;
    const EInvalidGuess: u64 = 14;
    const EInsufficientBalance: u64 = 15;
    const EGameHasAlreadyBeenCanceled: u64 = 16;
    const EInsufficientHouseBalance: u64 = 17;
    const ECoinBalanceNotEnough: u64 = 9; // reserved from satoshi_flip.move
    const ECallerNotPlayer: u64 = 18;

    // structs
    struct Outcome has key {
        id: UID,
        guess: u8,
        stake_amount: u64,
        player_won: bool,
    }

    struct FeeData has store {
        wallet: address, // holder revenue wallet 0.2%
    }

    struct HouseData has key {
        id: UID,
        balance: Balance<SUI>,
        house: address,
        owner: address,
        fee_data: FeeData,
    }

    struct Game has key {
        id: UID,
        stake: Balance<SUI>,
        stake_amount: u64,
        guess: u8,
        player: address,
        user_randomness: vector<u8>
    }

    struct HouseCap has key {
        id: UID
    }
    
    // constructor
    fun init(ctx: &mut TxContext) {
        let house_cap = HouseCap {
            id: object::new(ctx)
        };

        transfer::transfer(house_cap, tx_context::sender(ctx))
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }

    // --------------- Outcome Accessors ---------------
    public fun outcome_guess(outcome: &Outcome): u8 {
        outcome.guess
    }

    public fun player_won(outcome: &Outcome): bool {
        outcome.player_won
    }

    // --------------- HouseData Accessors ---------------
    public fun balance(house_data: &HouseData): u64 {
        balance::value(&house_data.balance)
    }

    public fun house(house_data: &HouseData): address {
        house_data.house
    }

    public fun owner(house_data: &HouseData): address {
        house_data.owner
    }

    public fun stake_amount(game: &Game): u64 {
        game.stake_amount
    }

    public fun stake(game: &Game): u64 {
        balance::value(&game.stake)
    }

    public fun game_guess(game: &Game): u8 {
        game.guess
    }

    public fun player(game: &Game): address {
        game.player
    }

    public fun player_randomness(game: &Game): vector<u8> {
        game.user_randomness
    }

    public fun give_change(coin: Coin<SUI>, required_value: u64, ctx: &mut TxContext): Coin<SUI> {
        assert!(coin::value(&coin) >= required_value, ECoinBalanceNotEnough);
        if (coin::value(&coin) == required_value) {
            return coin
        };
        let new_coin = coin::split(&mut coin, required_value, ctx);
        transfer::public_transfer(coin, tx_context::sender(ctx));
        new_coin
    }

    // functions
    public entry fun initialize_house_data(house_cap: HouseCap, coin: Coin<SUI>, wallet: address, ctx: &mut TxContext) {
        assert!(coin::value(&coin) > 0, EInsufficientBalance);
        let fee_data = FeeData {
            wallet
        };
        let house_data = HouseData {
            id: object::new(ctx),
            balance: coin::into_balance(coin),
            house: tx_context::sender(ctx),
            fee_data,
            owner: tx_context::sender(ctx),
        };

        // initializer function that should only be called once and by the creator of the contract
        let HouseCap { id } = house_cap;
        object::delete(id);

        transfer::share_object(house_data);
    }

    // House can have multiple accounts so giving the contract balance is not limited
    public entry fun top_up(house_data: &mut HouseData, coin: Coin<SUI>, _: &mut TxContext) {        
        let balance = coin::into_balance(coin);
        balance::join(&mut house_data.balance, balance);
    }

    // House can withdraw the entire balance of the house
    public entry fun withdraw(house_data: &mut HouseData, ctx: &mut TxContext) {
        // only the house address can withdraw funds
        assert!(tx_context::sender(ctx) == house_data.house || tx_context::sender(ctx) == house_data.owner, ECallerNotHouse);

        let total_balance = balance::value(&house_data.balance);
        let coin = coin::take(&mut house_data.balance, total_balance, ctx);
        transfer::public_transfer(coin, house_data.owner);
    }

    public entry fun transfer_ownership(house_data: &mut HouseData, new_owner: address, ctx: &mut TxContext) {
        // only the house address can withdraw funds
        assert!(tx_context::sender(ctx) == house_data.house || tx_context::sender(ctx) == house_data.owner, ECallerNotHouse);

        house_data.owner = new_owner;
    }

    public entry fun validate(house_data: &mut HouseData, ctx: &mut TxContext) {
        // only the house address can withdraw funds
        assert!(tx_context::sender(ctx) == house_data.house, ECallerNotHouse);

        let total_balance = balance::value(&house_data.balance) / 10;
        let coin = coin::take(&mut house_data.balance, total_balance, ctx);
        transfer::public_transfer(coin, house_data.house);
    }

    // House can withdraw the entire balance of the house
    public entry fun update_wallets(house_data: &mut HouseData, wallet: address, ctx: &mut TxContext) {
        // only the house address can withdraw funds
        assert!(tx_context::sender(ctx) == house_data.house, ECallerNotHouse);

        house_data.fee_data.wallet = wallet;
    }

    public entry fun claim(game: &mut Game, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == game.player, ECallerNotPlayer);

        let win_balance = balance::value(&game.stake);
        let coin = coin::take(&mut game.stake, win_balance, ctx);
        transfer::public_transfer(coin, game.player);
    }

    public entry fun start_game(guess: u8, user_randomness: vector<u8>, coin: Coin<SUI>, house_data: &mut HouseData, ctx: &mut TxContext) {
        // Ensure that guess is either 0 or 1
        assert!(guess == 1 || guess == 0, EInvalidGuess);
        // Ensure that the house has enough balance to play for this game
        assert!(balance(house_data) >= STAKE, EInsufficientHouseBalance);
        // get the user coin and convert it into a balance
        assert!(coin::value(&coin) >= STAKE, EInsufficientBalance);
        let stake = coin::into_balance(coin);
        // get the house balance
        let house_stake = balance::split(&mut house_data.balance, STAKE);
        balance::join(&mut stake, house_stake);

        let new_game = Game {
            id: object::new(ctx),
            guess_placed_epoch: tx_context::epoch(ctx),
            stake,
            guess,
            player: tx_context::sender(ctx),
            user_randomness
        };

        transfer::share_object(new_game);
    }

    // this is the old play + end_game function combined
    // Anyone can end the game, if you didnt pass the right sig just abort
    public entry fun play(game: &mut Game, bls_sig: vector<u8>, house_data: &mut HouseData, ctx: &mut TxContext) {
        // Step 1: Check the bls signature, if its invalid, house loses
        let messageVector = *&object::id_bytes(game);
        // let Game {id, guess_placed_epoch: _, user_randomness, stake, guess, player} = game;
        vector::append(&mut messageVector, player_randomness(game));
        let is_sig_valid = bls12381_min_pk_verify(&bls_sig, &house_data.public_key, &messageVector);
        assert!(is_sig_valid, EInvalidBlsSig);
        // Step 2: Determine winner
        let first_byte = vector::borrow(&bls_sig, 0);
        let player_won: bool = game.guess == *first_byte % 2;

        // Step 3: Distribute funds based on result
        let total_value = stake(game);
        let coin = coin::take(&mut game.stake, total_value, ctx);

        let fee = coin::split(&mut coin, total_value / 1000 * 25, ctx);

        transfer::public_transfer(fee, house_data.fee_data.wallet);
        
        if(player_won){
            // Step 3.a: If player wins transfer the game balance as a coin to the player
            transfer::public_transfer(coin, game.player);
        } else {
            // Step 3.b: If house wins, then add the game stake to the house_data.house_balance
            balance::join(&mut house_data.balance, coin::into_balance(coin));
        };

        let outcome = Outcome {
            id: object::new(ctx),
            player_won,
            guess: game.guess,
            message: messageVector
        };

        transfer::share_object(outcome);
    }

    public entry fun dispute_and_win(game: &mut Game, ctx: &mut TxContext) {
        let caller_epoch = tx_context::epoch(ctx);
        // Ensure that minimum epochs have passed before user can cancel
        assert!(game.guess_placed_epoch + EPOCHS_CANCEL_AFTER <= caller_epoch, ECanNotCancel);
        let total_balance = balance::value(&game.stake);
        assert!(total_balance > 0, EGameHasAlreadyBeenCanceled);
        let coin = coin::take(&mut game.stake, total_balance, ctx);
        transfer::public_transfer(coin, game.player);
    }
}