const std = @import("std");
const hash_mod = @import("../core/hash.zig");
const keypair_mod = @import("../core/keypair.zig");
const pubkey_mod = @import("../core/pubkey.zig");
const shortvec = @import("../core/shortvec.zig");
const signature_mod = @import("../core/signature.zig");
const instruction_mod = @import("../tx/instruction.zig");
const lookup_mod = @import("../tx/address_lookup_table.zig");
const message_mod = @import("../tx/message.zig");
const transaction_mod = @import("../tx/transaction.zig");

pub const OracleVectors = struct {
    meta: Meta,
    core: Core,
    keypair: KeypairCases,
    message: MessageCases,
    transaction: TransactionCases,

    pub const Meta = struct {
        schema_version: u32,
        solana_sdk_version: []const u8,
        generator: []const u8,
    };

    pub const Base58HexCase = struct {
        base58: []const u8,
        hex: []const u8,
    };

    pub const HexCase = struct {
        hex: []const u8,
    };

    pub const ShortvecCases = struct {
        @"0": []const u8,
        @"127": []const u8,
        @"128": []const u8,
        @"300": []const u8,
        @"16384": []const u8,
    };

    pub const Core = struct {
        pubkey_zero: Base58HexCase,
        pubkey_nonzero: Base58HexCase,
        pubkey_leading_zero_bytes: Base58HexCase,
        hash_nonzero: HexCase,
        shortvec: ShortvecCases,
    };

    pub const KeypairSignatureCase = struct {
        seed_hex: []const u8,
        pubkey_base58: []const u8,
        message_utf8: []const u8,
        message_hex: []const u8,
        signature_base58: []const u8,
    };

    pub const KeypairCases = struct {
        kp_sig_seed_01: KeypairSignatureCase,
        kp_sig_seed_02: KeypairSignatureCase,
    };

    pub const AccountMetaCase = struct {
        pubkey: []const u8,
        is_signer: bool,
        is_writable: bool,
    };

    pub const InstructionCase = struct {
        program_id: []const u8,
        accounts: []const AccountMetaCase,
        data_hex: []const u8,
    };

    pub const LookupEntryCase = struct {
        index: u8,
        pubkey: []const u8,
    };

    pub const LookupTableCase = struct {
        account_key: []const u8,
        writable: []const LookupEntryCase,
        readonly: []const LookupEntryCase,
    };

    pub const MessageCase = struct {
        version: []const u8,
        payer: []const u8,
        recent_blockhash_hex: []const u8,
        instructions: []const InstructionCase,
        lookups: []const LookupTableCase,
        serialized_hex: []const u8,
    };

    pub const MessageCases = struct {
        msg_legacy_simple: MessageCase,
        msg_legacy_multi_ix: MessageCase,
        msg_v0_basic_alt: MessageCase,
        msg_v0_multi_lookup: MessageCase,
    };

    pub const TransactionCase = struct {
        message_case: []const u8,
        signer_seed_hex: []const u8,
        serialized_hex: []const u8,
    };

    pub const TransactionCases = struct {
        tx_legacy_signed: TransactionCase,
        tx_v0_signed: TransactionCase,
    };
};

const PreparedInstructions = struct {
    allocator: std.mem.Allocator,
    instructions: []instruction_mod.Instruction,
    account_slices: [][]instruction_mod.AccountMeta,
    data_slices: [][]u8,

    fn deinit(self: *PreparedInstructions) void {
        for (self.account_slices) |accounts| self.allocator.free(accounts);
        for (self.data_slices) |data| self.allocator.free(data);
        self.allocator.free(self.instructions);
        self.allocator.free(self.account_slices);
        self.allocator.free(self.data_slices);
    }
};

const PreparedLookups = struct {
    allocator: std.mem.Allocator,
    tables: []lookup_mod.AddressLookupTable,
    writable_entries: [][]lookup_mod.LookupEntry,
    readonly_entries: [][]lookup_mod.LookupEntry,

    fn deinit(self: *PreparedLookups) void {
        for (self.writable_entries) |entries| self.allocator.free(entries);
        for (self.readonly_entries) |entries| self.allocator.free(entries);
        self.allocator.free(self.tables);
        self.allocator.free(self.writable_entries);
        self.allocator.free(self.readonly_entries);
    }
};

