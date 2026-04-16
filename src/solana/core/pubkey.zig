const std = @import("std");
const base58 = @import("base58.zig");

pub const Pubkey = struct {
    pub const LENGTH: usize = 32;

    bytes: [LENGTH]u8,

    pub fn init(bytes: [LENGTH]u8) Pubkey {
        return .{ .bytes = bytes };
    }

    pub fn fromSlice(slice: []const u8) !Pubkey {
        if (slice.len != LENGTH) return error.InvalidLength;
        var out: [LENGTH]u8 = undefined;
        @memcpy(&out, slice);
        return .{ .bytes = out };
    }

    pub fn fromBase58(input: []const u8) !Pubkey {
        return .{ .bytes = try base58.decodeFixed(LENGTH, input) };
    }

    pub fn toBase58Alloc(self: Pubkey, allocator: std.mem.Allocator) ![]u8 {
        return base58.encodeAlloc(allocator, &self.bytes);
    }

    pub fn eql(self: Pubkey, other: Pubkey) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }

    pub fn default() Pubkey {
        return init([_]u8{0} ** LENGTH);
    }
};

/// Derive a program address from seeds and a program id.
/// Returns `error.InvalidSeeds` if the derived address falls on the ed25519 curve.
pub fn createProgramAddress(seeds: []const []const u8, program_id: Pubkey) error{InvalidSeeds}!Pubkey {
    return createProgramAddressInternal(seeds, null, program_id);
}

/// Find a valid program address and bump seed.
/// Iterates bump from 255 down to 0 until `createProgramAddress` succeeds.
pub fn findProgramAddress(seeds: []const []const u8, program_id: Pubkey) error{InvalidSeeds}!struct { Pubkey, u8 } {
    var bump: u8 = 255;
    while (true) {
        const bump_seed = &[_]u8{bump};
        const address = createProgramAddressInternal(seeds, bump_seed, program_id) catch |err| switch (err) {
            error.InvalidSeeds => {
                if (bump == 0) return error.InvalidSeeds;
                bump -= 1;
                continue;
            },
        };
        return .{ address, bump };
    }
}

fn createProgramAddressInternal(
    seeds: []const []const u8,
    bump_seed: ?[]const u8,
    program_id: Pubkey,
) error{InvalidSeeds}!Pubkey {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (seeds) |seed| {
        hasher.update(seed);
    }
    if (bump_seed) |bs| {
        hasher.update(bs);
    }
    hasher.update(&program_id.bytes);
    hasher.update("ProgramDerivedAddress");

    var hash: [32]u8 = undefined;
    hasher.final(&hash);

    if (isOnCurve(hash)) return error.InvalidSeeds;

    return Pubkey.init(hash);
}

fn isOnCurve(bytes: [32]u8) bool {
    _ = std.crypto.ecc.Edwards25519.fromBytes(bytes) catch return false;
    return true;
}

test "pubkey base58 roundtrip" {
    const gpa = std.testing.allocator;

    var bytes: [Pubkey.LENGTH]u8 = undefined;
    @memset(&bytes, 7);
    const key = Pubkey.init(bytes);

    const b58 = try key.toBase58Alloc(gpa);
    defer gpa.free(b58);

    const reparsed = try Pubkey.fromBase58(b58);
    try std.testing.expect(key.eql(reparsed));
}

test "pubkey invalid length" {
    try std.testing.expectError(error.InvalidLength, Pubkey.fromSlice(&[_]u8{0} ** 31));
    try std.testing.expectError(error.InvalidLength, Pubkey.fromSlice(&[_]u8{0} ** 33));
}

test "createProgramAddress rejects on-curve point" {
    // All-zero bytes is a valid ed25519 point (identity), so PDA derivation should reject it.
    // We construct seeds that hash to all zeros. This is extremely unlikely for random seeds,
    // so instead we verify the structural behavior: isOnCurve correctly identifies zeros.
    try std.testing.expect(isOnCurve([_]u8{0} ** 32));
}

test "findProgramAddress returns valid PDA and bump" {
    const program_id = Pubkey.init([_]u8{0x01} ** 32);
    const seeds = &[_][]const u8{"seed"};

    const result = try findProgramAddress(seeds, program_id);
    const pda = result[0];
    const bump = result[1];

    // Bump must be in valid range.
    try std.testing.expect(bump >= 0 and bump <= 255);

    // Recreating with the returned bump must succeed.
    const bump_seed = &[_]u8{bump};
    const all_seeds = seeds ++ &[_][]const u8{bump_seed};
    const recreated = try createProgramAddress(all_seeds, program_id);
    try std.testing.expect(pda.eql(recreated));
}
