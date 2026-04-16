// Phase 1 Benchmark Baseline Harness
// Spec: docs/13-benchmark-baseline-spec.md
//
// Measures: Pubkey base58 encode/decode, shortvec encode/decode,
//           legacy/v0 message serialize/deserialize,
//           versioned transaction serialize/deserialize,
//           sign/verify operations.
//
// Build & run: zig build bench

const builtin = @import("builtin");
const std = @import("std");
const solana = @import("solana/mod.zig");

const shortvec = solana.core.shortvec;
const Pubkey = solana.core.Pubkey;
const Hash = solana.core.Hash;
const Keypair = solana.core.Keypair;
const Instruction = solana.tx.Instruction;
const AccountMeta = solana.tx.AccountMeta;
const Message = solana.tx.Message;
const VersionedTransaction = solana.tx.VersionedTransaction;
const AddressLookupTable = solana.tx.AddressLookupTable;
const LookupEntry = solana.tx.address_lookup_table.LookupEntry;

// --- Configuration ---

const WARMUP_ITERS: usize = 100;
const BENCH_ITERS: usize = 10_000;

const PROFILE_SMALL = "small";
const PROFILE_PHASE1_REALISTIC = "phase1-realistic";

// --- Timing ---

fn nowNs() u64 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts) != 0) unreachable;
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

// --- Input Fixtures ---

const PUBKEY_BYTES = [_]u8{0x0A} ** 32;
const HASH_BYTES = [_]u8{0x05} ** 32;
const SEED_BYTES = [_]u8{0x08} ** 32;

// --- Message / Transaction Helpers ---

fn buildLegacyMessage(allocator: std.mem.Allocator, payer: Keypair) !Message {
    const receiver = Pubkey.init([_]u8{0x07} ** 32);
    const program = Pubkey.init([_]u8{0x06} ** 32);
    const blockhash = Hash.init(HASH_BYTES);

    const accounts = [_]AccountMeta{
        .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
    };
    const payload = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const ixs = [_]Instruction{
        .{ .program_id = program, .accounts = &accounts, .data = &payload },
    };

    return try Message.compileLegacy(allocator, payer.pubkey(), &ixs, blockhash);
}

fn buildV0Message(allocator: std.mem.Allocator, payer: Keypair) !Message {
    const receiver = Pubkey.init([_]u8{0x07} ** 32);
    const program = Pubkey.init([_]u8{0x06} ** 32);
    const lookup_key1 = Pubkey.init([_]u8{0x0B} ** 32);
    const lookup_account = Pubkey.init([_]u8{0x0C} ** 32);
    const blockhash = Hash.init(HASH_BYTES);

    const accounts = [_]AccountMeta{
        .{ .pubkey = payer.pubkey(), .is_signer = true, .is_writable = true },
        .{ .pubkey = receiver, .is_signer = false, .is_writable = true },
        .{ .pubkey = lookup_account, .is_signer = false, .is_writable = false },
    };
    const payload = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const ixs = [_]Instruction{
        .{ .program_id = program, .accounts = &accounts, .data = &payload },
    };

    const writable_entries = [_]LookupEntry{
        .{ .index = 0, .pubkey = receiver },
    };
    const readonly_entries = [_]LookupEntry{
        .{ .index = 1, .pubkey = lookup_account },
    };
    const lookup_tables = [_]AddressLookupTable{
        .{
            .account_key = lookup_key1,
            .writable = &writable_entries,
            .readonly = &readonly_entries,
        },
    };

    return try Message.compileV0(allocator, payer.pubkey(), &ixs, blockhash, &lookup_tables);
}

// --- Benchmark Runner ---

