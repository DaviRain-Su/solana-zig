const std = @import("std");
const hash_mod = @import("../core/hash.zig");
const pubkey_mod = @import("../core/pubkey.zig");
const shortvec = @import("../core/shortvec.zig");
const instruction_mod = @import("instruction.zig");
const lookup_mod = @import("address_lookup_table.zig");

pub const MessageVersion = enum { legacy, v0 };

pub const MessageHeader = struct {
    num_required_signatures: u8,
    num_readonly_signed_accounts: u8,
    num_readonly_unsigned_accounts: u8,
};

pub const CompiledInstruction = struct {
    program_id_index: u8,
    account_indexes: []u8,
    data: []u8,

    pub fn deinit(self: *CompiledInstruction, allocator: std.mem.Allocator) void {
        allocator.free(self.account_indexes);
        allocator.free(self.data);
    }
};

pub const CompiledAddressLookup = struct {
    account_key: pubkey_mod.Pubkey,
    writable_indexes: []u8,
    readonly_indexes: []u8,

    pub fn deinit(self: *CompiledAddressLookup, allocator: std.mem.Allocator) void {
        allocator.free(self.writable_indexes);
        allocator.free(self.readonly_indexes);
    }
};

pub const Message = struct {
    allocator: std.mem.Allocator,
    version: MessageVersion,
    header: MessageHeader,
    account_keys: []pubkey_mod.Pubkey,
    recent_blockhash: hash_mod.Hash,
    instructions: []CompiledInstruction,
    address_table_lookups: []CompiledAddressLookup,

    pub fn deinit(self: *@This()) void {
        for (self.instructions) |*ix| ix.deinit(self.allocator);
        self.allocator.free(self.instructions);

        for (self.address_table_lookups) |*lookup| lookup.deinit(self.allocator);
        self.allocator.free(self.address_table_lookups);

        self.allocator.free(self.account_keys);
    }

    pub fn compileLegacy(
        allocator: std.mem.Allocator,
        payer: pubkey_mod.Pubkey,
        instructions: []const instruction_mod.Instruction,
        recent_blockhash: hash_mod.Hash,
    ) !@This() {
        return compileInternal(allocator, .legacy, payer, instructions, recent_blockhash, &.{});
    }

    pub fn compileV0(
        allocator: std.mem.Allocator,
        payer: pubkey_mod.Pubkey,
        instructions: []const instruction_mod.Instruction,
        recent_blockhash: hash_mod.Hash,
        lookup_tables: []const lookup_mod.AddressLookupTable,
    ) !@This() {
        return compileInternal(allocator, .v0, payer, instructions, recent_blockhash, lookup_tables);
    }

    fn compileInternal(
        allocator: std.mem.Allocator,
        version: MessageVersion,
        payer: pubkey_mod.Pubkey,
        instructions: []const instruction_mod.Instruction,
        recent_blockhash: hash_mod.Hash,
        lookup_tables: []const lookup_mod.AddressLookupTable,
    ) !@This() {
        var static_roles: std.ArrayList(AccountRole) = .empty;
        defer static_roles.deinit(allocator);

        try upsertRole(&static_roles, allocator, payer, true, true);

        for (instructions) |ix| {
            for (ix.accounts) |account| {
                const can_use_lookup = version == .v0 and !account.is_signer and hasLookupKey(lookup_tables, account.pubkey);
                if (!can_use_lookup) {
                    try upsertRole(&static_roles, allocator, account.pubkey, account.is_signer, account.is_writable);
                }
            }
            try upsertRole(&static_roles, allocator, ix.program_id, false, false);
        }

        const ordered_roles = try orderRoles(allocator, static_roles.items);
        defer allocator.free(ordered_roles);

        const account_keys = try allocator.alloc(pubkey_mod.Pubkey, ordered_roles.len);
        for (ordered_roles, 0..) |role, i| account_keys[i] = role.key;

        var num_signers: u8 = 0;
        var num_readonly_signed: u8 = 0;
        var num_readonly_unsigned: u8 = 0;
        for (ordered_roles) |role| {
            if (role.is_signer) {
                num_signers += 1;
                if (!role.is_writable) num_readonly_signed += 1;
            } else {
                if (!role.is_writable) num_readonly_unsigned += 1;
            }
        }

        const header: MessageHeader = .{
            .num_required_signatures = num_signers,
            .num_readonly_signed_accounts = num_readonly_signed,
            .num_readonly_unsigned_accounts = num_readonly_unsigned,
        };

        var key_indexes: std.ArrayList(KeyIndex) = .empty;
        defer key_indexes.deinit(allocator);
        try key_indexes.ensureTotalCapacity(allocator, account_keys.len + 64);
        for (account_keys, 0..) |key, i| {
            try key_indexes.append(allocator, .{ .key = key, .index = @intCast(i) });
        }
        const static_key_count = key_indexes.items.len;

        var compiled_lookups: std.ArrayList(CompiledAddressLookup) = .empty;
        defer {
            for (compiled_lookups.items) |*lookup| lookup.deinit(allocator);
            compiled_lookups.deinit(allocator);
        }

        if (version == .v0) {
            var next_dynamic_index: usize = account_keys.len;

            for (lookup_tables) |table| {
                var writable_indexes: std.ArrayList(u8) = .empty;
                defer writable_indexes.deinit(allocator);
                var readonly_indexes: std.ArrayList(u8) = .empty;
                defer readonly_indexes.deinit(allocator);

                for (table.writable) |entry| {
                    if (!instructionUsesKey(instructions, entry.pubkey)) continue;
                    if (containsStaticKeyIndex(key_indexes.items, static_key_count, entry.pubkey)) continue;
                    if (containsDynamicKeyIndex(key_indexes.items, static_key_count, entry.pubkey)) return error.DuplicateLookupKey;
                    if (next_dynamic_index > std.math.maxInt(u8)) return error.TooManyAccounts;

                    try writable_indexes.append(allocator, entry.index);
                    try key_indexes.append(allocator, .{ .key = entry.pubkey, .index = @intCast(next_dynamic_index) });
                    next_dynamic_index += 1;
                }

                for (table.readonly) |entry| {
                    if (!instructionUsesKey(instructions, entry.pubkey)) continue;
                    if (containsStaticKeyIndex(key_indexes.items, static_key_count, entry.pubkey)) continue;
                    if (containsDynamicKeyIndex(key_indexes.items, static_key_count, entry.pubkey)) return error.DuplicateLookupKey;
                    if (next_dynamic_index > std.math.maxInt(u8)) return error.TooManyAccounts;

                    try readonly_indexes.append(allocator, entry.index);
                    try key_indexes.append(allocator, .{ .key = entry.pubkey, .index = @intCast(next_dynamic_index) });
                    next_dynamic_index += 1;
                }

                if (writable_indexes.items.len == 0 and readonly_indexes.items.len == 0) continue;

                try compiled_lookups.append(allocator, .{
                    .account_key = table.account_key,
                    .writable_indexes = try writable_indexes.toOwnedSlice(allocator),
                    .readonly_indexes = try readonly_indexes.toOwnedSlice(allocator),
                });
            }
        }

        var compiled_ixs: std.ArrayList(CompiledInstruction) = .empty;
        defer {
            for (compiled_ixs.items) |*ix| ix.deinit(allocator);
            compiled_ixs.deinit(allocator);
        }

        for (instructions) |ix| {
            const maybe_program_idx = findKeyIndex(key_indexes.items, ix.program_id);
            const program_idx = maybe_program_idx orelse return error.MissingProgramId;

            var acct_indexes: std.ArrayList(u8) = .empty;
            defer acct_indexes.deinit(allocator);

            try acct_indexes.ensureTotalCapacity(allocator, ix.accounts.len);
            for (ix.accounts) |account| {
                const idx = findKeyIndex(key_indexes.items, account.pubkey) orelse return error.MissingAccountKey;
                try acct_indexes.append(allocator, idx);
            }

            const data = try allocator.dupe(u8, ix.data);
            try compiled_ixs.append(allocator, .{
                .program_id_index = program_idx,
                .account_indexes = try acct_indexes.toOwnedSlice(allocator),
                .data = data,
            });
        }

        return .{
            .allocator = allocator,
            .version = version,
            .header = header,
            .account_keys = account_keys,
            .recent_blockhash = recent_blockhash,
            .instructions = try compiled_ixs.toOwnedSlice(allocator),
            .address_table_lookups = try compiled_lookups.toOwnedSlice(allocator),
        };
    }

    pub fn serialize(self: @This(), allocator: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(allocator);

        if (self.version == .v0) {
            try out.append(allocator, 0x80);
        }

        try out.append(allocator, self.header.num_required_signatures);
        try out.append(allocator, self.header.num_readonly_signed_accounts);
        try out.append(allocator, self.header.num_readonly_unsigned_accounts);

        try shortvec.encodeToList(&out, allocator, self.account_keys.len);
        for (self.account_keys) |key| {
            try out.appendSlice(allocator, &key.bytes);
        }

        try out.appendSlice(allocator, &self.recent_blockhash.bytes);

        try shortvec.encodeToList(&out, allocator, self.instructions.len);
        for (self.instructions) |ix| {
            try out.append(allocator, ix.program_id_index);
            try shortvec.encodeToList(&out, allocator, ix.account_indexes.len);
            try out.appendSlice(allocator, ix.account_indexes);
            try shortvec.encodeToList(&out, allocator, ix.data.len);
            try out.appendSlice(allocator, ix.data);
        }

        if (self.version == .v0) {
            try shortvec.encodeToList(&out, allocator, self.address_table_lookups.len);
            for (self.address_table_lookups) |lookup| {
                try out.appendSlice(allocator, &lookup.account_key.bytes);

                try shortvec.encodeToList(&out, allocator, lookup.writable_indexes.len);
                try out.appendSlice(allocator, lookup.writable_indexes);

                try shortvec.encodeToList(&out, allocator, lookup.readonly_indexes.len);
                try out.appendSlice(allocator, lookup.readonly_indexes);
            }
        }

        return try out.toOwnedSlice(allocator);
    }

    pub const DecodeResult = struct {
        message: @This(),
        consumed: usize,
    };

    pub fn deserialize(allocator: std.mem.Allocator, bytes: []const u8) !DecodeResult {
        var cursor: usize = 0;
        var version: MessageVersion = .legacy;

        if (bytes.len == 0) return error.InvalidMessage;

        if ((bytes[0] & 0x80) != 0) {
            const message_version = bytes[0] & 0x7f;
            if (message_version != 0) return error.UnsupportedMessageVersion;
            version = .v0;
            cursor += 1;
        }

        if (cursor + 3 > bytes.len) return error.InvalidMessage;
        const header: MessageHeader = .{
            .num_required_signatures = bytes[cursor],
            .num_readonly_signed_accounts = bytes[cursor + 1],
            .num_readonly_unsigned_accounts = bytes[cursor + 2],
        };
        cursor += 3;

        const key_len_result = try shortvec.decode(bytes[cursor..]);
        cursor += key_len_result.consumed;

        const key_len = key_len_result.value;
        const account_keys = try allocator.alloc(pubkey_mod.Pubkey, key_len);
        errdefer allocator.free(account_keys);

        for (0..key_len) |i| {
            if (cursor + pubkey_mod.Pubkey.LENGTH > bytes.len) return error.InvalidMessage;
            account_keys[i] = .{ .bytes = bytes[cursor .. cursor + pubkey_mod.Pubkey.LENGTH][0..pubkey_mod.Pubkey.LENGTH].* };
            cursor += pubkey_mod.Pubkey.LENGTH;
        }

        if (cursor + hash_mod.Hash.LENGTH > bytes.len) return error.InvalidMessage;
        const recent_blockhash: hash_mod.Hash = .{ .bytes = bytes[cursor .. cursor + hash_mod.Hash.LENGTH][0..hash_mod.Hash.LENGTH].* };
        cursor += hash_mod.Hash.LENGTH;

        const ix_len_result = try shortvec.decode(bytes[cursor..]);
        cursor += ix_len_result.consumed;

        const instructions = try allocator.alloc(CompiledInstruction, ix_len_result.value);
        errdefer {
            for (instructions) |*ix| ix.deinit(allocator);
            allocator.free(instructions);
        }

        for (0..ix_len_result.value) |i| {
            if (cursor >= bytes.len) return error.InvalidMessage;
            const program_id_index = bytes[cursor];
            cursor += 1;

            const acct_len_result = try shortvec.decode(bytes[cursor..]);
            cursor += acct_len_result.consumed;

            if (cursor + acct_len_result.value > bytes.len) return error.InvalidMessage;
            const acct_indexes = try allocator.dupe(u8, bytes[cursor .. cursor + acct_len_result.value]);
            cursor += acct_len_result.value;

            const data_len_result = try shortvec.decode(bytes[cursor..]);
            cursor += data_len_result.consumed;

            if (cursor + data_len_result.value > bytes.len) return error.InvalidMessage;
            const data = try allocator.dupe(u8, bytes[cursor .. cursor + data_len_result.value]);
            cursor += data_len_result.value;

            instructions[i] = .{
                .program_id_index = program_id_index,
                .account_indexes = acct_indexes,
                .data = data,
            };
        }

        var lookups: []CompiledAddressLookup = &.{};
        if (version == .v0) {
            const lookup_len_result = try shortvec.decode(bytes[cursor..]);
            cursor += lookup_len_result.consumed;

            lookups = try allocator.alloc(CompiledAddressLookup, lookup_len_result.value);
            errdefer {
                for (lookups) |*lookup| lookup.deinit(allocator);
                allocator.free(lookups);
            }

            for (0..lookup_len_result.value) |i| {
                if (cursor + pubkey_mod.Pubkey.LENGTH > bytes.len) return error.InvalidMessage;
                const account_key: pubkey_mod.Pubkey = .{ .bytes = bytes[cursor .. cursor + pubkey_mod.Pubkey.LENGTH][0..pubkey_mod.Pubkey.LENGTH].* };
                cursor += pubkey_mod.Pubkey.LENGTH;

                const writable_len = try shortvec.decode(bytes[cursor..]);
                cursor += writable_len.consumed;
                if (cursor + writable_len.value > bytes.len) return error.InvalidMessage;
                const writable_indexes = try allocator.dupe(u8, bytes[cursor .. cursor + writable_len.value]);
                cursor += writable_len.value;

                const readonly_len = try shortvec.decode(bytes[cursor..]);
                cursor += readonly_len.consumed;
                if (cursor + readonly_len.value > bytes.len) return error.InvalidMessage;
                const readonly_indexes = try allocator.dupe(u8, bytes[cursor .. cursor + readonly_len.value]);
                cursor += readonly_len.value;

                lookups[i] = .{
                    .account_key = account_key,
                    .writable_indexes = writable_indexes,
                    .readonly_indexes = readonly_indexes,
                };
            }
        }

        return .{
            .message = .{
                .allocator = allocator,
                .version = version,
                .header = header,
                .account_keys = account_keys,
                .recent_blockhash = recent_blockhash,
                .instructions = instructions,
                .address_table_lookups = lookups,
            },
            .consumed = cursor,
        };
    }
};

