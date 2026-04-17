const std = @import("std");
const shortvec = @import("../core/shortvec.zig");
const signature_mod = @import("../core/signature.zig");
const keypair_mod = @import("../core/keypair.zig");
const message_mod = @import("message.zig");
const signer_mod = @import("../signers/signer.zig");

pub const VersionedTransaction = struct {
    allocator: std.mem.Allocator,
    signatures: []signature_mod.Signature,
    message: message_mod.Message,

    pub fn initUnsigned(allocator: std.mem.Allocator, message: message_mod.Message) !VersionedTransaction {
        try message.validateHeader();
        const sig_count = message.header.num_required_signatures;
        const signatures = try allocator.alloc(signature_mod.Signature, sig_count);
        for (signatures) |*sig| sig.* = signature_mod.Signature.zero();

        return .{
            .allocator = allocator,
            .signatures = signatures,
            .message = message,
        };
    }

    pub fn deinit(self: *VersionedTransaction) void {
        self.allocator.free(self.signatures);
        self.message.deinit();
    }

    pub fn sign(self: *VersionedTransaction, keypairs: []const keypair_mod.Keypair) !void {
        if (keypairs.len == 0) {
            try self.signWithSigners(&.{});
            return;
        }
        var signer_wrappers = try self.allocator.alloc(signer_mod.Signer, keypairs.len);
        defer self.allocator.free(signer_wrappers);

        var in_memory_signers = try self.allocator.alloc(@import("../signers/in_memory.zig").InMemorySigner, keypairs.len);
        defer self.allocator.free(in_memory_signers);

        for (keypairs, 0..) |kp, i| {
            in_memory_signers[i] = @import("../signers/in_memory.zig").InMemorySigner.init(kp);
            signer_wrappers[i] = in_memory_signers[i].asSigner();
        }

        try self.signWithSigners(signer_wrappers);
    }

    pub fn signWithSigners(self: *VersionedTransaction, signers: []const signer_mod.Signer) !void {
        try self.message.validateHeader();

        const required = @as(usize, self.message.header.num_required_signatures);
        if (required != self.signatures.len) return signer_mod.SignerError.SignatureCountMismatch;

        for (0..required) |i| {
            self.signatures[i] = signature_mod.Signature.zero();
        }

        const msg_bytes = try self.message.serialize(self.allocator);
        defer self.allocator.free(msg_bytes);

        for (signers) |signer| {
            const signer_key = try signer.getPubkey();
            const signer_index = findSignerIndex(self.message, signer_key) orelse continue;
            self.signatures[signer_index] = try signer.signMessage(self.allocator, msg_bytes);
        }

        for (self.signatures[0..required]) |sig| {
            if (sig.isZero()) return signer_mod.SignerError.MissingRequiredSignature;
        }
    }

    pub fn verifySignatures(self: VersionedTransaction) !void {
        try self.message.validateHeader();

        const msg_bytes = try self.message.serialize(self.allocator);
        defer self.allocator.free(msg_bytes);

        const required = self.message.header.num_required_signatures;
        if (required != self.signatures.len) return error.SignatureCountMismatch;

        for (0..required) |i| {
            const signer_key = self.message.account_keys[i];
            try self.signatures[i].verify(msg_bytes, signer_key);
        }
    }

    pub fn serialize(self: VersionedTransaction, allocator: std.mem.Allocator) ![]u8 {
        const message_bytes = try self.message.serialize(allocator);
        defer allocator.free(message_bytes);

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(allocator);

        try shortvec.encodeToList(&out, allocator, self.signatures.len);
        for (self.signatures) |sig| {
            try out.appendSlice(allocator, &sig.bytes);
        }

        try out.appendSlice(allocator, message_bytes);

        return try out.toOwnedSlice(allocator);
    }

    pub fn deserialize(allocator: std.mem.Allocator, bytes: []const u8) !VersionedTransaction {
        var cursor: usize = 0;

        const sig_len = try shortvec.decode(bytes);
        cursor += sig_len.consumed;

        const signatures = try allocator.alloc(signature_mod.Signature, sig_len.value);
        errdefer allocator.free(signatures);

        for (0..sig_len.value) |i| {
            if (cursor + signature_mod.Signature.LENGTH > bytes.len) return error.InvalidTransaction;
            signatures[i] = .{ .bytes = bytes[cursor .. cursor + signature_mod.Signature.LENGTH][0..signature_mod.Signature.LENGTH].* };
            cursor += signature_mod.Signature.LENGTH;
        }

        const decoded_message = try message_mod.Message.deserialize(allocator, bytes[cursor..]);
        cursor += decoded_message.consumed;

        if (sig_len.value != decoded_message.message.header.num_required_signatures) {
            var leaked = decoded_message.message;
            leaked.deinit();
            return error.InvalidTransaction;
        }

        if (cursor != bytes.len) {
            var leaked = decoded_message.message;
            leaked.deinit();
            return error.InvalidTransaction;
        }

        return .{
            .allocator = allocator,
            .signatures = signatures,
            .message = decoded_message.message,
        };
    }
};