pub fn loadEmbeddedVectors() !std.json.Parsed(OracleVectors) {
    return std.json.parseFromSlice(
        OracleVectors,
        std.heap.page_allocator,
        @embedFile("../../../testdata/oracle_vectors.json"),
        .{},
    );
}

fn hexToFixed(comptime N: usize, input: []const u8) ![N]u8 {
    if (input.len != N * 2) return error.InvalidLength;

    var out: [N]u8 = undefined;
    for (0..N) |i| {
        const hi = try std.fmt.charToDigit(input[i * 2], 16);
        const lo = try std.fmt.charToDigit(input[i * 2 + 1], 16);
        out[i] = @as(u8, @intCast((hi << 4) | lo));
    }

    return out;
}

fn hexToAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    if ((input.len & 1) != 0) return error.InvalidLength;
    const out = try allocator.alloc(u8, input.len / 2);
    errdefer allocator.free(out);

    for (0..out.len) |i| {
        const hi = try std.fmt.charToDigit(input[i * 2], 16);
        const lo = try std.fmt.charToDigit(input[i * 2 + 1], 16);
        out[i] = @as(u8, @intCast((hi << 4) | lo));
    }

    return out;
}

fn expectPubkeyCase(vector: OracleVectors.Base58HexCase) !void {
    const expected_bytes = try hexToFixed(32, vector.hex);
    const pk = try pubkey_mod.Pubkey.fromBase58(vector.base58);
    try std.testing.expectEqualSlices(u8, &expected_bytes, &pk.bytes);
}

fn expectShortvecCase(value: usize, encoded_hex: []const u8) !void {
    const encoded = try shortvec.encodeAlloc(std.testing.allocator, value);
    defer std.testing.allocator.free(encoded);
    const expected = try hexToAlloc(std.testing.allocator, encoded_hex);
    defer std.testing.allocator.free(expected);
    try std.testing.expectEqualSlices(u8, expected, encoded);
}

fn expectKeypairSignatureCase(case: OracleVectors.KeypairSignatureCase) !void {
    const seed = try hexToFixed(32, case.seed_hex);
    const keypair = try keypair_mod.Keypair.fromSeed(seed);
    const expected_pubkey = try pubkey_mod.Pubkey.fromBase58(case.pubkey_base58);
    try std.testing.expect(keypair.pubkey().eql(expected_pubkey));

    const message_bytes = try hexToAlloc(std.testing.allocator, case.message_hex);
    defer std.testing.allocator.free(message_bytes);
    try std.testing.expectEqualSlices(u8, case.message_utf8, message_bytes);

    const signature = try keypair.sign(message_bytes);
    const expected_signature = try signature_mod.Signature.fromBase58(case.signature_base58);
    try std.testing.expectEqualSlices(u8, &expected_signature.bytes, &signature.bytes);
    try signature.verify(message_bytes, expected_pubkey);
}

fn prepareInstructions(
    allocator: std.mem.Allocator,
    instruction_cases: []const OracleVectors.InstructionCase,
) !PreparedInstructions {
    const instructions = try allocator.alloc(instruction_mod.Instruction, instruction_cases.len);
    errdefer allocator.free(instructions);
    const account_slices = try allocator.alloc([]instruction_mod.AccountMeta, instruction_cases.len);
    errdefer allocator.free(account_slices);
    const data_slices = try allocator.alloc([]u8, instruction_cases.len);
    errdefer allocator.free(data_slices);

    var initialized: usize = 0;
    errdefer {
        for (account_slices[0..initialized]) |accounts| allocator.free(accounts);
        for (data_slices[0..initialized]) |data| allocator.free(data);
    }

    for (instruction_cases, 0..) |instruction_case, i| {
        const accounts = try allocator.alloc(instruction_mod.AccountMeta, instruction_case.accounts.len);
        errdefer allocator.free(accounts);
        for (instruction_case.accounts, 0..) |account_case, account_index| {
            accounts[account_index] = .{
                .pubkey = try pubkey_mod.Pubkey.fromBase58(account_case.pubkey),
                .is_signer = account_case.is_signer,
                .is_writable = account_case.is_writable,
            };
        }

        const data = try hexToAlloc(allocator, instruction_case.data_hex);

        instructions[i] = .{
            .program_id = try pubkey_mod.Pubkey.fromBase58(instruction_case.program_id),
            .accounts = accounts,
            .data = data,
        };
        account_slices[i] = accounts;
        data_slices[i] = data;
        initialized += 1;
    }

    return .{
        .allocator = allocator,
        .instructions = instructions,
        .account_slices = account_slices,
        .data_slices = data_slices,
    };
}

