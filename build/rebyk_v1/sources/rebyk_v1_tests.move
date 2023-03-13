#[test_only]
module rebyk_v1::rebyk_v1_tests {
    use std::debug;
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::coin::{Self, Coin};
    use rebyk_v1::rebyk_v1::{Self, Rebyk_V1, RebykV1Admin};

    const ADMIN: address = @0xACE;
    const PEOPLE: address = @0xBEEF;
    const INITIAL_TOKEN0_AMT: u64 = 50000000;
    const INITIAL_TOKEN1_AMT: u64 = 200000000000;
    const INITIAL_TOKEN_SHARE: u64 = 3162243123;
    const INITIAL_FEE_PERCENT: u64 = 50;
    const INPUT_AMOUNT0: u64 = 10000000;
    const INPUT_AMOUNT1: u64 = 10000000000;

    struct Coin0 has drop {}
    struct Coin1 has drop {}

    #[test] fun test_create_pool() {
        let scenario = scenario();
        let scenario_val = &mut scenario;

        test_create_pool_(scenario_val);
        test::end(scenario);
    }

    #[test] fun test_swap_token0() {
        let scenario = scenario();
        test_swap_token0_(&mut scenario);
        test::end(scenario);
    }

    #[test] fun test_swap_token1() {
        let scenario = scenario();
        test_swap_token1_(&mut scenario);
        test::end(scenario);
    }

    fun test_create_pool_(scenario: &mut Scenario) {
        {
            rebyk_v1::init_for_testing(ctx(scenario));
        };

        next_tx(scenario, ADMIN);
        {
            let admin = test::take_from_sender<RebykV1Admin>(scenario);

            rebyk_v1::create_pool<Coin0, Coin1>(
                &admin,
                coin::mint_for_testing<Coin0>(INITIAL_TOKEN0_AMT, ctx(scenario)),
                coin::mint_for_testing<Coin1>(INITIAL_TOKEN1_AMT, ctx(scenario)),
                INITIAL_FEE_PERCENT,
                ctx(scenario)
            );

            test::return_to_sender(scenario, admin)
        };

        next_tx(scenario, ADMIN);
        {
            let pool = test::take_shared<Rebyk_V1<Coin0, Coin1>>(scenario);
            let pool_mut = &mut pool;

            let (amt_tok0, amt_tok1, l) = rebyk_v1::get_amounts(pool_mut);
            assert!(amt_tok0 == INITIAL_TOKEN0_AMT, 1);
            assert!(amt_tok1 == INITIAL_TOKEN1_AMT, 1);
            assert!(l == INITIAL_TOKEN_SHARE, 1);

            let (fee0, fee1) = rebyk_v1::get_fee(pool_mut);
            assert!(fee0 == 0, 1);
            assert!(fee1 == 0, 1);

            test::return_shared(pool)
        };
    }

    fun test_swap_token0_(scenario: &mut Scenario) {
        test_create_pool_(scenario);

        next_tx(scenario, PEOPLE);
        {
            let pool = test::take_shared<Rebyk_V1<Coin0, Coin1>>(scenario);
            let pool_mut = &mut pool;

            rebyk_v1::swap_token(pool_mut, coin::mint_for_testing<Coin0>(INPUT_AMOUNT0, ctx(scenario)), coin::mint_for_testing<Coin1>(0, ctx(scenario)), ctx(scenario));
            
            let (amt_tok0, amt_tok1, _) = rebyk_v1::get_amounts(pool_mut);
            assert!(amt_tok0 == 59950000, 1);
            assert!(amt_tok1 == 166805671393, 1);

            let (fee0, fee1) = rebyk_v1::get_fee(pool_mut);
            assert!(fee0 == 50000, 1);
            assert!(fee1 == 0, 1);

            test::return_shared(pool);
        };
        
        // It seems like the initial object is not modified within context of an tx.
        // Therefore, `transfer` tx happens in `rebyk_v1::swap_token` only happens after another `next_tx(...)` call.
        // Here we double-check that the sender of `swap_token` receive Coin<Coin1>
        next_tx(scenario, PEOPLE);
        {
            let coin1 = test::take_from_sender<Coin<Coin1>>(scenario);
            assert!(coin::value<Coin1>(&coin1) == 33194328607, 1);

            test::return_to_sender(scenario, coin1);
        };
    }

    fun test_swap_token1_(scenario: &mut Scenario) {
        test_create_pool_(scenario);

        next_tx(scenario, PEOPLE);
        {
            let pool = test::take_shared<Rebyk_V1<Coin0, Coin1>>(scenario);
            let pool_mut = &mut pool;

            rebyk_v1::swap_token(pool_mut, coin::mint_for_testing<Coin0>(0, ctx(scenario)), coin::mint_for_testing<Coin1>(INPUT_AMOUNT1, ctx(scenario)), ctx(scenario));
            
            let (amt_tok0, amt_tok1, _) = rebyk_v1::get_amounts(pool_mut);
            debug::print(&amt_tok0);
            debug::print(&amt_tok1);
            assert!(amt_tok0 == 47630389, 1);
            assert!(amt_tok1 == 209950000000, 1);

            let (fee0, fee1) = rebyk_v1::get_fee(pool_mut);
            assert!(fee0 == 0, 1);
            assert!(fee1 == 50000000, 1);

            test::return_shared(pool);
        };
        
        // It seems like the initial object is not modified within context of an tx.
        // Therefore, `transfer` tx happens in `rebyk_v1::swap_token` only happens after another `next_tx(...)` call.
        // Here we double-check that the sender of `swap_token` receive Coin<Coin1>
        next_tx(scenario, PEOPLE);
        {
            let coin0 = test::take_from_sender<Coin<Coin0>>(scenario);
            assert!(coin::value<Coin0>(&coin0) == 2369611, 1);

            test::return_to_sender(scenario, coin0);
        };
    }

    // utilities
    fun scenario(): Scenario { test::begin(ADMIN) }
}