fn findSignerIndex(message: message_mod.Message, key: @TypeOf(message.account_keys[0])) ?usize {
    const required = message.header.num_required_signatures;
    for (0..required) |i| {
        if (message.account_keys[i].eql(key)) return i;
    }

    return null;
}

test "transaction sign/serialize/deserialize" {
    const gpa = std.testing.allocator;

    const payer = try keypair_mod.Keypair.fromSeed([_]u8{8} ** 32);
    const receiver = @import("../core/pubkey.zig").Pubkey.init([_]u8{7} ** 32);
    const program = @import("../core/pubkey.zig").Pubkey.init([_]u8{6} ** 32);
    const blockhash = @import("../core/hash.zig").Hash.init([_]u8{5} ** 32);

    const accounts = [_]@import("instruction.zig").AccountMeta{
        .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
    };
    const payload = [_]u8{ 9, 9, 9 };
    const ixs = [_]@import("instruction.zig").Instruction{
        .{ .program_id = program, .accounts = &accounts, .data = &payload },
    };

    var msg = try message_mod.Message.compileLegacy(gpa, payer.pubkey(), &ixs, blockhash);
    errdefer msg.deinit();

    var tx = try VersionedTransaction.initUnsigned(gpa, msg);
    defer tx.deinit();

    try tx.sign(&[_]keypair_mod.Keypair{payer});
    try tx.verifySignatures();

    const serialized = try tx.serialize(gpa);
    defer gpa.free(serialized);

    var parsed = try VersionedTransaction.deserialize(gpa, serialized);
    defer parsed.deinit();

    try parsed.verifySignatures();
}

test "transaction sign fails when required signer missing" {
    const gpa = std.testing.allocator;

    const payer = try keypair_mod.Keypair.fromSeed([_]u8{3} ** 32);
    const receiver = @import("../core/pubkey.zig").Pubkey.init([_]u8{2} ** 32);
    const program = @import("../core/pubkey.zig").Pubkey.init([_]u8{1} ** 32);
    const blockhash = @import("../core/hash.zig").Hash.init([_]u8{7} ** 32);

    const accounts = [_]@import("instruction.zig").AccountMeta{
        .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
    };
    const ixs = [_]@import("instruction.zig").Instruction{
        .{ .program_id = program, .accounts = &accounts, .data = &.{} },
    };

    var msg = try message_mod.Message.compileLegacy(gpa, payer.pubkey(), &ixs, blockhash);
    errdefer msg.deinit();

    var tx = try VersionedTransaction.initUnsigned(gpa, msg);
    defer tx.deinit();

    try std.testing.expectError(signer_mod.SignerError.MissingRequiredSignature, tx.sign(&.{}));
}

