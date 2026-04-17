//! solana-program-zig root — on-chain SDK shared types and helpers

// Re-export shared core types (per D-02 boundary)
pub const pubkey = @import("pubkey");
pub const hash = @import("hash");
pub const signature = @import("signature");

// Placeholder: entrypoint will be expanded in #102
pub const entrypoint = @import("entrypoint.zig");