const AccountRole = struct {
    key: pubkey_mod.Pubkey,
    is_signer: bool,
    is_writable: bool,
};

const KeyIndex = struct {
    key: pubkey_mod.Pubkey,
    index: u8,
};

fn upsertRole(
    roles: *std.ArrayList(AccountRole),
    allocator: std.mem.Allocator,
    key: pubkey_mod.Pubkey,
    is_signer: bool,
    is_writable: bool,
) !void {
    for (roles.items) |*role| {
        if (!role.key.eql(key)) continue;
        role.is_signer = role.is_signer or is_signer;
        role.is_writable = role.is_writable or is_writable;
        return;
    }

    try roles.append(allocator, .{ .key = key, .is_signer = is_signer, .is_writable = is_writable });
}

fn appendRoleCategory(
    roles: []const AccountRole,
    list: *std.ArrayList(AccountRole),
    allocator: std.mem.Allocator,
    signer: bool,
    writable: bool,
) !void {
    for (roles) |role| {
        if (role.is_signer == signer and role.is_writable == writable) {
            try list.append(allocator, role);
        }
    }
}

fn orderRoles(allocator: std.mem.Allocator, roles: []const AccountRole) ![]AccountRole {
    var ordered: std.ArrayList(AccountRole) = .empty;
    defer ordered.deinit(allocator);

    try ordered.ensureTotalCapacity(allocator, roles.len);
    try appendRoleCategory(roles, &ordered, allocator, true, true);
    try appendRoleCategory(roles, &ordered, allocator, true, false);
    try appendRoleCategory(roles, &ordered, allocator, false, true);
    try appendRoleCategory(roles, &ordered, allocator, false, false);

    return try ordered.toOwnedSlice(allocator);
}

