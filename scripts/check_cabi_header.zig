// Zig wrapper to compile-check solana_zig.h C ABI surface.
// Build: zig build cabi-check

const c = @cImport({
    @cInclude("solana_zig.h");
});

// Forward-declare an external so the linker does not require the actual archive.
extern fn solana_zig_abi_version() c_int;

pub fn main() void {
    const pk: c.SolanaPubkey = undefined;
    const h: c.SolanaHash = undefined;
    const sig: c.SolanaSignature = undefined;
    var rpc: ?*c.SolanaRpcClientHandle = null;
    var ix: ?*c.SolanaInstruction = null;
    var msg: ?*c.SolanaMessage = null;
    var tx: ?*c.SolanaTransaction = null;

    _ = solana_zig_abi_version;
    _ = @sizeOf(@TypeOf(pk));
    _ = @sizeOf(@TypeOf(h));
    _ = @sizeOf(@TypeOf(sig));
    _ = @intFromPtr(&rpc);
    _ = @intFromPtr(&ix);
    _ = @intFromPtr(&msg);
    _ = @intFromPtr(&tx);
}
