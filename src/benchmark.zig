// Phase 1 Benchmark Baseline Harness
// Spec: docs/13-benchmark-baseline-spec.md
//
// Measures: base58, shortvec, legacy/v0 message, versioned transaction,
//           sign/verify operations.
//
// Build & run: zig build bench

const std = @import("std");
const solana = @import("solana/mod.zig");

const base58 = solana.core.base58;
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

fn printResult(comptime name: []const u8, iters: usize, elapsed_ns: u64) void {
    const avg_ns = elapsed_ns / iters;
    std.debug.print("{s}: {d} iters, avg {d} ns/op, total {d} us\n", .{
        name,
        iters,
        avg_ns,
        elapsed_ns / 1000,
    });
}

// --- Main ---

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const payer = try Keypair.fromSeed(SEED_BYTES);

    std.debug.print("=== solana-zig Phase 1 Benchmark Baseline ===\n", .{});
    std.debug.print("iterations: {d} (warmup: {d})\n", .{ BENCH_ITERS, WARMUP_ITERS });
    std.debug.print("optimize: ReleaseFast (expected)\n", .{});
    std.debug.print("\n", .{});

    // --- base58 encode ---
    std.debug.print("--- base58 ---\n", .{});
    {
        for (0..WARMUP_ITERS) |_| {
            const e = base58.encodeAlloc(allocator, &PUBKEY_BYTES) catch continue;
            allocator.free(e);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const e = base58.encodeAlloc(allocator, &PUBKEY_BYTES) catch continue;
            allocator.free(e);
        }
        printResult("base58_encode", BENCH_ITERS, nowNs() - start);
    }

    // --- base58 decode ---
    {
        const encoded = try base58.encodeAlloc(allocator, &PUBKEY_BYTES);
        defer allocator.free(encoded);

        for (0..WARMUP_ITERS) |_| {
            const d = base58.decodeAlloc(allocator, encoded) catch continue;
            allocator.free(d);
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            const d = base58.decodeAlloc(allocator, encoded) catch continue;
            allocator.free(d);
        }
        printResult("base58_decode", BENCH_ITERS, nowNs() - start);
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
        printResult("shortvec_encode", BENCH_ITERS, nowNs() - start);
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
        printResult("shortvec_decode", BENCH_ITERS, nowNs() - start);
    }

    // --- legacy message ---
    std.debug.print("\n--- legacy message ---\n", .{});
    {
        for (0..WARMUP_ITERS) |_| {
            var m = buildLegacyMessage(allocator, payer) catch continue;
            const s = m.serialize(allocator) catch {
                m.deinit();
                continue;
            };
            allocator.free(s);
            m.deinit();
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            var m = buildLegacyMessage(allocator, payer) catch continue;
            const s = m.serialize(allocator) catch {
                m.deinit();
                continue;
            };
            allocator.free(s);
            m.deinit();
        }
        printResult("legacy_msg_compile_serialize", BENCH_ITERS, nowNs() - start);
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
        printResult("legacy_msg_deserialize", BENCH_ITERS, nowNs() - start);
    }

    // --- v0 message ---
    std.debug.print("\n--- v0 message ---\n", .{});
    {
        for (0..WARMUP_ITERS) |_| {
            var m = buildV0Message(allocator, payer) catch continue;
            const s = m.serialize(allocator) catch {
                m.deinit();
                continue;
            };
            allocator.free(s);
            m.deinit();
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            var m = buildV0Message(allocator, payer) catch continue;
            const s = m.serialize(allocator) catch {
                m.deinit();
                continue;
            };
            allocator.free(s);
            m.deinit();
        }
        printResult("v0_msg_compile_serialize", BENCH_ITERS, nowNs() - start);
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
        printResult("v0_msg_deserialize", BENCH_ITERS, nowNs() - start);
    }

    // --- versioned transaction ---
    std.debug.print("\n--- versioned transaction ---\n", .{});
    {
        for (0..WARMUP_ITERS) |_| {
            var m = buildLegacyMessage(allocator, payer) catch continue;
            var tx = VersionedTransaction.initUnsigned(allocator, m) catch {
                m.deinit();
                continue;
            };
            tx.sign(&[_]Keypair{payer}) catch {
                tx.deinit();
                continue;
            };
            const s = tx.serialize(allocator) catch {
                tx.deinit();
                continue;
            };
            allocator.free(s);
            tx.deinit();
        }
        const start = nowNs();
        for (0..BENCH_ITERS) |_| {
            var m = buildLegacyMessage(allocator, payer) catch continue;
            var tx = VersionedTransaction.initUnsigned(allocator, m) catch {
                m.deinit();
                continue;
            };
            tx.sign(&[_]Keypair{payer}) catch {
                tx.deinit();
                continue;
            };
            const s = tx.serialize(allocator) catch {
                tx.deinit();
                continue;
            };
            allocator.free(s);
            tx.deinit();
        }
        printResult("tx_compile_sign_serialize", BENCH_ITERS, nowNs() - start);
    }
    {
        const setup_msg = try buildLegacyMessage(allocator, payer);
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
        printResult("tx_deserialize", BENCH_ITERS, nowNs() - start);
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
        printResult("ed25519_sign", BENCH_ITERS, nowNs() - start);
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
        printResult("ed25519_verify", BENCH_ITERS, nowNs() - start);
    }

    std.debug.print("\n=== benchmark complete ===\n", .{});
}