fn prepareLookups(
    allocator: std.mem.Allocator,
    lookup_cases: []const OracleVectors.LookupTableCase,
) !PreparedLookups {
    const tables = try allocator.alloc(lookup_mod.AddressLookupTable, lookup_cases.len);
    errdefer allocator.free(tables);
    const writable_entries = try allocator.alloc([]lookup_mod.LookupEntry, lookup_cases.len);
    errdefer allocator.free(writable_entries);
    const readonly_entries = try allocator.alloc([]lookup_mod.LookupEntry, lookup_cases.len);
    errdefer allocator.free(readonly_entries);

    var initialized: usize = 0;
    errdefer {
        for (writable_entries[0..initialized]) |entries| allocator.free(entries);
        for (readonly_entries[0..initialized]) |entries| allocator.free(entries);
    }

    for (lookup_cases, 0..) |lookup_case, i| {
        const writable = try allocator.alloc(lookup_mod.LookupEntry, lookup_case.writable.len);
        errdefer allocator.free(writable);
        for (lookup_case.writable, 0..) |entry_case, entry_index| {
            writable[entry_index] = .{
                .index = entry_case.index,
                .pubkey = try pubkey_mod.Pubkey.fromBase58(entry_case.pubkey),
            };
        }

        const readonly = try allocator.alloc(lookup_mod.LookupEntry, lookup_case.readonly.len);
        errdefer allocator.free(readonly);
        for (lookup_case.readonly, 0..) |entry_case, entry_index| {
            readonly[entry_index] = .{
                .index = entry_case.index,
                .pubkey = try pubkey_mod.Pubkey.fromBase58(entry_case.pubkey),
            };
        }

        tables[i] = .{
            .account_key = try pubkey_mod.Pubkey.fromBase58(lookup_case.account_key),
            .writable = writable,
            .readonly = readonly,
        };
        writable_entries[i] = writable;
        readonly_entries[i] = readonly;
        initialized += 1;
    }

    return .{
        .allocator = allocator,
        .tables = tables,
        .writable_entries = writable_entries,
        .readonly_entries = readonly_entries,
    };
}

fn compileMessageCase(
    allocator: std.mem.Allocator,
    message_case: OracleVectors.MessageCase,
) !message_mod.Message {
    const payer = try pubkey_mod.Pubkey.fromBase58(message_case.payer);
    const recent_blockhash = hash_mod.Hash.init(try hexToFixed(32, message_case.recent_blockhash_hex));

    var prepared_instructions = try prepareInstructions(allocator, message_case.instructions);
    defer prepared_instructions.deinit();
    var prepared_lookups = try prepareLookups(allocator, message_case.lookups);
    defer prepared_lookups.deinit();

    if (std.mem.eql(u8, message_case.version, "legacy")) {
        return message_mod.Message.compileLegacy(
            allocator,
            payer,
            prepared_instructions.instructions,
            recent_blockhash,
        );
    }
    if (std.mem.eql(u8, message_case.version, "v0")) {
        return message_mod.Message.compileV0(
            allocator,
            payer,
            prepared_instructions.instructions,
            recent_blockhash,
            prepared_lookups.tables,
        );
    }

    return error.UnsupportedMessageVersion;
}