fn hasLookupKey(lookup_tables: []const lookup_mod.AddressLookupTable, key: pubkey_mod.Pubkey) bool {
    for (lookup_tables) |table| {
        for (table.writable) |entry| {
            if (entry.pubkey.eql(key)) return true;
        }
        for (table.readonly) |entry| {
            if (entry.pubkey.eql(key)) return true;
        }
    }

    return false;
}

fn instructionUsesKey(instructions: []const instruction_mod.Instruction, key: pubkey_mod.Pubkey) bool {
    for (instructions) |ix| {
        for (ix.accounts) |account| {
            if (account.pubkey.eql(key)) return true;
        }
    }
    return false;
}

fn findKeyIndex(indexes: []const KeyIndex, key: pubkey_mod.Pubkey) ?u8 {
    for (indexes) |entry| {
        if (entry.key.eql(key)) return entry.index;
    }

    return null;
}

fn containsStaticKeyIndex(indexes: []const KeyIndex, static_key_count: usize, key: pubkey_mod.Pubkey) bool {
    return findKeyIndex(indexes[0..static_key_count], key) != null;
}

fn containsDynamicKeyIndex(indexes: []const KeyIndex, static_key_count: usize, key: pubkey_mod.Pubkey) bool {
    return findKeyIndex(indexes[static_key_count..], key) != null;
}

