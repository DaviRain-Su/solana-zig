// Requires Rust + solana-sdk = 4.0.1
// Usage:
//   cargo run --manifest-path scripts/oracle/Cargo.toml --release

use serde_json::{json, Value};
use solana_sdk::{
    hash::Hash,
    instruction::{AccountMeta, Instruction},
    message::{v0, AddressLookupTableAccount, Message, VersionedMessage},
    pubkey::Pubkey,
    signature::{keypair_from_seed, Keypair, Signer},
    transaction::VersionedTransaction,
};

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

fn tx_wire_bytes(tx: &VersionedTransaction) -> Vec<u8> {
    let mut out = shortvec_encode(tx.signatures.len());
    for signature in &tx.signatures {
        out.extend_from_slice(signature.as_ref());
    }
    out.extend_from_slice(&tx.message.serialize());
    out
}

fn pubkey_case_json(pubkey: &Pubkey) -> Value {
    json!({
        "base58": pubkey.to_string(),
        "hex": hex(pubkey.as_ref()),
    })
}

fn lookup_entry_json(index: u8, pubkey: &Pubkey) -> Value {
    json!({
        "index": index,
        "pubkey": pubkey.to_string(),
    })
}

fn account_meta_json(meta: &AccountMeta) -> Value {
    json!({
        "pubkey": meta.pubkey.to_string(),
        "is_signer": meta.is_signer,
        "is_writable": meta.is_writable,
    })
}

fn instruction_json(ix: &Instruction) -> Value {
    let accounts: Vec<Value> = ix.accounts.iter().map(account_meta_json).collect();
    json!({
        "program_id": ix.program_id.to_string(),
        "accounts": accounts,
        "data_hex": hex(&ix.data),
    })
}

fn message_case_json(
    name: &str,
    version: &str,
    payer: &Pubkey,
    recent_blockhash: &Hash,
    instructions: &[Instruction],
    lookup_tables: &[AddressLookupTableAccount],
    serialized: &[u8],
) -> (String, Value) {
    let instructions_json: Vec<Value> = instructions.iter().map(instruction_json).collect();
    let lookup_tables_json: Vec<Value> = lookup_tables
        .iter()
        .map(|table| {
            let writable = if table.addresses.is_empty() {
                Vec::new()
            } else {
                table.addresses
                    .iter()
                    .enumerate()
                    .filter(|(index, _)| *index % 2 == 0)
                    .map(|(index, pubkey)| lookup_entry_json(index as u8, pubkey))
                    .collect()
            };
            let readonly = table
                .addresses
                .iter()
                .enumerate()
                .filter(|(index, _)| *index % 2 == 1)
                .map(|(index, pubkey)| lookup_entry_json(index as u8, pubkey))
                .collect::<Vec<_>>();

            json!({
                "account_key": table.key.to_string(),
                "writable": writable,
                "readonly": readonly,
            })
        })
        .collect();

    (
        name.to_owned(),
        json!({
            "version": version,
            "payer": payer.to_string(),
            "recent_blockhash_hex": hex(recent_blockhash.as_ref()),
            "instructions": instructions_json,
            "lookups": lookup_tables_json,
            "serialized_hex": hex(serialized),
        }),
    )
}

fn build_keypair_case(seed: [u8; 32], message: &[u8]) -> Value {
    let keypair = keypair_from_seed(&seed).expect("keypair_from_seed");
    let signature = keypair.sign_message(message);
    json!({
        "seed_hex": hex(&seed),
        "pubkey_base58": keypair.pubkey().to_string(),
        "message_utf8": String::from_utf8_lossy(message),
        "message_hex": hex(message),
        "signature_base58": signature.to_string(),
    })
}

fn legacy_message(
    payer: &Keypair,
    recent_blockhash: Hash,
    instructions: Vec<Instruction>,
) -> Message {
    Message::new_with_blockhash(&instructions, Some(&payer.pubkey()), &recent_blockhash)
}