test "transaction signWithSigners matches keypair path" {
    const gpa = std.testing.allocator;
    const pubkey_mod = @import("../core/pubkey.zig");
    const hash_mod = @import("../core/hash.zig");
    const instruction_mod = @import("instruction.zig");
    const InMemorySigner = @import("../signers/in_memory.zig").InMemorySigner;

    const payer = try keypair_mod.Keypair.fromSeed([_]u8{61} ** 32);
    const receiver = pubkey_mod.Pubkey.init([_]u8{62} ** 32);
    const program = pubkey_mod.Pubkey.init([_]u8{63} ** 32);
    const blockhash = hash_mod.Hash.init([_]u8{64} ** 32);

    const accounts = [_]instruction_mod.AccountMeta{
        .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
    };
    const ixs = [_]instruction_mod.Instruction{
        .{ .program_id = program, .accounts = &accounts, .data = &[_]u8{0xAB} },
    };

    var msg1 = try message_mod.Message.compileLegacy(gpa, payer.pubkey(), &ixs, blockhash);
    errdefer msg1.deinit();
    var tx1 = try VersionedTransaction.initUnsigned(gpa, msg1);
    defer tx1.deinit();
    try tx1.sign(&[_]keypair_mod.Keypair{payer});

    var msg2 = try message_mod.Message.compileLegacy(gpa, payer.pubkey(), &ixs, blockhash);
    errdefer msg2.deinit();
    var tx2 = try VersionedTransaction.initUnsigned(gpa, msg2);
    defer tx2.deinit();

    var im_signer = InMemorySigner.init(payer);
    try tx2.signWithSigners(&[_]signer_mod.Signer{im_signer.asSigner()});

    try std.testing.expectEqualSlices(u8, &tx1.signatures[0].bytes, &tx2.signatures[0].bytes);
}

test "transaction signWithSigners fails when required signer missing" {
    const gpa = std.testing.allocator;
    const pubkey_mod = @import("../core/pubkey.zig");
    const hash_mod = @import("../core/hash.zig");
    const instruction_mod = @import("instruction.zig");

    const payer = try keypair_mod.Keypair.fromSeed([_]u8{71} ** 32);
    const receiver = pubkey_mod.Pubkey.init([_]u8{72} ** 32);
    const program = pubkey_mod.Pubkey.init([_]u8{73} ** 32);
    const blockhash = hash_mod.Hash.init([_]u8{74} ** 32);

    const accounts = [_]instruction_mod.AccountMeta{
        .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
    };
    const ixs = [_]instruction_mod.Instruction{
        .{ .program_id = program, .accounts = &accounts, .data = &.{} },
    };

    var msg = try message_mod.Message.compileLegacy(gpa, payer.pubkey(), &ixs, blockhash);
    errdefer msg.deinit();
    var tx = try VersionedTransaction.initUnsigned(gpa, msg);
    defer tx.deinit();

    try std.testing.expectError(signer_mod.SignerError.MissingRequiredSignature, tx.signWithSigners(&.{}));
}

test "transaction signWithSigners clears stale signatures before applying signers" {
    const gpa = std.testing.allocator;
    const pubkey_mod = @import("../core/pubkey.zig");
    const hash_mod = @import("../core/hash.zig");
    const instruction_mod = @import("instruction.zig");

    const payer = try keypair_mod.Keypair.fromSeed([_]u8{75} ** 32);
    const receiver = pubkey_mod.Pubkey.init([_]u8{76} ** 32);
    const program = pubkey_mod.Pubkey.init([_]u8{77} ** 32);
    const blockhash = hash_mod.Hash.init([_]u8{78} ** 32);

    const accounts = [_]instruction_mod.AccountMeta{
        .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
    };
    const ixs = [_]instruction_mod.Instruction{
        .{ .program_id = program, .accounts = &accounts, .data = &.{} },
    };

    var msg = try message_mod.Message.compileLegacy(gpa, payer.pubkey(), &ixs, blockhash);
    errdefer msg.deinit();
    var tx = try VersionedTransaction.initUnsigned(gpa, msg);
    defer tx.deinit();

    tx.signatures[0] = signature_mod.Signature.init([_]u8{0xAB} ** signature_mod.Signature.LENGTH);

    try std.testing.expectError(signer_mod.SignerError.MissingRequiredSignature, tx.signWithSigners(&.{}));
}

test "verify signatures rejects malformed message header before indexing account keys" {
    const gpa = std.testing.allocator;
    const pubkey_mod = @import("../core/pubkey.zig");
    const hash_mod = @import("../core/hash.zig");

    const account_keys = try gpa.alloc(pubkey_mod.Pubkey, 1);
    errdefer gpa.free(account_keys);
    account_keys[0] = pubkey_mod.Pubkey.init([_]u8{1} ** 32);

    var message = message_mod.Message{
        .allocator = gpa,
        .version = .legacy,
        .header = .{
            .num_required_signatures = 2,
            .num_readonly_signed_accounts = 0,
            .num_readonly_unsigned_accounts = 0,
        },
        .account_keys = account_keys,
        .recent_blockhash = hash_mod.Hash.init([_]u8{2} ** 32),
        .instructions = &.{},
        .address_table_lookups = &.{},
    };
    errdefer message.deinit();

    const signatures = try gpa.alloc(signature_mod.Signature, 2);
    errdefer gpa.free(signatures);
    for (signatures) |*sig| sig.* = signature_mod.Signature.zero();

    var tx = VersionedTransaction{
        .allocator = gpa,
        .signatures = signatures,
        .message = message,
    };
    defer tx.deinit();

    try std.testing.expectError(error.InvalidMessage, tx.verifySignatures());
}