test "compile and serialize legacy message" {
    const gpa = std.testing.allocator;

    const payer = pubkey_mod.Pubkey.init([_]u8{1} ** 32);
    const receiver = pubkey_mod.Pubkey.init([_]u8{2} ** 32);
    const program_id = pubkey_mod.Pubkey.init([_]u8{3} ** 32);
    const blockhash = hash_mod.Hash.init([_]u8{9} ** 32);

    const accounts = [_]instruction_mod.AccountMeta{
        .{ .pubkey = payer, .is_signer = true, .is_writable = true },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
    };

    const data = [_]u8{ 1, 2, 3, 4 };
    const ixs = [_]instruction_mod.Instruction{
        .{ .program_id = program_id, .accounts = &accounts, .data = &data },
    };

    var message = try Message.compileLegacy(gpa, payer, &ixs, blockhash);
    defer message.deinit();

    const encoded = try message.serialize(gpa);
    defer gpa.free(encoded);

    const decoded = try Message.deserialize(gpa, encoded);
    defer {
        var m = decoded.message;
        m.deinit();
    }

    try std.testing.expectEqual(MessageVersion.legacy, decoded.message.version);
    try std.testing.expectEqual(@as(usize, 1), decoded.message.instructions.len);
}

test "compile legacy with empty instruction data" {
    const gpa = std.testing.allocator;
    const payer = pubkey_mod.Pubkey.init([_]u8{4} ** 32);
    const program_id = pubkey_mod.Pubkey.init([_]u8{5} ** 32);
    const blockhash = hash_mod.Hash.init([_]u8{6} ** 32);

    const accounts = [_]instruction_mod.AccountMeta{
        .{ .pubkey = payer, .is_signer = true, .is_writable = true },
    };
    const ixs = [_]instruction_mod.Instruction{
        .{ .program_id = program_id, .accounts = &accounts, .data = &.{} },
    };

    var message = try Message.compileLegacy(gpa, payer, &ixs, blockhash);
    defer message.deinit();

    try std.testing.expectEqual(@as(usize, 1), message.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), message.instructions[0].data.len);
}

