// Requires Rust + solana-sdk = 4.0.1
// Usage:
//   cargo run --manifest-path scripts/oracle/Cargo.toml --release

use solana_sdk::pubkey::Pubkey;

fn main() {
    let pk = Pubkey::new_from_array([0u8; 32]);

    // shortvec(300) => 0xac 0x02
    let json = r#"{
  \"pubkey_base58\": \"11111111111111111111111111111111\",
  \"pubkey_hex\": \"0000000000000000000000000000000000000000000000000000000000000000\",
  \"shortvec_300_hex\": \"ac02\"
}"#;

    // keep a runtime check so this script fails fast if assumptions change
    assert_eq!(pk.to_string(), "11111111111111111111111111111111");

    std::fs::write("testdata/oracle_vectors.json", json).expect("write testdata/oracle_vectors.json");
    println!("wrote testdata/oracle_vectors.json");
}