test "versioned_deserialize_rejects_truncated_signature_bytes" {
    const gpa = std.testing.allocator;

    const bytes = [_]u8{
        1, // signatures len
        0xAA, 0xBB, 0xCC, // truncated signature bytes
    };

    try std.testing.expectError(error.InvalidTransaction, VersionedTransaction.deserialize(gpa, &bytes));
}

test "versioned_deserialize_rejects_unsupported_message_version" {
    const gpa = std.testing.allocator;

    const sig = signature_mod.Signature.zero().bytes;
    const bytes = [_]u8{
        1, // signature vector len
    } ++ sig ++ [_]u8{
        0x81, // v1 message version (unsupported)
        0, 0, 0, // minimal header
        0, // empty account keys vec
    };

    try std.testing.expectError(error.UnsupportedMessageVersion, VersionedTransaction.deserialize(gpa, &bytes));
}

test "versioned_deserialize_rejects_trailing_bytes" {
    const gpa = std.testing.allocator;

    const payer = try keypair_mod.Keypair.fromSeed([_]u8{31} ** 32);
    const receiver = @import("../core/pubkey.zig").Pubkey.init([_]u8{32} ** 32);
    const program = @import("../core/pubkey.zig").Pubkey.init([_]u8{33} ** 32);
    const blockhash = @import("../core/hash.zig").Hash.init([_]u8{34} ** 32);

    const accounts = [_]@import("instruction.zig").AccountMeta{
        .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
    };
    const payload = [_]u8{7};
    const ixs = [_]@import("instruction.zig").Instruction{
        .{ .program_id = program, .accounts = &accounts, .data = &payload },
    };

    var message = try message_mod.Message.compileLegacy(gpa, payer.pubkey(), &ixs, blockhash);
    errdefer message.deinit();

    var tx = try VersionedTransaction.initUnsigned(gpa, message);
    defer tx.deinit();
    try tx.sign(&[_]keypair_mod.Keypair{payer});

    const encoded = try tx.serialize(gpa);
    defer gpa.free(encoded);

    var malformed = try gpa.alloc(u8, encoded.len + 1);
    defer gpa.free(malformed);
    @memcpy(malformed[0..encoded.len], encoded);
    malformed[encoded.len] = 0x42;

    try std.testing.expectError(error.InvalidTransaction, VersionedTransaction.deserialize(gpa, malformed));
}

test "versioned_deserialize_rejects_signature_count_mismatch" {
    const gpa = std.testing.allocator;

    const sig = signature_mod.Signature.zero().bytes;
    const account_key = [_]u8{1} ** 32;
    const blockhash = [_]u8{2} ** 32;
    const bytes = [_]u8{2} ++ sig ++ sig ++ [_]u8{
        1, // header.num_required_signatures
        0, // header.num_readonly_signed_accounts
        0, // header.num_readonly_unsigned_accounts
        1, // account_keys len
    } ++ account_key ++ blockhash ++ [_]u8{
        0, // instructions len
    };

    try std.testing.expectError(error.InvalidTransaction, VersionedTransaction.deserialize(gpa, &bytes));
}