test "compile v0 skips lookup keys that are already static" {
    const gpa = std.testing.allocator;
    const payer = pubkey_mod.Pubkey.init([_]u8{7} ** 32);
    const receiver = pubkey_mod.Pubkey.init([_]u8{8} ** 32);
    const program_id = pubkey_mod.Pubkey.init([_]u8{9} ** 32);
    const blockhash = hash_mod.Hash.init([_]u8{1} ** 32);

    const accounts = [_]instruction_mod.AccountMeta{
        .{ .pubkey = payer, .is_signer = true, .is_writable = true },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
    };
    const ixs = [_]instruction_mod.Instruction{
        .{ .program_id = program_id, .accounts = &accounts, .data = &.{} },
    };

    const writable_entries = [_]lookup_mod.LookupEntry{
        .{ .index = 0, .pubkey = payer },
    };
    const lookups = [_]lookup_mod.AddressLookupTable{
        .{
            .account_key = pubkey_mod.Pubkey.init([_]u8{2} ** 32),
            .writable = &writable_entries,
            .readonly = &.{},
        },
    };

    var message = try Message.compileV0(gpa, payer, &ixs, blockhash, &lookups);
    defer message.deinit();

    try std.testing.expectEqual(@as(usize, 0), message.address_table_lookups.len);
}

