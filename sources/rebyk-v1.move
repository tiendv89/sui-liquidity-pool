module rebyk_v1::rebyk_v1 {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::math;
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self, Supply, Balance};

    /// For when supplied Coin is zero.
    const EZeroAmount: u64 = 0;

    /// For when pool fee is set incorrectly.
    /// Allowed values are: [0-10000).
    const EWrongFee: u64 = 1;

    /// For when someone tries to swap in an empty pool.
    const EReservesEmpty: u64 = 2;

    /// For when someone attempts to add more liquidity than u128 Math allows.
    const EPoolFull: u64 = 4;

    /// For when input token is not one the two poken in target pool.
    const EInvalidInputToken : u64 = 5;

    /// The integer scaling setting for fees calculation.
    const FEE_SCALING: u128 = 10000;

    /// The max value that can be held in one of the Balances of
    /// a Pool. U64 MAX / FEE_SCALING
    const MAX_POOL_VALUE: u64 = {
        18446744073709551615 / 10000
    };

    struct RebykV1Admin has key {
        id: UID
    }

    struct LP<phantom T0, phantom T1> has drop {}

    struct Rebyk_V1<phantom T0, phantom T1> has key {
        id: UID,
        token0: Balance<T0>,
        token1: Balance<T1>,
        fee0: Balance<T0>,
        fee1: Balance<T1>,
        lsp_supply: Supply<LP<T0, T1>>,
        fee_percent: u64
    }

    fun init(ctx: &mut TxContext) {
        transfer::transfer(RebykV1Admin{
            id: object::new(ctx)
        }, tx_context::sender(ctx))
    }

    public entry fun change_admin(admin: RebykV1Admin, to: address ,_: &mut TxContext) {
        transfer::transfer(admin, to)
    }

    public entry fun create_pool<T0, T1>(
        _ : &RebykV1Admin,
        token0: Coin<T0>,
        token1: Coin<T1>,
        fee_percent: u64,
        ctx: &mut TxContext
    ) {
        let tok0_amt = coin::value(&token0);
        let tok1_amt = coin::value(&token1);

        assert!(tok0_amt > 0 && tok1_amt > 0, EZeroAmount);
        assert!(tok0_amt < MAX_POOL_VALUE && tok1_amt < MAX_POOL_VALUE, EPoolFull);
        assert!(fee_percent >= 0 && fee_percent < 10000, EWrongFee);
    
        // Initial share of LSP is the sqrt(a) * sqrt(b)
        let share = math::sqrt(tok0_amt) * math::sqrt(tok1_amt);
        let lsp_supply = balance::create_supply(LP<T0, T1> {});
        let lsp = balance::increase_supply(&mut lsp_supply, share);
    
        transfer::share_object( Rebyk_V1 {
            id: object::new(ctx),
            token0: coin::into_balance(token0),
            token1: coin::into_balance(token1),
            fee0: balance::zero<T0>(),
            fee1: balance::zero<T1>(),
            lsp_supply,
            fee_percent,
        });

        transfer::transfer(
            coin::from_balance(lsp, ctx),
            tx_context::sender(ctx)
        )
    }

    // public fun add_liquidity<T0, T1>(coin_x: Coin<X>, coin_y: Coin<Y>) {

    // }

    /// Entrypoint for the `swap_token0` & `swap_token1` methods. Sends swapped token
    /// to sender.
    public entry fun swap_token<T0, T1>(
        pool: &mut Rebyk_V1<T0, T1>, coin0: Coin<T0>, coin1: Coin<T1>, ctx: &mut TxContext
    ) {
        assert!(coin::value(&coin0) > 0 || coin::value(&coin1) > 0, EZeroAmount);
        
        if (coin::value(&coin0) == 0) {
            coin::destroy_zero<T0>(coin0);
        } else {
            transfer::transfer(swap_token0(pool, coin0, ctx), tx_context::sender(ctx));
        };

        if (coin::value(&coin1) == 0) {
            coin::destroy_zero<T1>(coin1);
        } else {
            transfer::transfer(swap_token1(pool, coin1, ctx), tx_context::sender(ctx));
        }
    }

    /// Swap Coin<T0> <-> Coin<T1>
    /// Returns Coin<T1> 
    public fun swap_token0<T0, T1>(
        pool: &mut Rebyk_V1<T0, T1>, token_in: Coin<T0>, ctx: &mut TxContext
    ): Coin<T1> {
        let token_in_balance = coin::into_balance(token_in);

        // Calculate the output amount - fee
        let (token0_reserve, token1_reserve, _) = get_amounts(pool);
        assert!(token0_reserve > 0 && token1_reserve > 0, EReservesEmpty);

        let (output_amount, fee_value) = get_input_price_and_fee(
            balance::value(&token_in_balance),
            token0_reserve,
            token1_reserve,
            pool.fee_percent
        );

        let fee_balance = balance::split(&mut token_in_balance, fee_value);
        balance::join(&mut pool.fee0, fee_balance);
        balance::join(&mut pool.token0, token_in_balance);
        coin::take(&mut pool.token1, output_amount, ctx)
    }

    /// Swap Coin<T0> <-> Coin<T1>
    /// Returns Coin<T1> 
    public fun swap_token1<T0, T1>(
        pool: &mut Rebyk_V1<T0, T1>, token_in: Coin<T1>, ctx: &mut TxContext
    ): Coin<T0> {
        let token_in_balance = coin::into_balance(token_in);

        // Calculate the output amount - fee
        let (token0_reserve, token1_reserve, _) = get_amounts(pool);
        assert!(token0_reserve > 0 && token1_reserve > 0, EReservesEmpty);

        let (output_amount, fee_value) = get_input_price_and_fee(
            balance::value(&token_in_balance),
            token1_reserve,
            token0_reserve,
            pool.fee_percent
        );

        let fee_balance = balance::split(&mut token_in_balance, fee_value);
        balance::join(&mut pool.fee1, fee_balance);
        balance::join(&mut pool.token1, token_in_balance);
        coin::take(&mut pool.token0, output_amount, ctx)
    }    

    /// Get most used values in a handy way:
    /// - amount of SUI
    /// - amount of token
    /// - total supply of LSP
    public fun get_amounts<T0, T1>(pool: &Rebyk_V1<T0, T1>): (u64, u64, u64) {
        (
            balance::value(&pool.token0),
            balance::value(&pool.token1),
            balance::supply_value(&pool.lsp_supply)
        )
    }

    /// Get fee values in a handy way:
    /// - fee amount in token0
    /// - fee amount in token1
    public fun get_fee<T0, T1>(pool: &Rebyk_V1<T0, T1>): (u64, u64) {
        (
            balance::value(&pool.fee0),
            balance::value(&pool.fee1)
        )
    }

    /// Calculate the output amount minus the fee - 0.3%
    public fun get_input_price_and_fee(
        input_amount: u64, input_reserve: u64, output_reserve: u64, fee_percent: u64
    ): (u64, u64) {
        // up casts
        let (
            input_amount,
            input_reserve,
            output_reserve,
            fee_percent
        ) = (
            (input_amount as u128),
            (input_reserve as u128),
            (output_reserve as u128),
            (fee_percent as u128)
        );

        let input_amount_with_fee = input_amount * (FEE_SCALING - fee_percent);
        let numerator = input_amount_with_fee * output_reserve;
        let denominator = (input_reserve * FEE_SCALING) + input_amount_with_fee;

        ((numerator / denominator as u64), ((input_amount * FEE_SCALING - input_amount_with_fee) / FEE_SCALING as u64))
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }

    #[test_only]
    const ADMIN: address = @0xACE;
    #[test_only]
    const INITIAL_TOKEN0_AMT: u64 = 50000000;
    #[test_only]
    const INITIAL_TOKEN1_AMT: u64 = 200000000000;
    #[test_only]
    const INITIAL_TOKEN_SHARE: u64 = 3162243123;
    #[test_only]
    const INITIAL_FEE_PERCENT: u64 = 50;
    #[test_only]
    const INPUT_AMOUNT0: u64 = 10000000;
    #[test_only]
    const INPUT_AMOUNT1: u64 = 10000000000;

    #[test_only]
    struct Coin0 has drop {}
    #[test_only]
    struct Coin1 has drop {}

    #[test_only]
    fun create_rebyk_v1(ctx: &mut TxContext, fee: u64) : Rebyk_V1<Coin0, Coin1> {
        // Initial share of LSP is the sqrt(a) * sqrt(b)
        let share = math::sqrt(INITIAL_TOKEN0_AMT) * math::sqrt(INITIAL_TOKEN1_AMT);
        let lsp_supply = balance::create_supply_for_testing<LP<Coin0, Coin1>>(share);

        // create a Rebyk V1 pool
        Rebyk_V1 {
            id: object::new(ctx),
            token0: balance::create_for_testing<Coin0>(INITIAL_TOKEN0_AMT),
            token1: balance::create_for_testing<Coin1>(INITIAL_TOKEN1_AMT),
            fee0: balance::create_for_testing<Coin0>(0),
            fee1: balance::create_for_testing<Coin1>(0),
            lsp_supply,
            fee_percent: fee
        }
    }

    #[test]
    fun test_token_amount_after_pool_creation() {
        // create a dummy TxContext for testing
        let ctx = tx_context::dummy();
        let rebyk = create_rebyk_v1(&mut ctx, INITIAL_FEE_PERCENT);

        let (t0, t1, l) = get_amounts<Coin0, Coin1>(&rebyk);
        assert!(t0 == INITIAL_TOKEN0_AMT, 1);
        assert!(t1 == INITIAL_TOKEN1_AMT, 1);
        assert!(l == INITIAL_TOKEN_SHARE, 1);

        // create a dummy address and transfer the sword
        let dummy_address = @0xCAFE;
        transfer::transfer(rebyk, dummy_address);
    }

    #[test]
    fun test_get_input_price_and_fee_for_token0() {
        // create a dummy TxContext for testing
        let ctx = tx_context::dummy();
        let rebyk = create_rebyk_v1(&mut ctx, INITIAL_FEE_PERCENT);

        let (t0, t1, _) = get_amounts<Coin0, Coin1>(&rebyk);
        let (output, fee_value) = get_input_price_and_fee(INPUT_AMOUNT0, t0, t1, INITIAL_FEE_PERCENT);

        assert!(fee_value == 50000, 1);
        assert!(output == 33194328607, 1);

        // create a dummy address and transfer the sword
        let dummy_address = @0xCAFE;
        transfer::transfer(rebyk, dummy_address);
    }
    
    #[test]
    fun test_get_input_price_and_fee_for_token1() {
        // create a dummy TxContext for testing
        let ctx = tx_context::dummy();
        let rebyk = create_rebyk_v1(&mut ctx, INITIAL_FEE_PERCENT);

        let (t0, t1, _) = get_amounts<Coin0, Coin1>(&rebyk);
        let (output, _) = get_input_price_and_fee(INPUT_AMOUNT1, t1, t0, INITIAL_FEE_PERCENT);

        assert!(output == 2369611, 1);

        // create a dummy address and transfer the sword
        let dummy_address = @0xCAFE;
        transfer::transfer(rebyk, dummy_address);
    }

    #[test]
    fun test_swap_token0() {
        // create a dummy TxContext for testing
        let ctx = tx_context::dummy();
        let rebyk = create_rebyk_v1(&mut ctx, INITIAL_FEE_PERCENT);

        let output = swap_token0<Coin0, Coin1>(&mut rebyk, coin::mint_for_testing<Coin0>(INPUT_AMOUNT0, &mut ctx), &mut ctx);
        let output_value = coin::destroy_for_testing<Coin1>(output);
        assert!(output_value == 33194328607, 1);

        // create a dummy address and transfer the sword
        let dummy_address = @0xCAFE;
        transfer::transfer(rebyk, dummy_address);
    }

    #[test]
    fun test_swap_token1() {
        // create a dummy TxContext for testing
        let ctx = tx_context::dummy();
        let rebyk = create_rebyk_v1(&mut ctx, INITIAL_FEE_PERCENT);

        let output = swap_token1<Coin0, Coin1>(&mut rebyk, coin::mint_for_testing<Coin1>(INPUT_AMOUNT1, &mut ctx), &mut ctx);
        let output_value = coin::destroy_for_testing<Coin0>(output);
        assert!(output_value == 2369611, 1);

        // create a dummy address and transfer the sword
        let dummy_address = @0xCAFE;
        transfer::transfer(rebyk, dummy_address);
    }
}