fn v0_message(
    payer: &Keypair,
    recent_blockhash: Hash,
    instructions: Vec<Instruction>,
    lookup_tables: Vec<AddressLookupTableAccount>,
) -> v0::Message {
    v0::Message::try_compile(
        &payer.pubkey(),
        &instructions,
        &lookup_tables,
        recent_blockhash,
    )
    .expect("v0::Message::try_compile")
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

    let seed_01 = [0x11u8; 32];
    let seed_02 = [0x22u8; 32];
    let payer_legacy = keypair_from_seed(&seed_01).expect("payer legacy");
    let payer_v0 = keypair_from_seed(&seed_02).expect("payer v0");

    let receiver = Pubkey::new_from_array([0x31u8; 32]);
    let alt_writable = Pubkey::new_from_array([0x32u8; 32]);
    let alt_readonly = Pubkey::new_from_array([0x33u8; 32]);
    let alt_extra_writable = Pubkey::new_from_array([0x34u8; 32]);
    let alt_extra_readonly = Pubkey::new_from_array([0x35u8; 32]);
    let auxiliary_signer = Pubkey::new_from_array([0x36u8; 32]);
    let program_simple = Pubkey::new_from_array([0x41u8; 32]);
    let program_extra = Pubkey::new_from_array([0x42u8; 32]);
    let lookup_table_a = Pubkey::new_from_array([0x51u8; 32]);
    let lookup_table_b = Pubkey::new_from_array([0x52u8; 32]);

    let blockhash_legacy_simple = Hash::new_from_array([0x61u8; 32]);
    let blockhash_legacy_multi = Hash::new_from_array([0x62u8; 32]);
    let blockhash_v0_basic = Hash::new_from_array([0x63u8; 32]);
    let blockhash_v0_multi = Hash::new_from_array([0x64u8; 32]);

    let legacy_simple_instructions = vec![Instruction::new_with_bytes(
        program_simple,
        &[0x01, 0x02, 0x03, 0x04],
        vec![
            AccountMeta::new(payer_legacy.pubkey(), true),
            AccountMeta::new(receiver, false),
        ],
    )];
    let legacy_simple = legacy_message(
        &payer_legacy,
        blockhash_legacy_simple,
        legacy_simple_instructions.clone(),
    );

    let legacy_multi_instructions = vec![
        Instruction::new_with_bytes(
            program_simple,
            &[0xaa, 0xbb],
            vec![
                AccountMeta::new(payer_legacy.pubkey(), true),
                AccountMeta::new(receiver, false),
                AccountMeta::new_readonly(auxiliary_signer, false),
            ],
        ),
        Instruction::new_with_bytes(
            program_extra,
            &[0xcc, 0xdd, 0xee],
            vec![
                AccountMeta::new(payer_legacy.pubkey(), true),
                AccountMeta::new(receiver, false),
            ],
        ),
    ];
    let legacy_multi = legacy_message(
        &payer_legacy,
        blockhash_legacy_multi,
        legacy_multi_instructions.clone(),
    );

    let basic_alt_table = AddressLookupTableAccount {
        key: lookup_table_a,
        addresses: vec![alt_writable, alt_readonly],
    };
    let v0_basic_instructions = vec![Instruction::new_with_bytes(
        program_simple,
        &[0x10, 0x20, 0x30],
        vec![
            AccountMeta::new(payer_v0.pubkey(), true),
            AccountMeta::new(alt_writable, false),
            AccountMeta::new_readonly(alt_readonly, false),
        ],
    )];
    let v0_basic = v0_message(
        &payer_v0,
        blockhash_v0_basic,
        v0_basic_instructions.clone(),
        vec![basic_alt_table.clone()],
    );

    let multi_alt_table_a = AddressLookupTableAccount {
        key: lookup_table_a,
        addresses: vec![alt_writable, alt_readonly],
    };
    let multi_alt_table_b = AddressLookupTableAccount {
        key: lookup_table_b,
        addresses: vec![alt_extra_writable, alt_extra_readonly],
    };
    let v0_multi_instructions = vec![
        Instruction::new_with_bytes(
            program_simple,
            &[0x99],
            vec![
                AccountMeta::new(payer_v0.pubkey(), true),
                AccountMeta::new(alt_writable, false),
                AccountMeta::new_readonly(alt_readonly, false),
            ],
        ),
        Instruction::new_with_bytes(
            program_extra,
            &[0x44, 0x55],
            vec![
                AccountMeta::new(payer_v0.pubkey(), true),
                AccountMeta::new(alt_extra_writable, false),
                AccountMeta::new_readonly(alt_extra_readonly, false),
            ],
        ),
    ];
    let v0_multi = v0_message(
        &payer_v0,
        blockhash_v0_multi,
        v0_multi_instructions.clone(),
        vec![multi_alt_table_a.clone(), multi_alt_table_b.clone()],
    );

    let tx_legacy = VersionedTransaction::try_new(
        VersionedMessage::Legacy(legacy_simple.clone()),
        &[&payer_legacy],
    )
    .expect("legacy tx");
    let tx_v0 = VersionedTransaction::try_new(
        VersionedMessage::V0(v0_basic.clone()),
        &[&payer_v0],
    )
    .expect("v0 tx");

    assert_eq!(pubkey_zero.to_string(), "11111111111111111111111111111111");
    assert_eq!(hex(&shortvec_encode(300)), "ac02");

    let json = json!({
        "meta": {
            "schema_version": 2,
            "solana_sdk_version": "4.0.1",
            "generator": "scripts/oracle/generate_vectors.rs",
        },
        "core": {
            "pubkey_zero": pubkey_case_json(&pubkey_zero),
            "pubkey_nonzero": pubkey_case_json(&pubkey_nonzero),
            "pubkey_leading_zero_bytes": pubkey_case_json(&pubkey_leading_zero),
            "hash_nonzero": {
                "hex": hex(hash_nonzero.as_ref()),
            },
            "shortvec": {
                "0": hex(&shortvec_encode(0)),
                "127": hex(&shortvec_encode(127)),
                "128": hex(&shortvec_encode(128)),
                "300": hex(&shortvec_encode(300)),
                "16384": hex(&shortvec_encode(16384)),
            },
        },
        "keypair": {
            "kp_sig_seed_01": build_keypair_case(seed_01, b"oracle-kp-sig-case-01"),
            "kp_sig_seed_02": build_keypair_case(seed_02, b"oracle-kp-sig-case-02"),
        },
        "message": Value::Object(
            [
                message_case_json(
                    "msg_legacy_simple",
                    "legacy",
                    &payer_legacy.pubkey(),
                    &blockhash_legacy_simple,
                    &legacy_simple_instructions,
                    &[],
                    &legacy_simple.serialize(),
                ),
                message_case_json(
                    "msg_legacy_multi_ix",
                    "legacy",
                    &payer_legacy.pubkey(),
                    &blockhash_legacy_multi,
                    &legacy_multi_instructions,
                    &[],
                    &legacy_multi.serialize(),
                ),
                message_case_json(
                    "msg_v0_basic_alt",
                    "v0",
                    &payer_v0.pubkey(),
                    &blockhash_v0_basic,
                    &v0_basic_instructions,
                    &[basic_alt_table],
                    &v0_basic.serialize(),
                ),
                message_case_json(
                    "msg_v0_multi_lookup",
                    "v0",
                    &payer_v0.pubkey(),
                    &blockhash_v0_multi,
                    &v0_multi_instructions,
                    &[multi_alt_table_a, multi_alt_table_b],
                    &v0_multi.serialize(),
                ),
            ]
            .into_iter()
            .collect()
        ),
        "transaction": {
            "tx_legacy_signed": {
                "message_case": "msg_legacy_simple",
                "signer_seed_hex": hex(&seed_01),
                "serialized_hex": hex(&tx_wire_bytes(&tx_legacy)),
            },
            "tx_v0_signed": {
                "message_case": "msg_v0_basic_alt",
                "signer_seed_hex": hex(&seed_02),
                "serialized_hex": hex(&tx_wire_bytes(&tx_v0)),
            },
        },
    });

    let mut rendered = serde_json::to_string_pretty(&json).expect("serialize vectors");
    rendered.push('\n');
    std::fs::write("testdata/oracle_vectors.json", rendered)
        .expect("write testdata/oracle_vectors.json");
    println!(
        "wrote testdata/oracle_vectors.json with schema v2 phase1 oracle vectors ({})",
        hash_nonzero
    );
}
