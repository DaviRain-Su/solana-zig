use solana_sdk::signature::{Keypair, Signer};
use solana_sdk::pubkey::Pubkey;
use std::time::Instant;

fn bench_signer_sign(iters: usize) -> (u128, u128, u128) {
    let kp = Keypair::new();
    let msg = b"solana-zig-rust-benchmark-msg";

    for _ in 0..100 {
        let _ = kp.sign_message(msg);
    }

    let start = Instant::now();
    for _ in 0..iters {
        let _ = kp.sign_message(msg);
    }
    let total_us = start.elapsed().as_micros();
    let ns_op = (total_us * 1000) / iters as u128;
    let ops_sec = if total_us == 0 {
        0
    } else {
        (iters as u128 * 1_000_000) / total_us
    };

    (total_us, ns_op, ops_sec)
}

fn bench_pubkey_to_base58(iters: usize) -> (u128, u128, u128) {
    let pk = Pubkey::new_from_array([0x0A; 32]);

    for _ in 0..100 {
        let _ = pk.to_string();
    }

    let start = Instant::now();
    for _ in 0..iters {
        let _ = pk.to_string();
    }
    let total_us = start.elapsed().as_micros();
    let ns_op = (total_us * 1000) / iters as u128;
    let ops_sec = if total_us == 0 {
        0
    } else {
        (iters as u128 * 1_000_000) / total_us
    };

    (total_us, ns_op, ops_sec)
}

fn main() {
    let iters: usize = 10_000;

    println!("=== solana-zig Rust Baseline Benchmark ===");
    println!("iterations: {iters} (warmup: 100)");
    println!("columns: BENCH|op|profile|iters|total_us|ns_op|ops_sec");

    let (sign_total, sign_ns, sign_ops) = bench_signer_sign(iters);
    println!(
        "BENCH|rust_signer_sign|small|{iters}|{sign_total}|{sign_ns}|{sign_ops}"
    );

    let (b58_total, b58_ns, b58_ops) = bench_pubkey_to_base58(iters);
    println!(
        "BENCH|rust_pubkey_to_base58|small|{iters}|{b58_total}|{b58_ns}|{b58_ops}"
    );

    println!("=== rust benchmark complete ===");
}
