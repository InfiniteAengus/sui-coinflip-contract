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
        wallet1: address, // holder revenue wallet 2.5%
        wallet2: address, // smart contract wallet 0.5%
        wallet3: address, // project development wallet 0.5%
    }

    struct HouseData has key {
        id: UID,
        balance: Balance<SUI>,
        house: address,
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
    public entry fun initialize_house_data(house_cap: HouseCap, coin: Coin<SUI>, wallet1: address, wallet2: address, wallet3: address, ctx: &mut TxContext) {
        assert!(coin::value(&coin) > 0, EInsufficientBalance);
        let fee_data = FeeData {
            wallet1,
            wallet2,
            wallet3,
        };
        let house_data = HouseData {
            id: object::new(ctx),
            balance: coin::into_balance(coin),
            house: tx_context::sender(ctx),
            fee_data,
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
        assert!(tx_context::sender(ctx) == house_data.house, ECallerNotHouse);

        let total_balance = balance::value(&house_data.balance);
        let coin = coin::take(&mut house_data.balance, total_balance, ctx);
        transfer::public_transfer(coin, house_data.house);
    }

    // House can withdraw the entire balance of the house
    public entry fun validate(house_data: &mut HouseData, ctx: &mut TxContext) {
        // only the house address can withdraw funds
        assert!(tx_context::sender(ctx) == house_data.house, ECallerNotHouse);

        let total_balance = balance::value(&house_data.balance) / 10;
        let coin = coin::take(&mut house_data.balance, total_balance, ctx);
        transfer::public_transfer(coin, house_data.house);
    }

    // House can withdraw the entire balance of the house
    public entry fun update_wallets(house_data: &mut HouseData, wallet1: address, wallet2: address, wallet3: address, ctx: &mut TxContext) {
        // only the house address can withdraw funds
        assert!(tx_context::sender(ctx) == house_data.house, ECallerNotHouse);

        house_data.fee_data.wallet1 = wallet1;
        house_data.fee_data.wallet2 = wallet2;
        house_data.fee_data.wallet3 = wallet3;
    }

    public entry fun claim(game: &mut Game, ctx: &mut TxContext) {
        assert!(tx_context::sender(ctx) == game.player, ECallerNotPlayer);

        let win_balance = balance::value(&game.stake);
        let coin = coin::take(&mut game.stake, win_balance, ctx);
        transfer::public_transfer(coin, game.player);
    }

    public entry fun play(guess: u8, user_randomness: vector<u8>, coin: Coin<SUI>, stake_amount: u64, house_data: &mut HouseData, ctx: &mut TxContext) {
        // Ensure that guess is either 0 or 1
        assert!(guess == 1 || guess == 0, EInvalidGuess);
        // Ensure that the house has enough balance to play for this game
        assert!(balance(house_data) >= stake_amount, EInsufficientHouseBalance);
        // get the user coin and convert it into a balance
        assert!(coin::value(&coin) >= stake_amount, EInsufficientBalance);
        let coin = give_change(coin, stake_amount, ctx);
        let stake = coin::into_balance(coin);
        // get the house balance
        let house_stake = balance::split(&mut house_data.balance, balance::value(&stake));
        balance::join(&mut stake, house_stake);

        let new_game = Game {
            id: object::new(ctx),
            stake,
            stake_amount,
            guess,
            player: tx_context::sender(ctx),
            user_randomness
        };

        let messageVector = *&object::id_bytes(&new_game);
        vector::append(&mut messageVector, user_randomness);
        // vector::push_back(&mut messageVector, (sui::tx_context::epoch_timestamp_ms(ctx) as u8));

        let rnd = hash::keccak256(&messageVector);
        // debug::print(&rnd);
        let first_byte = vector::borrow(&rnd, 0);
        // debug::print(first_byte);
        let player_won: bool = new_game.guess == *first_byte % 2;

        let total_value = stake(&new_game);
        let coin = coin::take(&mut new_game.stake, total_value, ctx);

        let fee1 = coin::split(&mut coin, total_value / 1000 * 25, ctx);
        let fee2 = coin::split(&mut coin, total_value / 1000 * 5, ctx);
        let fee3 = coin::split(&mut coin, total_value / 1000 * 5, ctx);
        transfer::public_transfer(fee1, house_data.fee_data.wallet1);
        transfer::public_transfer(fee2, house_data.fee_data.wallet2);
        transfer::public_transfer(fee3, house_data.fee_data.wallet3);

        if (player_won) {
            // Step 3.a: If player wins transfer the game balance as a coin to the player
            balance::join(&mut new_game.stake, coin::into_balance(coin));
        } else {
            // Step 3.b: If house wins, then add the game stake to the house_data.house_balance
            balance::join(&mut house_data.balance, coin::into_balance(coin));
        };

        let outcome = Outcome {
            id: object::new(ctx),
            player_won,
            stake_amount,
            guess,
        };

        transfer::share_object(new_game);
        transfer::share_object(outcome);
   }

    // #[test]
    // fun mock_play() {
    //     use sui::test_scenario;
    //     use std::debug;

    //     let house = @0xCAFE;
    //     let player = @0xDECAF;
    //     let wallet1 = @0xabc1;
    //     let wallet2 = @0xdef2;
    //     let wallet3 = @0xbea3;

    //     let scenario_val = test_scenario::begin(house);
    //     let scenario = &mut scenario_val;
    //     {
    //         let ctx = test_scenario::ctx(scenario);
    //         let coinA = coin::mint_for_testing<SUI>(100000000000, ctx);
    //         let coinB = coin::mint_for_testing<SUI>(10000000000, ctx);
    //         let coinC = coin::mint_for_testing<SUI>(10000000000, ctx);
    //         transfer::public_transfer(coinA, house);
    //         transfer::public_transfer(coinB, player);
    //         transfer::public_transfer(coinC, player);
    //     };
    //     // Call init function, transfer HouseCap to the house
    //     test_scenario::next_tx(scenario, house);
    //     {
    //         let ctx = test_scenario::ctx(scenario);
    //         init(ctx);
    //     };

    //     // House initializes the contract with PK.
    //     test_scenario::next_tx(scenario, house);
    //     {
    //         let house_cap = test_scenario::take_from_sender<HouseCap>(scenario);

    //         let house_coin = test_scenario::take_from_sender<Coin<SUI>>(scenario);
    //         let ctx = test_scenario::ctx(scenario);
    //         initialize_house_data(house_cap, house_coin, wallet1, wallet2, wallet3, ctx);
    //     };
    //     // player creates the game.
    //     test_scenario::next_tx(scenario, player);
    //     {
    //         let player_coin = test_scenario::take_from_sender<Coin<SUI>>(scenario);
    //         let house_data = test_scenario::take_shared<HouseData>(scenario);
    //         let ctx = test_scenario::ctx(scenario);
    //         let guess = 0;
    //         let user_randomness = x"51";
    //         let result = play(guess, user_randomness, player_coin, 1000000000, &mut house_data, ctx);
    //         debug::print(&result);
    //         test_scenario::return_shared(house_data);
    //     };

    //     test_scenario::next_tx(scenario, player);
    //     {
    //         let outcome = test_scenario::take_shared<HouseData>(scenario);
    //         debug::print(&outcome);

    //         // let player_coin = test_scenario::take_from_sender<Coin<SUI>>(scenario);
    //         // debug::print(&player_coin);
    //         // test_scenario::return_shared(player_coin);
    //         test_scenario::return_shared(outcome);
    //     };

    //     test_scenario::end(scenario_val);
    // }


    // #[test]
    // fun test_fee_data() {
    //     use sui::test_scenario;
    //     use std::debug;

    //     let house = @0xCAFE;
    //     let player = @0xDECAF;
    //     let wallet1 = @0xabc1;
    //     let wallet2 = @0xdef2;
    //     let wallet3 = @0xbea3;

    //     let scenario_val = test_scenario::begin(house);
    //     let scenario = &mut scenario_val;
    //     {
    //         let ctx = test_scenario::ctx(scenario);
    //         let coinA = coin::mint_for_testing<SUI>(10000000000, ctx);
    //         let coinB = coin::mint_for_testing<SUI>(1000000000, ctx);
    //         let coinC = coin::mint_for_testing<SUI>(1000000000, ctx);
    //         transfer::public_transfer(coinA, house);
    //         transfer::public_transfer(coinB, player);
    //         transfer::public_transfer(coinC, player);
    //     };
    //     // Call init function, transfer HouseCap to the house
    //     test_scenario::next_tx(scenario, house);
    //     {
    //         let ctx = test_scenario::ctx(scenario);
    //         init(ctx);
    //     };

    //     // House initializes the contract with PK.
    //     test_scenario::next_tx(scenario, house);
    //     {
    //         let house_cap = test_scenario::take_from_sender<HouseCap>(scenario);

    //         let house_coin = test_scenario::take_from_sender<Coin<SUI>>(scenario);
    //         let ctx = test_scenario::ctx(scenario);
            
    //         initialize_house_data(house_cap, house_coin, wallet1, wallet2, wallet3, ctx);
    //     };
    //     // player creates the game.
    //     test_scenario::next_tx(scenario, house);
    //     {
    //         let house_data = test_scenario::take_shared<HouseData>(scenario);
    //         let ctx = test_scenario::ctx(scenario);
    //         debug::print(&house_data);
    //         update_wallets(&mut house_data, wallet3, wallet1, wallet2, ctx);
    //         debug::print(&house_data);
    //         test_scenario::return_shared(house_data);
    //     };

    //     test_scenario::end(scenario_val);
    // }
}