test "compile v0 rejects duplicate dynamic lookup keys across tables" {
    const gpa = std.testing.allocator;
    const payer = pubkey_mod.Pubkey.init([_]u8{3} ** 32);
    const lookup_account = pubkey_mod.Pubkey.init([_]u8{4} ** 32);
    const program_id = pubkey_mod.Pubkey.init([_]u8{5} ** 32);
    const blockhash = hash_mod.Hash.init([_]u8{6} ** 32);

    const accounts = [_]instruction_mod.AccountMeta{
        .{ .pubkey = payer, .is_signer = true, .is_writable = true },
        .{ .pubkey = lookup_account, .is_signer = false, .is_writable = true },
    };
    const ixs = [_]instruction_mod.Instruction{
        .{ .program_id = program_id, .accounts = &accounts, .data = &.{} },
    };

    const table1_writable = [_]lookup_mod.LookupEntry{
        .{ .index = 0, .pubkey = lookup_account },
    };
    const table2_readonly = [_]lookup_mod.LookupEntry{
        .{ .index = 1, .pubkey = lookup_account },
    };
    const lookups = [_]lookup_mod.AddressLookupTable{
        .{
            .account_key = pubkey_mod.Pubkey.init([_]u8{10} ** 32),
            .writable = &table1_writable,
            .readonly = &.{},
        },
        .{
            .account_key = pubkey_mod.Pubkey.init([_]u8{11} ** 32),
            .writable = &.{},
            .readonly = &table2_readonly,
        },
    };

    try std.testing.expectError(
        error.DuplicateLookupKey,
        Message.compileV0(gpa, payer, &ixs, blockhash, &lookups),
    );
}
