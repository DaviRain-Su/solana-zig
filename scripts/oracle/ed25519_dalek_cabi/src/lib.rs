use ed25519_dalek::{SigningKey, VerifyingKey, Signature, Signer, Verifier};
use std::slice;

#[no_mangle]
pub extern "C" fn dalek_ed25519_sign(
    msg_ptr: *const u8,
    msg_len: usize,
    seed32: *const [u8; 32],
    out_sig: *mut [u8; 64],
) -> i32 {
    if msg_ptr.is_null() || seed32.is_null() || out_sig.is_null() {
        return -1;
    }
    let msg = unsafe { slice::from_raw_parts(msg_ptr, msg_len) };
    let signing_key = SigningKey::from_bytes(unsafe { &*seed32 });
    let sig = signing_key.sign(msg);
    unsafe { *out_sig = sig.to_bytes() };
    0
}

#[no_mangle]
pub extern "C" fn dalek_ed25519_verify(
    sig_ptr: *const [u8; 64],
    msg_ptr: *const u8,
    msg_len: usize,
    pk32: *const [u8; 32],
) -> i32 {
    if sig_ptr.is_null() || msg_ptr.is_null() || pk32.is_null() {
        return -1;
    }
    let msg = unsafe { slice::from_raw_parts(msg_ptr, msg_len) };
    let verifying_key = match VerifyingKey::from_bytes(unsafe { &*pk32 }) {
        Ok(k) => k,
        Err(_) => return -1,
    };
    let signature = Signature::from_bytes(unsafe { &*sig_ptr });
    match verifying_key.verify(msg, &signature) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}
