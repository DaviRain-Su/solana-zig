use ring::signature::{Ed25519KeyPair, UnparsedPublicKey, ED25519};
use std::slice;

pub struct RingKeypair {
    inner: Ed25519KeyPair,
}

#[no_mangle]
pub extern "C" fn ring_ed25519_keypair_new(seed32: *const [u8; 32]) -> *mut RingKeypair {
    if seed32.is_null() {
        return std::ptr::null_mut();
    }
    let seed = unsafe { &*seed32 };
    let kp = match Ed25519KeyPair::from_seed_unchecked(seed) {
        Ok(kp) => kp,
        Err(_) => return std::ptr::null_mut(),
    };
    Box::into_raw(Box::new(RingKeypair { inner: kp }))
}

#[no_mangle]
pub extern "C" fn ring_ed25519_keypair_sign(
    kp: *const RingKeypair,
    msg_ptr: *const u8,
    msg_len: usize,
    out_sig: *mut [u8; 64],
) -> i32 {
    if kp.is_null() || msg_ptr.is_null() || out_sig.is_null() {
        return -1;
    }
    let msg = unsafe { slice::from_raw_parts(msg_ptr, msg_len) };
    let sig = unsafe { (*kp).inner.sign(msg) };
    unsafe { *out_sig = sig.as_ref().try_into().unwrap() };
    0
}

#[no_mangle]
pub extern "C" fn ring_ed25519_keypair_free(kp: *mut RingKeypair) {
    if !kp.is_null() {
        unsafe {
            drop(Box::from_raw(kp));
        }
    }
}

#[no_mangle]
pub extern "C" fn ring_ed25519_verify(
    sig_ptr: *const [u8; 64],
    msg_ptr: *const u8,
    msg_len: usize,
    pk32: *const [u8; 32],
) -> i32 {
    if sig_ptr.is_null() || msg_ptr.is_null() || pk32.is_null() {
        return -1;
    }
    let msg = unsafe { slice::from_raw_parts(msg_ptr, msg_len) };
    let public_key = UnparsedPublicKey::new(&ED25519, unsafe { &*pk32 });
    match public_key.verify(msg, unsafe { &*sig_ptr }) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}
