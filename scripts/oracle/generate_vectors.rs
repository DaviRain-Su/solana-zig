// Requires Rust + solana-sdk = 4.0.1
// Usage:
//   cargo run --manifest-path scripts/oracle/Cargo.toml --release

use solana_sdk::{hash::Hash, pubkey::Pubkey};

fn hex(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push_str(&format!("{:02x}", byte));
    }
    out
}

fn shortvec_encode(mut value: usize) -> Vec<u8> {
    let mut out = Vec::new();
    loop {
        let mut byte = (value & 0x7f) as u8;
        value >>= 7;
        if value != 0 {
            byte |= 0x80;
        }
        out.push(byte);
        if value == 0 {
            break;
        }
    }
    out
}

fn main() {
    let pubkey_zero_bytes = [0u8; 32];
    let pubkey_nonzero_bytes: [u8; 32] = core::array::from_fn(|i| (i as u8) + 1);
    let pubkey_leading_zero_bytes = [
        0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
        23, 24, 25, 26, 27, 28,
    ];
    let hash_nonzero_bytes: [u8; 32] = core::array::from_fn(|i| 255u8.saturating_sub(i as u8));

    let pubkey_zero = Pubkey::new_from_array(pubkey_zero_bytes);
    let pubkey_nonzero = Pubkey::new_from_array(pubkey_nonzero_bytes);
    let pubkey_leading_zero = Pubkey::new_from_array(pubkey_leading_zero_bytes);
    let hash_nonzero = Hash::new_from_array(hash_nonzero_bytes);

    assert_eq!(pubkey_zero.to_string(), "11111111111111111111111111111111");
    assert_eq!(hex(&shortvec_encode(300)), "ac02");

    let json = format!(
        r#"{{
  "meta": {{
    "schema_version": 2,
    "solana_sdk_version": "4.0.1",
    "generator": "scripts/oracle/generate_vectors.rs"
  }},
  "core": {{
    "pubkey_zero": {{
      "base58": "{pubkey_zero}",
      "hex": "{pubkey_zero_hex}"
    }},
    "pubkey_nonzero": {{
      "base58": "{pubkey_nonzero}",
      "hex": "{pubkey_nonzero_hex}"
    }},
    "pubkey_leading_zero_bytes": {{
      "base58": "{pubkey_leading_zero}",
      "hex": "{pubkey_leading_zero_hex}"
    }},
    "hash_nonzero": {{
      "hex": "{hash_nonzero_hex}"
    }},
    "shortvec": {{
      "0": "{shortvec_0}",
      "127": "{shortvec_127}",
      "128": "{shortvec_128}",
      "300": "{shortvec_300}",
      "16384": "{shortvec_16384}"
    }}
  }}
}}
"#,
        pubkey_zero = pubkey_zero,
        pubkey_zero_hex = hex(&pubkey_zero_bytes),
        pubkey_nonzero = pubkey_nonzero,
        pubkey_nonzero_hex = hex(&pubkey_nonzero_bytes),
        pubkey_leading_zero = pubkey_leading_zero,
        pubkey_leading_zero_hex = hex(&pubkey_leading_zero_bytes),
        hash_nonzero_hex = hex(hash_nonzero.as_ref()),
        shortvec_0 = hex(&shortvec_encode(0)),
        shortvec_127 = hex(&shortvec_encode(127)),
        shortvec_128 = hex(&shortvec_encode(128)),
        shortvec_300 = hex(&shortvec_encode(300)),
        shortvec_16384 = hex(&shortvec_encode(16384)),
    );

    std::fs::write("testdata/oracle_vectors.json", json)
        .expect("write testdata/oracle_vectors.json");
    println!(
        "wrote testdata/oracle_vectors.json with schema v2 core vectors ({})",
        hash_nonzero
    );
}
