const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = .ReleaseSmall;

    // Shared core type modules (per D-02 boundary)
    // These are the only allowed imports from the off-chain SDK
    const pubkey_mod = b.createModule(.{
        .root_source_file = b.path("../../src/solana/core/pubkey.zig"),
    });
    const hash_mod = b.createModule(.{
        .root_source_file = b.path("../../src/solana/core/hash.zig"),
    });
    const signature_mod = b.createModule(.{
        .root_source_file = b.path("../../src/solana/core/signature.zig"),
    });

    // Example to build (hello-world for G-P4B smoke)
    const example_path = "examples/hello/lib.zig";
    const bitcode_path = "entrypoint.bc";
    const program_so_path = "zig-out/lib/program_name.so";

    // Step 1: Generate LLVM bitcode using zig build-lib
    const gen_bitcode = b.addSystemCommand(&.{
        "zig",
        "build-lib",
        "-target",
        "bpfel-freestanding",
        "-O",
        "ReleaseSmall",
        "-femit-llvm-bc=" ++ bitcode_path,
        "-fno-emit-bin",
        "--dep", "solana_program",
        "--dep", "pubkey",
        "--dep", "hash",
        "--dep", "signature",
        b.fmt("-Mroot={s}", .{example_path}),
        "-Msolana_program=src/root.zig",
        "-Mpubkey=../../src/solana/core/pubkey.zig",
        "-Mhash=../../src/solana/core/hash.zig",
        "-Msignature=../../src/solana/core/signature.zig",
    });

    // Step 2: Link with sbpf-linker
    const link_program = b.addSystemCommand(&.{
        "sbpf-linker",
        "--cpu", "v2",
        "--llvm-args=-bpf-stack-size=4096",
        "--export", "entrypoint",
        "-o", program_so_path,
        bitcode_path,
    });
    link_program.step.dependOn(&gen_bitcode.step);

    // Default install step depends on linking
    b.getInstallStep().dependOn(&link_program.step);

    // Host unit tests (run on native target, not BPF)
    const test_step = b.step("test", "Run unit tests");
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pubkey", .module = pubkey_mod },
            .{ .name = "hash", .module = hash_mod },
            .{ .name = "signature", .module = signature_mod },
        },
    });
    const lib_unit_tests = b.addTest(.{
        .root_module = test_module,
    });
    const run_unit_tests = b.addRunArtifact(lib_unit_tests);
    test_step.dependOn(&run_unit_tests.step);
}
