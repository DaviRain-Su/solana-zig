const std = @import("std");
const tx = @import("../tx/instruction.zig");
const pubkey_mod = @import("../core/pubkey.zig");

/// ComputeBudget program ID: ComputeBudget111111111111111111111111111111
pub const program_id = pubkey_mod.Pubkey.init(.{
    3, 6, 70, 111, 229, 33, 23, 50,
    255, 236, 173, 186, 114, 195, 155, 231,
    188, 140, 229, 187, 197, 247, 18, 107,
    44, 67, 155, 58, 64, 0, 0, 0,
});

/// Instruction discriminants matching the Rust SDK's ComputeBudgetInstruction enum.
const Discriminant = enum(u8) {
    set_compute_unit_limit = 0x02,
    set_compute_unit_price = 0x03,
};

pub const ComputeBudgetError = error{
    InvalidInstructionParams,
};

/// Build a SetComputeUnitLimit instruction.
///
/// Sets the maximum number of compute units the transaction is allowed to consume.
/// Data layout: [0x02] ++ little-endian u32 (5 bytes total).
/// Accounts: none.
pub fn buildSetComputeUnitLimitInstruction(
    allocator: std.mem.Allocator,
    units: u32,
) (std.mem.Allocator.Error || ComputeBudgetError)!tx.Instruction {
    const data = try allocator.alloc(u8, 5);
    data[0] = @intFromEnum(Discriminant.set_compute_unit_limit);
    std.mem.writeInt(u32, data[1..5], units, .little);

    return tx.Instruction{
        .program_id = program_id,
        .accounts = &.{},
        .data = data,
    };
}

/// Build a SetComputeUnitPrice instruction.
///
/// Sets the priority fee rate in micro-lamports per compute unit.
/// Data layout: [0x03] ++ little-endian u64 (9 bytes total).
/// Accounts: none.
pub fn buildSetComputeUnitPriceInstruction(
    allocator: std.mem.Allocator,
    micro_lamports: u64,
) (std.mem.Allocator.Error || ComputeBudgetError)!tx.Instruction {
    const data = try allocator.alloc(u8, 9);
    data[0] = @intFromEnum(Discriminant.set_compute_unit_price);
    std.mem.writeInt(u64, data[1..9], micro_lamports, .little);

    return tx.Instruction{
        .program_id = program_id,
        .accounts = &.{},
        .data = data,
    };
}

/// Returns the ComputeBudget program ID.
pub fn programId() pubkey_mod.Pubkey {
    return program_id;
}

// ─── Tests ───────────────────────────────────────────────────────────────────

test "programId returns ComputeBudget111111111111111111111111111111" {
    const allocator = std.testing.allocator;
    const id = programId();
    const expected = "ComputeBudget111111111111111111111111111111";
    const actual = try id.toBase58Alloc(allocator);
    defer allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

test "setComputeUnitLimit — happy path byte layout" {
    const allocator = std.testing.allocator;
    const ix = try buildSetComputeUnitLimitInstruction(allocator, 200_000);
    defer allocator.free(ix.data);

    // discriminant 0x02
    try std.testing.expectEqual(@as(u8, 0x02), ix.data[0]);
    // 200_000 = 0x00030D40 LE => 0x40, 0x0D, 0x03, 0x00
    try std.testing.expectEqual(@as(u8, 0x40), ix.data[1]);
    try std.testing.expectEqual(@as(u8, 0x0D), ix.data[2]);
    try std.testing.expectEqual(@as(u8, 0x03), ix.data[3]);
    try std.testing.expectEqual(@as(u8, 0x00), ix.data[4]);
    // total length
    try std.testing.expectEqual(@as(usize, 5), ix.data.len);
    // no accounts
    try std.testing.expectEqual(@as(usize, 0), ix.accounts.len);
    // program id
    try std.testing.expect(std.mem.eql(u8, &ix.program_id.bytes, &program_id.bytes));
}

test "setComputeUnitLimit — boundary: zero" {
    const allocator = std.testing.allocator;
    const ix = try buildSetComputeUnitLimitInstruction(allocator, 0);
    defer allocator.free(ix.data);

    try std.testing.expectEqual(@as(u8, 0x02), ix.data[0]);
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, ix.data[1..5], .little));
}

