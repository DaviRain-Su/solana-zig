const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    const host = b.graph.host;
    const can_run_target = target.result.os.tag == host.result.os.tag and target.result.cpu.arch == host.result.cpu.arch and target.result.abi == host.result.abi;
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // libsodium is optional but recommended for faster Ed25519 sign/verify.
    const enable_libsodium = b.option(bool, "enable-libsodium", "Link libsodium for faster Ed25519 (default: true)") orelse true;

    // ed25519-dalek staticlib provides the same backend as Rust's ed25519-dalek crate.
    // Default is false because the staticlib is not checked into the repo and must be
    // built manually from scripts/oracle/ed25519_dalek_cabi/.
    const enable_dalek = b.option(bool, "enable-dalek", "Link ed25519-dalek staticlib for Ed25519 (default: false)") orelse false;
    const dalek_staticlib_path = "scripts/oracle/ed25519_dalek_cabi/target/release/libed25519_dalek_cabi.a";

    // ring staticlib (based on BoringSSL) often outperforms dalek on aarch64.
    const enable_ring = b.option(bool, "enable-ring", "Link ring staticlib for Ed25519 (default: true)") orelse true;
    const ring_staticlib_path = "scripts/oracle/ed25519_ring_cabi/target/release/libed25519_ring_cabi.a";

    // Build-time config options exposed to Zig code via @import("config").
    const config_options = b.addOptions();
    config_options.addOption(bool, "enable_libsodium", enable_libsodium);
    config_options.addOption(bool, "enable_dalek", enable_dalek);
    config_options.addOption(bool, "enable_ring", enable_ring);

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("solana_zig", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
        .link_libc = true,
    });
    mod.addIncludePath(b.path("include"));
    mod.addOptions("config", config_options);
    if (enable_libsodium) {
        mod.linkSystemLibrary("sodium", .{});
        mod.addLibraryPath(std.Build.LazyPath{ .cwd_relative = "/opt/homebrew/lib" });
    }
    if (enable_dalek) {
        mod.addObjectFile(b.path(dalek_staticlib_path));
    }
    if (enable_ring) {
        mod.addObjectFile(b.path(ring_staticlib_path));
    }

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "solana_zig",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "solana_zig" is the name you will use in your source code to
                // import this module (e.g. `@import("solana_zig")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "solana_zig", .module = mod },
            },
        }),
    });
    exe.root_module.addIncludePath(b.path("include"));
    exe.root_module.addOptions("config", config_options);
    if (enable_libsodium) {
        exe.root_module.linkSystemLibrary("sodium", .{});
        exe.root_module.addLibraryPath(std.Build.LazyPath{ .cwd_relative = "/opt/homebrew/lib" });
    }
    if (enable_dalek) {
        exe.root_module.addObjectFile(b.path(dalek_staticlib_path));
    }
    if (enable_ring) {
        exe.root_module.addObjectFile(b.path(ring_staticlib_path));
    }

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the relative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    if (can_run_target) {
        test_step.dependOn(&run_mod_tests.step);
        test_step.dependOn(&run_exe_tests.step);
    } else {
        test_step.dependOn(&mod_tests.step);
        test_step.dependOn(&exe_tests.step);
    }

    // Surfpool E2E tests for Phase 1 closeout (docs/18)
    const e2e_mod = b.createModule(.{
        .root_source_file = b.path("src/e2e/surfpool.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "solana_zig", .module = mod },
        },
    });
    const e2e_tests = b.addTest(.{
        .root_module = e2e_mod,
    });
    const run_e2e_tests = b.addRunArtifact(e2e_tests);
    const e2e_step = b.step("e2e", "Run surfpool local E2E tests (requires SURFPOOL_RPC_URL)");
    e2e_step.dependOn(&run_e2e_tests.step);

    // Devnet E2E tests for Phase 1 closeout (docs/14)
    const devnet_e2e_mod = b.createModule(.{
        .root_source_file = b.path("src/e2e/devnet_e2e.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "solana_zig", .module = mod },
        },
    });
    const devnet_e2e_tests = b.addTest(.{
        .root_module = devnet_e2e_mod,
    });
    const run_devnet_e2e = b.addRunArtifact(devnet_e2e_tests);
    const devnet_e2e_step = b.step("devnet-e2e", "Run Devnet E2E tests (mock always; live RPC when SOLANA_RPC_URL is set; live websocket when SOLANA_RPC_URL and SOLANA_WS_URL are set)");
    devnet_e2e_step.dependOn(&run_devnet_e2e.step);

    // Nonce E2E tests for Phase 2 Batch 3 (#34 P2-14)
    const nonce_e2e_mod = b.createModule(.{
        .root_source_file = b.path("src/e2e/nonce_e2e.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "solana_zig", .module = mod },
        },
    });
    const nonce_e2e_tests = b.addTest(.{
        .root_module = nonce_e2e_mod,
    });
    const run_nonce_e2e = b.addRunArtifact(nonce_e2e_tests);
    const nonce_e2e_step = b.step("nonce-e2e", "Run Nonce E2E tests (mock always; live when SOLANA_RPC_URL set)");
    nonce_e2e_step.dependOn(&run_nonce_e2e.step);

    // Benchmark executable for Phase 1 baseline (docs/13)
    const bench_exe = b.addExecutable(.{
        .name = "benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/benchmark.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .link_libc = true,
        }),
    });
    bench_exe.root_module.addOptions("config", config_options);
    if (enable_libsodium) {
        bench_exe.root_module.linkSystemLibrary("sodium", .{});
        bench_exe.root_module.addLibraryPath(std.Build.LazyPath{ .cwd_relative = "/opt/homebrew/lib" });
    }
    if (enable_dalek) {
        bench_exe.root_module.addObjectFile(b.path(dalek_staticlib_path));
    }
    if (enable_ring) {
        bench_exe.root_module.addObjectFile(b.path(ring_staticlib_path));
    }
    b.installArtifact(bench_exe);

    const bench_run = b.addRunArtifact(bench_exe);
    bench_run.step.dependOn(b.getInstallStep());
    const bench_step = b.step("bench", "Run Phase 1 benchmark baseline");
    bench_step.dependOn(&bench_run.step);

    // C ABI header compile check (docs/03d-cabi-spec.md)
    const cabi_header_check = b.addExecutable(.{
        .name = "cabi_header_check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("scripts/check_cabi_header.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    cabi_header_check.root_module.addIncludePath(b.path("include"));
    const run_cabi_header_check = b.addRunArtifact(cabi_header_check);
    const cabi_check_step = b.step("cabi-check", "Compile C ABI header check");
    cabi_check_step.dependOn(&run_cabi_header_check.step);

    // Core freestanding compile check (ADR-0002)
    const freestanding_target = b.resolveTargetQuery(.{
        .cpu_arch = .bpfel,
        .os_tag = .freestanding,
    });
    const freestanding_check = b.addObject(.{
        .name = "freestanding_check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/solana/core/pubkey.zig"),
            .target = freestanding_target,
            .optimize = .ReleaseSmall,
        }),
    });
    const freestanding_step = b.step("freestanding-check", "Compile core types for bpfel-freestanding");
    freestanding_step.dependOn(&freestanding_check.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