fn printResult(comptime name: []const u8, comptime profile: []const u8, iters: usize, elapsed_ns: u64) void {
    const safe_elapsed_ns = if (elapsed_ns == 0) 1 else elapsed_ns;
    const avg_ns = safe_elapsed_ns / iters;
    const ops_per_sec: u64 = @intCast((@as(u128, iters) * std.time.ns_per_s) / safe_elapsed_ns);
    std.debug.print("BENCH|{s}|{s}|{d}|{d}|{d}|{d}\n", .{
        name,
        profile,
        iters,
        safe_elapsed_ns / std.time.ns_per_us,
        avg_ns,
        ops_per_sec,
    });
}

// --- Main ---

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const payer = try Keypair.fromSeed(SEED_BYTES);
    const benchmark_target = comptime std.fmt.comptimePrint("{s}-{s}", .{
        @tagName(builtin.target.cpu.arch),
        @tagName(builtin.target.os.tag),
    });
    const pubkey = Pubkey.init(PUBKEY_BYTES);

    std.debug.print("=== solana-zig Phase 1 Benchmark Baseline ===\n", .{});
    std.debug.print("iterations: {d} (warmup: {d})\n", .{ BENCH_ITERS, WARMUP_ITERS });
    std.debug.print("target: {s}\n", .{benchmark_target});
    std.debug.print("zig: {d}.{d}.{d}\n", .{
        builtin.zig_version.major,
        builtin.zig_version.minor,
        builtin.zig_version.patch,
    });
    std.debug.print("optimize: ReleaseFast\n", .{});
    std.debug.print("columns: BENCH|op|profile|iters|total_us|ns_op|ops_sec\n", .{});
    std.debug.print("\n", .{});

    // --- Pubkey base58 encode/decode ---
    std.debug.print("--- pubkey base58 ---\n", .{});
    {
        for (0..WARMUP_ITERS) |_| {
            const e = pubkey.toBase58Alloc(allocator) catch continue;
            allocator.free(e);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const e = pubkey.toBase58Alloc(allocator) catch continue;
            allocator.free(e);
        }
        printResult("pubkey_base58_encode", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }

    {
        const encoded = try pubkey.toBase58Alloc(allocator);
        defer allocator.free(encoded);

        for (0..WARMUP_ITERS) |_| {
            var d = Pubkey.fromBase58(encoded) catch continue;
            std.mem.doNotOptimizeAway(&d);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            var d = Pubkey.fromBase58(encoded) catch continue;
            std.mem.doNotOptimizeAway(&d);
        }
        printResult("pubkey_base58_decode", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }

    // --- shortvec ---
    std.debug.print("\n--- shortvec ---\n", .{});
    {
        for (0..WARMUP_ITERS) |_| {
            const e = shortvec.encodeAlloc(allocator, 12345) catch continue;
            allocator.free(e);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const e = shortvec.encodeAlloc(allocator, 12345) catch continue;
            allocator.free(e);
        }
        printResult("shortvec_encode", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }
    {
        const input = [_]u8{ 0xB9, 0x60 };
        for (0..WARMUP_ITERS) |_| {
            const r = shortvec.decode(&input) catch continue;
            std.mem.doNotOptimizeAway(&r);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const r = shortvec.decode(&input) catch continue;
            std.mem.doNotOptimizeAway(&r);
        }
        printResult("shortvec_decode", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }

    // --- legacy message ---
    std.debug.print("\n--- legacy message ---\n", .{});
    {
        var message = try buildLegacyMessage(allocator, payer);
        defer message.deinit();

        for (0..WARMUP_ITERS) |_| {
            const s = message.serialize(allocator) catch continue;
            allocator.free(s);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const s = message.serialize(allocator) catch continue;
            allocator.free(s);
        }
        printResult("legacy_message_serialize", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }
    {
        var setup_msg = try buildLegacyMessage(allocator, payer);
        const serialized = try setup_msg.serialize(allocator);
        setup_msg.deinit();
        defer allocator.free(serialized);

        for (0..WARMUP_ITERS) |_| {
            var d = Message.deserialize(allocator, serialized) catch continue;
            d.message.deinit();
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            var d = Message.deserialize(allocator, serialized) catch continue;
            d.message.deinit();
        }
        printResult("legacy_message_deserialize", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }

    // --- v0 message ---
    std.debug.print("\n--- v0 message ---\n", .{});
    {
        var message = try buildV0Message(allocator, payer);
        defer message.deinit();

        for (0..WARMUP_ITERS) |_| {
            const s = message.serialize(allocator) catch continue;
            allocator.free(s);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const s = message.serialize(allocator) catch continue;
            allocator.free(s);
        }
        printResult("v0_message_serialize", PROFILE_PHASE1_REALISTIC, BENCH_ITERS, nowNs() - start);
    }
    {
        var setup_msg = try buildV0Message(allocator, payer);
        const serialized = try setup_msg.serialize(allocator);
        setup_msg.deinit();
        defer allocator.free(serialized);

        for (0..WARMUP_ITERS) |_| {
            var d = Message.deserialize(allocator, serialized) catch continue;
            d.message.deinit();
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            var d = Message.deserialize(allocator, serialized) catch continue;
            d.message.deinit();
        }
        printResult("v0_message_deserialize", PROFILE_PHASE1_REALISTIC, BENCH_ITERS, nowNs() - start);
    }

    // --- versioned transaction ---
    std.debug.print("\n--- versioned transaction ---\n", .{});
    {
        const setup_msg = try buildV0Message(allocator, payer);
        var tx = try VersionedTransaction.initUnsigned(allocator, setup_msg);
        defer tx.deinit();
        try tx.sign(&[_]Keypair{payer});

        for (0..WARMUP_ITERS) |_| {
            const s = tx.serialize(allocator) catch continue;
            allocator.free(s);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const s = tx.serialize(allocator) catch continue;
            allocator.free(s);
        }
        printResult("transaction_serialize", PROFILE_PHASE1_REALISTIC, BENCH_ITERS, nowNs() - start);
    }
    {
        const setup_msg = try buildV0Message(allocator, payer);
        var tx = try VersionedTransaction.initUnsigned(allocator, setup_msg);
        try tx.sign(&[_]Keypair{payer});
        const serialized = try tx.serialize(allocator);
        tx.deinit();
        defer allocator.free(serialized);

        for (0..WARMUP_ITERS) |_| {
            var d = VersionedTransaction.deserialize(allocator, serialized) catch continue;
            d.deinit();
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            var d = VersionedTransaction.deserialize(allocator, serialized) catch continue;
            d.deinit();
        }
        printResult("transaction_deserialize", PROFILE_PHASE1_REALISTIC, BENCH_ITERS, nowNs() - start);
    }

    // --- sign / verify ---
    std.debug.print("\n--- sign / verify ---\n", .{});
    {
        var sign_msg = try buildLegacyMessage(allocator, payer);
        const msg_bytes = try sign_msg.serialize(allocator);
        sign_msg.deinit();
        defer allocator.free(msg_bytes);

        for (0..WARMUP_ITERS) |_| {
            const sig = payer.sign(msg_bytes) catch continue;
            std.mem.doNotOptimizeAway(&sig);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const sig = payer.sign(msg_bytes) catch continue;
            std.mem.doNotOptimizeAway(&sig);
        }
        printResult("ed25519_sign", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }
    {
        var verify_msg = try buildLegacyMessage(allocator, payer);
        const verify_bytes = try verify_msg.serialize(allocator);
        verify_msg.deinit();
        defer allocator.free(verify_bytes);

        const sig = try payer.sign(verify_bytes);

        for (0..WARMUP_ITERS) |_| {
            sig.verify(verify_bytes, payer.pubkey()) catch {};
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            sig.verify(verify_bytes, payer.pubkey()) catch {};
        }
        printResult("ed25519_verify", PROFILE_SMALL, BENCH_ITERS, nowNs() - start);
    }

    std.debug.print("\n=== benchmark complete ===\n", .{});
}
