// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module satoshi::coin_flip {
    // Imports

    // Std library
    use std::vector;

    // Sui library
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::bls12381::bls12381_min_pk_verify;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;

    // Suifrens library
    use suifrens::suifrens::{SuiFren};
    use suifrens::capy::Capy;

    // Consts 
    const EPOCHS_CANCEL_AFTER: u64 = 7;
    const STAKE: u64 = 5000;
    const MAX_FEE_IN_BP: u16 = 10_000;

    // Errors
    const EInvalidBlsSig: u64 = 10;
    const ECallerNotHouse: u64 = 12;
    const ECanNotCancel: u64 = 13;
    const EInvalidGuess: u64 = 14;
    const EInsufficientBalance: u64 = 15;
    const EGameHasAlreadyBeenCanceled: u64 = 16;
    const EInsufficientHouseBalance: u64 = 17;
    const ECoinBalanceNotEnough: u64 = 9;
    const EBaseFeeTooHigh: u64 = 8;

    // Structs
    struct Outcome has key {
        id: UID,
        guess: u8,
        player_won: bool,
        message: vector<u8>
    }

    struct HouseData has key {
        id: UID,
        balance: Balance<SUI>,
        house: address,
        public_key: vector<u8>,
        fees: Balance<SUI>,
        base_fee_in_bp: u16,
        capy_owner_fee_in_bp: u16,
    }

    struct Game has key {
        id: UID,
        guess_placed_epoch: u64,
        stake: Balance<SUI>,
        guess: u8,
        player: address,
        user_randomness: vector<u8>,
        fee_bp: u16
    }

    struct HouseCap has key {
        id: UID
    }
    
    // Constructor
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

    /// Returns the player's guess for a specific outcome
    /// @param outcome: An Outcome object
    public fun outcome_guess(outcome: &Outcome): u8 {
        outcome.guess
    }

    /// Returns a boolean declaring if the player won or not
    /// True if the player won, false if the house won
    /// @param outcome: An Outcome object
    public fun player_won(outcome: &Outcome): bool {
        outcome.player_won
    }

    // --------------- HouseData Accessors ---------------

    /// Returns the balance of the house
    /// @param house_data: The HouseData object
    public fun balance(house_data: &HouseData): u64 {
        balance::value(&house_data.balance)
    }

    /// Returns the address of the house
    /// @param house_data: The HouseData object
    public fun house(house_data: &HouseData): address {
        house_data.house
    }

    /// Returns the public key of the house
    /// @param house_data: The HouseData object
    public fun public_key(house_data: &HouseData): vector<u8> {
        house_data.public_key
    }

    /// Returns the fees of the house
    /// @param house_data: The HouseData object
    public fun fees(house_data: &HouseData): u64 {
        balance::value(&house_data.fees)
    }

    /// Returns the base fee of the house
    /// @param house_data: The HouseData object
    public fun base_fee_in_bp(house_data: &HouseData): u16 {
        house_data.base_fee_in_bp
    }

    /// Returns the capy owner fee of the house
    /// @param house_data: The HouseData object
    public fun capy_owner_fee_in_bp(house_data: &HouseData): u16 {
        house_data.capy_owner_fee_in_bp
    }

    // --------------- Game Accessors ---------------

    /// Returns the epoch in which the guess was placed
    /// @param game: A Game object
    public fun guess_placed_epoch(game: &Game): u64 {
        game.guess_placed_epoch
    }

    /// Returns the total stake 
    /// @param game: A Game object
    public fun stake(game: &Game): u64 {
        balance::value(&game.stake)
    }

    /// Returns the player's guess
    /// @param game: A Game object
    public fun game_guess(game: &Game): u8 {
        game.guess
    }

    /// Returns the player's address
    /// @param game: A Game object
    public fun player(game: &Game): address {
        game.player
    }

    /// Returns the player's randomn bytes input
    /// @param game: A Game object
    public fun player_randomness(game: &Game): vector<u8> {
        game.user_randomness
    }

    /// Returns the fee of the game
    /// @param game: A Game object
    public fun fee_in_bp(game: &Game): u16 {
        game.fee_bp
    }

    // Functions

    /// Initializes the house data object. This object is involed in all games created by the same instance of this package. 
    /// It holds the balance of the house (used for the house's stake as well as for storing the house's earnings), the house address, and the public key of the house.
    /// @param house_cap: The HouseCap object
    /// @param coin: The coin object that will be used to initialize the house balance. Acts as a treasury
    /// @param public_key: The public key of the house
    public entry fun initialize_house_data(house_cap: HouseCap, coin: Coin<SUI>, public_key: vector<u8>, ctx: &mut TxContext) {
        assert!(coin::value(&coin) > 0, EInsufficientBalance);
        let house_data = HouseData {
            id: object::new(ctx),
            balance: coin::into_balance(coin),
            house: tx_context::sender(ctx),
            public_key,
            fees: balance::zero(),
            base_fee_in_bp: 20,
            capy_owner_fee_in_bp: 10
        };

        // initializer function that should only be called once and by the creator of the contract
        let HouseCap { id } = house_cap;
        object::delete(id);

        transfer::share_object(house_data);
    }

    /// Function used to top up the house balance. Can be called by anyone.
    /// House can have multiple accounts so giving the treasury balance is not limited.
    /// @param house_data: The HouseData object
    /// @param coin: The coin object that will be used to top up the house balance. The entire coin is consumed
    public entry fun top_up(house_data: &mut HouseData, coin: Coin<SUI>, _: &mut TxContext) {        
        let balance = coin::into_balance(coin);
        balance::join(&mut house_data.balance, balance);
    }

    /// House can withdraw the entire balance of the house object
    /// @param house_data: The HouseData object
    public entry fun withdraw(house_data: &mut HouseData, ctx: &mut TxContext) {
        // only the house address can withdraw funds
        assert!(tx_context::sender(ctx) == house_data.house, ECallerNotHouse);

        let total_balance = balance::value(&house_data.balance);
        let coin = coin::take(&mut house_data.balance, total_balance, ctx);
        transfer::public_transfer(coin, house_data.house);
    }

    /// House can update the base fee in basis points
    /// @param house_data: The HouseData object
    /// @param base_fee_in_bp: The new base fee in basis points
    public entry fun update_base_fee(house_data: &mut HouseData, base_fee_in_bp: u16, ctx: &mut TxContext) {
        // only the house address can update the base fee
        assert!(tx_context::sender(ctx) == house_data.house, ECallerNotHouse);
        // base fee cannot be higher than 100%
        assert!(base_fee_in_bp <= MAX_FEE_IN_BP, EBaseFeeTooHigh);

        house_data.base_fee_in_bp = base_fee_in_bp;
    }

    /// House can update the capy owner fee in basis points
    /// @param house_data: The HouseData object
    /// @param capy_owner_fee_in_bp: The new capy owner fee in basis points
    public entry fun update_capy_owner_fee(house_data: &mut HouseData, capy_owner_fee_in_bp: u16, ctx: &mut TxContext) {
        // only the house address can update the capy owner fee
        assert!(tx_context::sender(ctx) == house_data.house, ECallerNotHouse);
        // base fee cannot be higher than 100%
        assert!(capy_owner_fee_in_bp <= MAX_FEE_IN_BP, EBaseFeeTooHigh);

        house_data.capy_owner_fee_in_bp = capy_owner_fee_in_bp;
    }

    /// House can withdraw the accumulated fees of the house object
    /// @param house_data: The HouseData object
    public entry fun claim_fees(house_data: &mut HouseData, ctx: &mut TxContext) {
        // only the house address can withdraw fee funds
        assert!(tx_context::sender(ctx) == house_data.house, ECallerNotHouse);

        let total_fees = balance::value(&house_data.fees);
        let coin = coin::take(&mut house_data.fees, total_fees, ctx);
        transfer::public_transfer(coin, house_data.house);
    }

    /// Helper function to calculate the amount of fees to be paid.
    public fun fee_amount(game: &Game): u64 {
        let amount = (((stake(game) as u128) * (fee_in_bp(game) as u128) / 10_000) as u64);

        amount
    }

    /// Function used to create a new game. The player must provide a guess and a randomn vector of bytes.
    /// Stake is taken from the player's coin and added to the game's stake. The house's stake is also added to the game's stake.
    /// @param guess: The player's guess. Can be either 0 or 1
    /// @param user_randomness: A vector of randomly produced bytes that will be used to calculate the result of the VRF
    /// @param coin: The coin object that will be used to take the player's stake
    /// @param house_data: The HouseData object
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
            user_randomness,
            fee_bp: base_fee_in_bp(house_data),
        };

        transfer::share_object(new_game);
    }

    /// Function used to create a new game. The player must provide a guess and a randomn vector of bytes.
    /// Stake is taken from the player's coin and added to the game's stake. The house's stake is also added to the game's stake.
    /// @param guess: The player's guess. Can be either 0 or 1
    /// @param user_randomness: A vector of randomly produced bytes that will be used to calculate the result of the VRF
    /// @param coin: The coin object that will be used to take the player's stake
    /// @param house_data: The HouseData object
    /// @param capy: The SuiFren<Capy> object that will be used to determine the capy owner's fee & verify capy ownership
    public entry fun start_game_with_capy(capy: SuiFren<Capy>, guess: u8, user_randomness: vector<u8>, coin: Coin<SUI>, house_data: &mut HouseData, ctx: &mut TxContext) {
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
            user_randomness,
            fee_bp: capy_owner_fee_in_bp(house_data),
        };

        // Return the capy back to its owner
        transfer::public_transfer(capy, tx_context::sender(ctx));

        transfer::share_object(new_game);
    }

    /// Function that determines the winner and distributes the funds accordingly.
    /// Anyone can end the game (game & house_data objects are shared).
    /// If an incorrect bls sig is passed the function will abort.
    /// A shared Outcome object is created to signal that the game has ended. Contains the winner, guess, and the unsigned message used as an input in the VRF.
    /// @param game: The Game object
    /// @param bls_sig: The bls signature of the game id and the player's randomn bytes appended together
    /// @param house_data: The HouseData object
    public entry fun play(game: &mut Game, bls_sig: vector<u8>, house_data: &mut HouseData, ctx: &mut TxContext) {
        // Step 1: Check the bls signature, if its invalid, house loses
        let messageVector = *&object::id_bytes(game);
        vector::append(&mut messageVector, player_randomness(game));
        let is_sig_valid = bls12381_min_pk_verify(&bls_sig, &house_data.public_key, &messageVector);
        assert!(is_sig_valid, EInvalidBlsSig);
        // Step 2: Determine winner
        let first_byte = vector::borrow(&bls_sig, 0);
        let player_won: bool = game.guess == *first_byte % 2;

        // Step 3: Distribute funds based on result & charge fee
        // Calculate the fee and transfer it to the house
        let amount = fee_amount(game);
        let fees = balance::split(&mut game.stake, amount);
        balance::join(&mut house_data.fees, fees);

        // Calculate the rewards and take it from the game stake
        let remaining_value = stake(game);
        let coin = coin::take(&mut game.stake, remaining_value, ctx);

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

    /// Function used to cancel a game after EPOCHS_CANCEL_AFTER epochs have passed. Can be called by anyone.
    /// On successful execution the entire game stake is returned to the player.
    /// @param game: The Game object
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