test "setComputeUnitLimit — boundary: max u32" {
    const allocator = std.testing.allocator;
    const ix = try buildSetComputeUnitLimitInstruction(allocator, std.math.maxInt(u32));
    defer allocator.free(ix.data);

    try std.testing.expectEqual(@as(u8, 0x02), ix.data[0]);
    try std.testing.expectEqual(std.math.maxInt(u32), std.mem.readInt(u32, ix.data[1..5], .little));
}

test "setComputeUnitPrice — happy path byte layout" {
    const allocator = std.testing.allocator;
    const ix = try buildSetComputeUnitPriceInstruction(allocator, 1_000);
    defer allocator.free(ix.data);

    // discriminant 0x03
    try std.testing.expectEqual(@as(u8, 0x03), ix.data[0]);
    // 1000 = 0x03E8 LE => 0xE8, 0x03, 0x00...
    try std.testing.expectEqual(@as(u8, 0xE8), ix.data[1]);
    try std.testing.expectEqual(@as(u8, 0x03), ix.data[2]);
    var i: usize = 3;
    while (i < 9) : (i += 1) {
        try std.testing.expectEqual(@as(u8, 0x00), ix.data[i]);
    }
    // total length
    try std.testing.expectEqual(@as(usize, 9), ix.data.len);
    // no accounts
    try std.testing.expectEqual(@as(usize, 0), ix.accounts.len);
    // program id
    try std.testing.expect(std.mem.eql(u8, &ix.program_id.bytes, &program_id.bytes));
}

test "setComputeUnitPrice — boundary: zero" {
    const allocator = std.testing.allocator;
    const ix = try buildSetComputeUnitPriceInstruction(allocator, 0);
    defer allocator.free(ix.data);

    try std.testing.expectEqual(@as(u8, 0x03), ix.data[0]);
    try std.testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, ix.data[1..9], .little));
}

test "setComputeUnitPrice — boundary: max u64" {
    const allocator = std.testing.allocator;
    const ix = try buildSetComputeUnitPriceInstruction(allocator, std.math.maxInt(u64));
    defer allocator.free(ix.data);

    try std.testing.expectEqual(@as(u8, 0x03), ix.data[0]);
    try std.testing.expectEqual(std.math.maxInt(u64), std.mem.readInt(u64, ix.data[1..9], .little));
}

test "setComputeUnitPrice — Rust reference: 50_000 micro-lamports" {
    const allocator = std.testing.allocator;
    // Rust SDK: ComputeBudgetInstruction::SetComputeUnitPrice(50_000)
    // Expected bytes: [0x03, 0x50, 0xC3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    const ix = try buildSetComputeUnitPriceInstruction(allocator, 50_000);
    defer allocator.free(ix.data);

    const expected = [_]u8{ 0x03, 0x50, 0xC3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    try std.testing.expectEqualSlices(u8, &expected, ix.data);
}

test "setComputeUnitLimit — Rust reference: 400_000 units" {
    const allocator = std.testing.allocator;
    // Rust SDK: ComputeBudgetInstruction::SetComputeUnitLimit(400_000)
    // 400_000 = 0x61A80 => LE: [0x80, 0x1A, 0x06, 0x00]
    // Expected bytes: [0x02, 0x80, 0x1A, 0x06, 0x00]
    const ix = try buildSetComputeUnitLimitInstruction(allocator, 400_000);
    defer allocator.free(ix.data);

    const expected = [_]u8{ 0x02, 0x80, 0x1A, 0x06, 0x00 };
    try std.testing.expectEqualSlices(u8, &expected, ix.data);
}
