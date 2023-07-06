module desuilabs::dlab {
    /// One time witness is only instantiated in the init method
    struct DLAB has drop {}

    /// Can be used for authorization of other actions post-creation. It is
    /// vital that this struct is not freely given to any contract, because it
    /// serves as an auth token.
    struct Witness has drop {}

    struct Dlab has key, store {
        id: sui::object::UID,
        name: std::string::String,
        description: std::string::String,
        url: sui::url::Url,
        attributes: nft_protocol::attributes::Attributes,
    }

    fun init(witness: DLAB, ctx: &mut sui::tx_context::TxContext) {
        let delegated_witness = ob_permissions::witness::from_witness(Witness {});

        let collection = nft_protocol::collection::create<Dlab>(delegated_witness, ctx);
        let collection_id = sui::object::id(&collection);

        let creators = sui::vec_set::empty();
        sui::vec_set::insert(&mut creators, @0x61028a4c388514000a7de787c3f7b8ec1eb88d1bd2dbc0d3dfab37078e39630f);

        nft_protocol::collection::add_domain(
            delegated_witness,
            &mut collection,
            nft_protocol::creators::new(creators),
        );

        nft_protocol::collection::add_domain(
            delegated_witness,
            &mut collection,
            nft_protocol::display_info::new(
                std::string::utf8(b"DeSuiLabs"),
                std::string::utf8(b"2222 Degenerates running experiments on the Blockchain."),
            ),
        );

        nft_protocol::collection::add_domain(
            delegated_witness,
            &mut collection,
            nft_protocol::symbol::new(std::string::utf8(b"DLAB")),
        );

        let royalty_map = sui::vec_map::empty();
        sui::vec_map::insert(&mut royalty_map, @0x61028a4c388514000a7de787c3f7b8ec1eb88d1bd2dbc0d3dfab37078e39630f, 1000);
        sui::vec_map::insert(&mut royalty_map, @0xa6e6f36c9eab8e8bc2e4a82e225f25da703a55a2cbd4d3eefbd11b41e8888a24, 9000);

        nft_protocol::royalty_strategy_bps::create_domain_and_add_strategy(
            delegated_witness,
            &mut collection,
            nft_protocol::royalty::from_shares(royalty_map, ctx),
            1000,
            ctx,
        );

        sui::transfer::public_share_object(collection);

        let mint_cap = nft_protocol::mint_cap::new_limited<DLAB, Dlab>(
            &witness, collection_id, 2222, ctx
        );
        sui::transfer::public_transfer(mint_cap, sui::tx_context::sender(ctx));

        let publisher = sui::package::claim(witness, ctx);

        let display = sui::display::new<Dlab>(&publisher, ctx);
        sui::display::add(&mut display, std::string::utf8(b"name"), std::string::utf8(b"{name}"));
        sui::display::add(&mut display, std::string::utf8(b"description"), std::string::utf8(b"{description}"));
        sui::display::add(&mut display, std::string::utf8(b"image_url"), std::string::utf8(b"{url}"));
        sui::display::add(&mut display, std::string::utf8(b"attributes"), std::string::utf8(b"{attributes}"));

        let tags = std::vector::empty();
        std::vector::push_back(&mut tags, std::string::utf8(b"PFP"));
        std::vector::push_back(&mut tags, std::string::utf8(b"Utility"));
        std::vector::push_back(&mut tags, std::string::utf8(b"Gaming"));

        sui::display::add(&mut display, std::string::utf8(b"tags"), ob_utils::display::from_vec(tags));
        sui::display::update_version(&mut display);

        sui::transfer::public_transfer(display, sui::tx_context::sender(ctx));

        let (transfer_policy, transfer_policy_cap) = ob_request::transfer_request::init_policy<Dlab>(
            &publisher, ctx,
        );
        nft_protocol::royalty_strategy_bps::enforce(&mut transfer_policy, &transfer_policy_cap);
        nft_protocol::transfer_allowlist::enforce(&mut transfer_policy, &transfer_policy_cap);

        let (withdraw_policy, withdraw_policy_cap) = ob_request::withdraw_request::init_policy<Dlab>(
            &publisher, ctx,
        );
        ob_request::request::enforce_rule_no_state<ob_request::request::WithNft<Dlab, ob_request::withdraw_request::WITHDRAW_REQ>, Witness>(
            &mut withdraw_policy, &withdraw_policy_cap,
        );

        // Protected orderbook such that trading is not initially possible
        let orderbook = liquidity_layer_v1::orderbook::new_with_protected_actions<Dlab, sui::sui::SUI>(
            delegated_witness, &transfer_policy, liquidity_layer_v1::orderbook::custom_protection(true, true, true), ctx,
        );
        liquidity_layer_v1::orderbook::share(orderbook);

        sui::transfer::public_transfer(publisher, sui::tx_context::sender(ctx));

        sui::transfer::public_transfer(transfer_policy_cap, sui::tx_context::sender(ctx));
        sui::transfer::public_share_object(transfer_policy);

        sui::transfer::public_transfer(withdraw_policy_cap, sui::tx_context::sender(ctx));
        sui::transfer::public_share_object(withdraw_policy);
    }

    public entry fun mint_nft_to_warehouse(
        name: std::string::String,
        description: std::string::String,
        url: vector<u8>,
        attributes_keys: vector<std::ascii::String>,
        attributes_values: vector<std::ascii::String>,
        mint_cap: &mut nft_protocol::mint_cap::MintCap<Dlab>,
        warehouse: &mut ob_launchpad::warehouse::Warehouse<Dlab>,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let nft = mint(
            name,
            description,
            url,
            attributes_keys,
            attributes_values,
            mint_cap,
            ctx,
        );

        ob_launchpad::warehouse::deposit_nft(warehouse, nft);
    }

    public entry fun mint_nft_to_kiosk(
        name: std::string::String,
        description: std::string::String,
        url: vector<u8>,
        attributes_keys: vector<std::ascii::String>,
        attributes_values: vector<std::ascii::String>,
        mint_cap: &mut nft_protocol::mint_cap::MintCap<Dlab>,
        receiver: &mut sui::kiosk::Kiosk,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let nft = mint(
            name,
            description,
            url,
            attributes_keys,
            attributes_values,
            mint_cap,
            ctx,
        );

        ob_kiosk::ob_kiosk::deposit(receiver, nft, ctx);
    }

    public entry fun mint_nft_to_new_kiosk(
        name: std::string::String,
        description: std::string::String,
        url: vector<u8>,
        attributes_keys: vector<std::ascii::String>,
        attributes_values: vector<std::ascii::String>,
        mint_cap: &mut nft_protocol::mint_cap::MintCap<Dlab>,
        receiver: address,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let nft = mint(
            name,
            description,
            url,
            attributes_keys,
            attributes_values,
            mint_cap,
            ctx,
        );

        let (kiosk, _) = ob_kiosk::ob_kiosk::new_for_address(receiver, ctx);
        ob_kiosk::ob_kiosk::deposit(&mut kiosk, nft, ctx);
        sui::transfer::public_share_object(kiosk);
    }

    fun mint(
        name: std::string::String,
        description: std::string::String,
        url: vector<u8>,
        attributes_keys: vector<std::ascii::String>,
        attributes_values: vector<std::ascii::String>,
        mint_cap: &mut nft_protocol::mint_cap::MintCap<Dlab>,
        ctx: &mut sui::tx_context::TxContext,
    ): Dlab {
        let delegated_witness = ob_permissions::witness::from_witness(Witness {});

        let nft = Dlab {
            id: sui::object::new(ctx),
            name,
            description,
            url: sui::url::new_unsafe_from_bytes(url),
            attributes: nft_protocol::attributes::from_vec(attributes_keys, attributes_values),
        };

        nft_protocol::mint_event::emit_mint(
            delegated_witness,
            nft_protocol::mint_cap::collection_id(mint_cap),
            &nft,
        );

        nft_protocol::mint_cap::increment_supply(mint_cap, 1);

        nft
    }

    public fun burn_nft(
        collection: &nft_protocol::collection::Collection<Dlab>,
        nft: Dlab,
    ) {
        let delegated_witness = ob_permissions::witness::from_witness(Witness {});
        let guard = nft_protocol::mint_event::start_burn(delegated_witness, &nft);
        let Dlab { id, name: _, description: _, url: _, attributes: _ } = nft;
        nft_protocol::mint_event::emit_burn(guard, sui::object::id(collection), id);
    }

    public entry fun burn_nft_in_kiosk(
        collection: &nft_protocol::collection::Collection<Dlab>,
        kiosk: &mut sui::kiosk::Kiosk,
        nft_id: sui::object::ID,
        policy: &ob_request::request::Policy<ob_request::request::WithNft<Dlab, ob_request::withdraw_request::WITHDRAW_REQ>>,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let (nft, withdraw_request) = ob_kiosk::ob_kiosk::withdraw_nft_signed(kiosk, nft_id, ctx);
        ob_request::withdraw_request::add_receipt(&mut withdraw_request, &Witness {});
        ob_request::withdraw_request::confirm(withdraw_request, policy);

        burn_nft(collection, nft);
    }

    public entry fun burn_nft_in_listing(
        collection: &nft_protocol::collection::Collection<Dlab>,
        listing: &mut ob_launchpad::listing::Listing,
        inventory_id: sui::object::ID,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let nft = ob_launchpad::listing::admin_redeem_nft<Dlab>(listing, inventory_id, ctx);
        burn_nft(collection, nft);
    }

    public entry fun burn_nft_in_listing_with_id(
        collection: &nft_protocol::collection::Collection<Dlab>,
        listing: &mut ob_launchpad::listing::Listing,
        inventory_id: sui::object::ID,
        nft_id: sui::object::ID,
        ctx: &mut sui::tx_context::TxContext,
    ) {
        let nft = ob_launchpad::listing::admin_redeem_nft_with_id(listing, inventory_id, nft_id, ctx);
        burn_nft(collection, nft);
    }

    #[test_only]
    const CREATOR: address = @0xA1C04;

    #[test]
    fun it_inits_collection() {
        let scenario = sui::test_scenario::begin(CREATOR);

        init(DLAB {}, sui::test_scenario::ctx(&mut scenario));
        sui::test_scenario::next_tx(&mut scenario, CREATOR);

        assert!(sui::test_scenario::has_most_recent_shared<nft_protocol::collection::Collection<Dlab>>(), 0);

        let mint_cap = sui::test_scenario::take_from_address<nft_protocol::mint_cap::MintCap<Dlab>>(
            &scenario, CREATOR,
        );

        sui::test_scenario::return_to_address(CREATOR, mint_cap);
        sui::test_scenario::next_tx(&mut scenario, CREATOR);

        sui::test_scenario::end(scenario);
    }

    #[test]
    fun it_mints_nft_airdrop() {
        let scenario = sui::test_scenario::begin(CREATOR);
        init(DLAB {}, sui::test_scenario::ctx(&mut scenario));

        sui::test_scenario::next_tx(&mut scenario, CREATOR);

        let mint_cap = sui::test_scenario::take_from_address<nft_protocol::mint_cap::MintCap<Dlab>>(
            &scenario,
            CREATOR,
        );

        let (kiosk, _) = ob_kiosk::ob_kiosk::new(sui::test_scenario::ctx(&mut scenario));

        mint_nft_to_kiosk(
            std::string::utf8(b"TEST STRING"),
            std::string::utf8(b"TEST STRING"),
            b"https://originbyte.io",
            vector[std::ascii::string(b"key")],
            vector[std::ascii::string(b"attribute")],
            &mut mint_cap,
            &mut kiosk,
            sui::test_scenario::ctx(&mut scenario)
        );

        sui::transfer::public_share_object(kiosk);
        sui::test_scenario::return_to_address(CREATOR, mint_cap);
        sui::test_scenario::end(scenario);
    }

    #[test]
    fun it_mints_nft_launchpad() {
        let scenario = sui::test_scenario::begin(CREATOR);
        init(DLAB {}, sui::test_scenario::ctx(&mut scenario));

        sui::test_scenario::next_tx(&mut scenario, CREATOR);

        let mint_cap = sui::test_scenario::take_from_address<nft_protocol::mint_cap::MintCap<Dlab>>(
            &scenario,
            CREATOR,
        );

        let warehouse = ob_launchpad::warehouse::new<Dlab>(sui::test_scenario::ctx(&mut scenario));

        mint_nft_to_warehouse(
            std::string::utf8(b"TEST STRING"),
            std::string::utf8(b"TEST STRING"),
            b"https://originbyte.io",
            vector[std::ascii::string(b"key")],
            vector[std::ascii::string(b"attribute")],
            &mut mint_cap,
            &mut warehouse,
            sui::test_scenario::ctx(&mut scenario)
        );

        sui::transfer::public_transfer(warehouse, CREATOR);
        sui::test_scenario::return_to_address(CREATOR, mint_cap);
        sui::test_scenario::end(scenario);
    }

        #[test]
        fun it_burns_nft() {
            let scenario = sui::test_scenario::begin(CREATOR);
            init(DLAB {}, sui::test_scenario::ctx(&mut scenario));

            sui::test_scenario::next_tx(&mut scenario, CREATOR);

            let mint_cap = sui::test_scenario::take_from_address<nft_protocol::mint_cap::MintCap<Dlab>>(
                &scenario,
                CREATOR,
            );

            let publisher = sui::test_scenario::take_from_address<sui::package::Publisher>(
                &scenario,
                CREATOR,
            );

            let collection = sui::test_scenario::take_shared<nft_protocol::collection::Collection<Dlab>>(
                &scenario
            );

            let withdraw_policy = sui::test_scenario::take_shared<
                ob_request::request::Policy<
                    ob_request::request::WithNft<Dlab, ob_request::withdraw_request::WITHDRAW_REQ>
                >
            >(&scenario);

            let nft = mint(
                std::string::utf8(b"TEST STRING"),
                std::string::utf8(b"TEST STRING"),
                b"https://originbyte.io",
                vector[std::ascii::string(b"key")],
                vector[std::ascii::string(b"attribute")],
                &mut mint_cap,
                sui::test_scenario::ctx(&mut scenario)
            );
            let nft_id = sui::object::id(&nft);

            let (kiosk, _) = ob_kiosk::ob_kiosk::new(sui::test_scenario::ctx(&mut scenario));
            ob_kiosk::ob_kiosk::deposit(&mut kiosk, nft, sui::test_scenario::ctx(&mut scenario));

            burn_nft_in_kiosk(
                &collection,
                &mut kiosk,
                nft_id,
                &withdraw_policy,
                sui::test_scenario::ctx(&mut scenario)
            );

            sui::test_scenario::return_to_address(CREATOR, mint_cap);
            sui::test_scenario::return_to_address(CREATOR, publisher);
            sui::test_scenario::return_shared(collection);
            sui::test_scenario::return_shared(withdraw_policy);
            sui::transfer::public_share_object(kiosk);
            sui::test_scenario::end(scenario);
        }

    #[test]
    fun test_trade() {
        let scenario = sui::test_scenario::begin(CREATOR);

        init(DLAB {}, sui::test_scenario::ctx(&mut scenario));
        sui::test_scenario::next_tx(&mut scenario, CREATOR);

        // Setup allowlist
        let (allowlist, allowlist_cap) = ob_allowlist::allowlist::new(sui::test_scenario::ctx(&mut scenario));
        ob_allowlist::allowlist::insert_authority<liquidity_layer_v1::orderbook::Witness>(&allowlist_cap, &mut allowlist);

        let publisher = sui::test_scenario::take_from_address<sui::package::Publisher>(
            &scenario, CREATOR,
        );

        // Need to insert all tradeable types into collection
        ob_allowlist::allowlist::insert_collection<Dlab>(&mut allowlist, &publisher);
        sui::transfer::public_share_object(allowlist);
        sui::transfer::public_transfer(allowlist_cap, CREATOR);

        // Setup orderbook
        let orderbook = sui::test_scenario::take_shared<liquidity_layer_v1::orderbook::Orderbook<Dlab, sui::sui::SUI>>(&scenario);
        liquidity_layer_v1::orderbook::enable_orderbook(&publisher, &mut orderbook);

        sui::test_scenario::return_to_address(CREATOR, publisher);

        // Setup test NFT
        let mint_cap = sui::test_scenario::take_from_address<nft_protocol::mint_cap::MintCap<Dlab>>(
            &mut scenario, CREATOR,
        );

        let nft = mint(
            std::string::utf8(b"TEST STRING"),
            std::string::utf8(b"TEST STRING"),
            b"https://originbyte.io",
            vector[std::ascii::string(b"key")],
            vector[std::ascii::string(b"attribute")],
            &mut mint_cap,
            sui::test_scenario::ctx(&mut scenario),
        );
        let nft_id = sui::object::id(&nft);

        sui::test_scenario::return_to_address(CREATOR, mint_cap);

        // Deposit NFT into Kiosk
        let (kiosk, _) = ob_kiosk::ob_kiosk::new(sui::test_scenario::ctx(&mut scenario));
        ob_kiosk::ob_kiosk::deposit(&mut kiosk, nft, sui::test_scenario::ctx(&mut scenario));
        sui::transfer::public_share_object(kiosk);

        sui::test_scenario::next_tx(&mut scenario, CREATOR);

        // Test trade
        let seller_kiosk = sui::test_scenario::take_shared<sui::kiosk::Kiosk>(&scenario);
        let (buyer_kiosk, _) = ob_kiosk::ob_kiosk::new(sui::test_scenario::ctx(&mut scenario));

        liquidity_layer_v1::orderbook::create_ask(
            &mut orderbook,
            &mut seller_kiosk,
            100_000_000,
            nft_id,
            sui::test_scenario::ctx(&mut scenario),
        );

        let coin = sui::coin::mint_for_testing<sui::sui::SUI>(100_000_000, sui::test_scenario::ctx(&mut scenario));

        let trade_opt = liquidity_layer_v1::orderbook::create_bid(
            &mut orderbook,
            &mut buyer_kiosk,
            100_000_000,
            &mut coin,
            sui::test_scenario::ctx(&mut scenario),
        );

        sui::coin::burn_for_testing(coin);
        let trade = std::option::destroy_some(trade_opt);

        let request = liquidity_layer_v1::orderbook::finish_trade(
            &mut orderbook,
            liquidity_layer_v1::orderbook::trade_id(&trade),
            &mut seller_kiosk,
            &mut buyer_kiosk,
            sui::test_scenario::ctx(&mut scenario),
        );

        let allowlist = sui::test_scenario::take_shared<ob_allowlist::allowlist::Allowlist>(&scenario);
        nft_protocol::transfer_allowlist::confirm_transfer(&allowlist, &mut request);
        sui::test_scenario::return_shared(allowlist);

        let royalty_strategy = sui::test_scenario::take_shared<nft_protocol::royalty_strategy_bps::BpsRoyaltyStrategy<Dlab>>(&mut scenario);
        nft_protocol::royalty_strategy_bps::confirm_transfer<Dlab, sui::sui::SUI>(&mut royalty_strategy, &mut request);
        sui::test_scenario::return_shared(royalty_strategy);

        let transfer_policy = sui::test_scenario::take_shared<sui::transfer_policy::TransferPolicy<Dlab>>(&scenario);
        ob_request::transfer_request::confirm<Dlab, sui::sui::SUI>(request, &transfer_policy, sui::test_scenario::ctx(&mut scenario));
        sui::test_scenario::return_shared(transfer_policy);

        ob_kiosk::ob_kiosk::assert_nft_type<Dlab>(&buyer_kiosk, nft_id);

        sui::transfer::public_share_object(buyer_kiosk);
        sui::test_scenario::return_shared(seller_kiosk);
        sui::test_scenario::return_shared(orderbook);
        sui::test_scenario::end(scenario);
    }
}