test "transaction multi-signer legacy flow is order-independent" {
    const gpa = std.testing.allocator;
    const instruction_mod = @import("instruction.zig");
    const pubkey_mod = @import("../core/pubkey.zig");
    const hash_mod = @import("../core/hash.zig");

    const payer = try keypair_mod.Keypair.fromSeed([_]u8{41} ** 32);
    const co_signer = try keypair_mod.Keypair.fromSeed([_]u8{42} ** 32);
    const receiver = pubkey_mod.Pubkey.init([_]u8{43} ** 32);
    const program = pubkey_mod.Pubkey.init([_]u8{44} ** 32);
    const blockhash = hash_mod.Hash.init([_]u8{45} ** 32);

    const accounts = [_]instruction_mod.AccountMeta{
        .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
        .{ .pubkey = co_signer.pubkey(), .is_signer = true, .is_writable = false },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
    };
    const payload = [_]u8{ 0xAA, 0xBB };
    const ixs = [_]instruction_mod.Instruction{
        .{ .program_id = program, .accounts = &accounts, .data = &payload },
    };

    var message = try message_mod.Message.compileLegacy(gpa, payer.pubkey(), &ixs, blockhash);
    errdefer message.deinit();

    var tx = try VersionedTransaction.initUnsigned(gpa, message);
    defer tx.deinit();

    try tx.sign(&[_]keypair_mod.Keypair{ co_signer, payer });
    try tx.verifySignatures();
    try std.testing.expect(!tx.signatures[0].isZero());
    try std.testing.expect(!tx.signatures[1].isZero());

    const serialized = try tx.serialize(gpa);
    defer gpa.free(serialized);

    var parsed = try VersionedTransaction.deserialize(gpa, serialized);
    defer parsed.deinit();
    try parsed.verifySignatures();

    const reserialized = try parsed.serialize(gpa);
    defer gpa.free(reserialized);
    try std.testing.expectEqualSlices(u8, serialized, reserialized);
}

test "transaction sign serialize deserialize roundtrip supports v0 messages" {
    const gpa = std.testing.allocator;
    const instruction_mod = @import("instruction.zig");
    const lookup_mod = @import("address_lookup_table.zig");
    const pubkey_mod = @import("../core/pubkey.zig");
    const hash_mod = @import("../core/hash.zig");

    const payer = try keypair_mod.Keypair.fromSeed([_]u8{51} ** 32);
    const writable_lookup_account = pubkey_mod.Pubkey.init([_]u8{52} ** 32);
    const readonly_lookup_account = pubkey_mod.Pubkey.init([_]u8{53} ** 32);
    const program = pubkey_mod.Pubkey.init([_]u8{54} ** 32);
    const blockhash = hash_mod.Hash.init([_]u8{55} ** 32);

    const accounts = [_]instruction_mod.AccountMeta{
        .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
        .{ .pubkey = writable_lookup_account, .is_signer = false, .is_writable = true },
        .{ .pubkey = readonly_lookup_account, .is_signer = false, .is_writable = false },
    };
    const payload = [_]u8{ 0x10, 0x20, 0x30 };
    const ixs = [_]instruction_mod.Instruction{
        .{ .program_id = program, .accounts = &accounts, .data = &payload },
    };

    const writable_entries = [_]lookup_mod.LookupEntry{
        .{ .index = 5, .pubkey = writable_lookup_account },
    };
    const readonly_entries = [_]lookup_mod.LookupEntry{
        .{ .index = 7, .pubkey = readonly_lookup_account },
    };
    const lookup_tables = [_]lookup_mod.AddressLookupTable{
        .{
            .account_key = pubkey_mod.Pubkey.init([_]u8{56} ** 32),
            .writable = &writable_entries,
            .readonly = &readonly_entries,
        },
    };

    var message = try message_mod.Message.compileV0(gpa, payer.pubkey(), &ixs, blockhash, &lookup_tables);
    errdefer message.deinit();

    var tx = try VersionedTransaction.initUnsigned(gpa, message);
    defer tx.deinit();

    try tx.sign(&[_]keypair_mod.Keypair{payer});
    try tx.verifySignatures();

    const serialized = try tx.serialize(gpa);
    defer gpa.free(serialized);

    var parsed = try VersionedTransaction.deserialize(gpa, serialized);
    defer parsed.deinit();
    try parsed.verifySignatures();
    try std.testing.expectEqual(message_mod.MessageVersion.v0, parsed.message.version);
    try std.testing.expectEqual(@as(usize, 1), parsed.message.address_table_lookups.len);
    try std.testing.expectEqualSlices(u8, &[_]u8{5}, parsed.message.address_table_lookups[0].writable_indexes);
    try std.testing.expectEqualSlices(u8, &[_]u8{7}, parsed.message.address_table_lookups[0].readonly_indexes);

    const reserialized = try parsed.serialize(gpa);
    defer gpa.free(reserialized);
    try std.testing.expectEqualSlices(u8, serialized, reserialized);
}