fn expectMessageCase(message_case: OracleVectors.MessageCase) !void {
    var compiled = try compileMessageCase(std.testing.allocator, message_case);
    defer compiled.deinit();

    const encoded = try compiled.serialize(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    const expected = try hexToAlloc(std.testing.allocator, message_case.serialized_hex);
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualSlices(u8, expected, encoded);
}

fn lookupMessageCase(
    cases: OracleVectors.MessageCases,
    name: []const u8,
) !OracleVectors.MessageCase {
    if (std.mem.eql(u8, name, "msg_legacy_simple")) return cases.msg_legacy_simple;
    if (std.mem.eql(u8, name, "msg_legacy_multi_ix")) return cases.msg_legacy_multi_ix;
    if (std.mem.eql(u8, name, "msg_v0_basic_alt")) return cases.msg_v0_basic_alt;
    if (std.mem.eql(u8, name, "msg_v0_multi_lookup")) return cases.msg_v0_multi_lookup;
    return error.UnknownMessageCase;
}

fn expectTransactionCase(
    message_cases: OracleVectors.MessageCases,
    transaction_case: OracleVectors.TransactionCase,
) !void {
    const message_case = try lookupMessageCase(message_cases, transaction_case.message_case);
    var message = try compileMessageCase(std.testing.allocator, message_case);
    errdefer message.deinit();

    var tx = try transaction_mod.VersionedTransaction.initUnsigned(std.testing.allocator, message);
    defer tx.deinit();

    const signer_seed = try hexToFixed(32, transaction_case.signer_seed_hex);
    const signer = try keypair_mod.Keypair.fromSeed(signer_seed);

    try tx.sign(&[_]keypair_mod.Keypair{signer});
    try tx.verifySignatures();

    const encoded = try tx.serialize(std.testing.allocator);
    defer std.testing.allocator.free(encoded);
    const expected = try hexToAlloc(std.testing.allocator, transaction_case.serialized_hex);
    defer std.testing.allocator.free(expected);

    try std.testing.expectEqualSlices(u8, expected, encoded);
}

test "oracle vectors validate v2 schema core cases" {
    var parsed = try loadEmbeddedVectors();
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u32, 2), parsed.value.meta.schema_version);

    try expectPubkeyCase(parsed.value.core.pubkey_zero);
    try expectPubkeyCase(parsed.value.core.pubkey_nonzero);
    try expectPubkeyCase(parsed.value.core.pubkey_leading_zero_bytes);

    const expected_hash_bytes = try hexToFixed(32, parsed.value.core.hash_nonzero.hex);
    const hash = hash_mod.Hash.init(expected_hash_bytes);
    try std.testing.expectEqualSlices(u8, &expected_hash_bytes, &hash.bytes);

    try expectShortvecCase(0, parsed.value.core.shortvec.@"0");
    try expectShortvecCase(127, parsed.value.core.shortvec.@"127");
    try expectShortvecCase(128, parsed.value.core.shortvec.@"128");
    try expectShortvecCase(300, parsed.value.core.shortvec.@"300");
    try expectShortvecCase(16384, parsed.value.core.shortvec.@"16384");
}

test "oracle vectors validate deterministic keypair and signature cases" {
    var parsed = try loadEmbeddedVectors();
    defer parsed.deinit();

    try expectKeypairSignatureCase(parsed.value.keypair.kp_sig_seed_01);
    try expectKeypairSignatureCase(parsed.value.keypair.kp_sig_seed_02);
}

test "oracle vectors validate legacy and v0 message serialization cases" {
    var parsed = try loadEmbeddedVectors();
    defer parsed.deinit();

    try expectMessageCase(parsed.value.message.msg_legacy_simple);
    try expectMessageCase(parsed.value.message.msg_legacy_multi_ix);
    try expectMessageCase(parsed.value.message.msg_v0_basic_alt);
    try expectMessageCase(parsed.value.message.msg_v0_multi_lookup);
}

test "oracle vectors validate legacy and v0 transaction serialization cases" {
    var parsed = try loadEmbeddedVectors();
    defer parsed.deinit();

    try expectTransactionCase(parsed.value.message, parsed.value.transaction.tx_legacy_signed);
    try expectTransactionCase(parsed.value.message, parsed.value.transaction.tx_v0_signed);
}
