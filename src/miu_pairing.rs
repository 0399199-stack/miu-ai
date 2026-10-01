use base::{config::keys, message_proto::LoginRequest};
use hbb_common::{
    config::{self, Config},
    protobuf::Message as ProtobufMessage,
    sha2::{Digest, Sha256},
    sodiumoxide::{base64, crypto::sign},
};

pub fn local_public_key() -> String {
    let pair = Config::get_key_pair();
    let stored: Config = config::load_path(Config::file());
    let persisted = serde_json::to_value(stored)
        .ok()
        .and_then(|value| value.get("key_pair").cloned());
    if persisted != serde_json::to_value(&pair).ok() {
        return String::new();
    }
    base64::encode(pair.1, base64::Variant::Original)
}

fn login_digest(request: &LoginRequest, nonce: &[u8]) -> Option<Vec<u8>> {
    if nonce.len() != 32 {
        return None;
    }
    let mut request = request.clone();
    request.miu_controller_proof = Default::default();
    let mut digest = Sha256::new();
    digest.update(b"Miu AI controller login v1\0");
    digest.update(nonce);
    digest.update(request.write_to_bytes().ok()?);
    Some(digest.finalize().to_vec())
}

pub fn sign_login(request: &mut LoginRequest, nonce: &[u8]) {
    let (secret, public) = Config::get_key_pair();
    let Some(secret) = sign::SecretKey::from_slice(&secret) else {
        return;
    };
    if public.len() != 32 {
        return;
    }
    request.miu_controller_public_key = public.into();
    if let Some(digest) = login_digest(request, nonce) {
        request.miu_controller_proof = sign::sign(&digest, &secret).into();
    }
}

pub fn verify_pinned_login(request: &LoginRequest, nonce: &[u8]) -> bool {
    if Config::get_option(keys::OPTION_APPROVE_MODE) != "password"
        || Config::get_option(keys::OPTION_VERIFICATION_METHOD) != "use-permanent-password"
        || !Config::has_permanent_password()
    {
        return false;
    }
    let encoded = Config::get_option(keys::OPTION_MIU_TRUSTED_CONTROLLER_PK);
    let Some(pinned) = parse_pinned_key(&encoded) else {
        return false;
    };
    verify_login_with_key(request, nonce, &pinned)
}

fn parse_pinned_key(encoded: &str) -> Option<Vec<u8>> {
    let key = base64::decode(encoded, base64::Variant::Original).ok()?;
    (key.len() == 32).then_some(key)
}

fn verify_login_with_key(request: &LoginRequest, nonce: &[u8], pinned: &[u8]) -> bool {
    if pinned != &request.miu_controller_public_key[..] {
        return false;
    }
    let Some(public) = sign::PublicKey::from_slice(pinned) else {
        return false;
    };
    let Some(expected) = login_digest(request, nonce) else {
        return false;
    };
    sign::verify(&request.miu_controller_proof, &public)
        .map(|actual| actual == expected)
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn proof_is_bound_to_fresh_nonce_and_login_scope() {
        let _ = hbb_common::sodiumoxide::init();
        let (public, secret) = sign::gen_keypair();
        let mut request = LoginRequest::new();
        request.username = "host".into();
        request.my_id = "controller".into();
        request.session_id = 42;
        request.miu_controller_public_key = public.0.to_vec().into();
        let nonce = [7u8; 32];
        let digest = login_digest(&request, &nonce).unwrap();
        request.miu_controller_proof = sign::sign(&digest, &secret).into();
        assert!(verify_login_with_key(&request, &nonce, &public.0));
        assert!(!verify_login_with_key(&request, &[8u8; 32], &public.0));
        assert!(!verify_login_with_key(&request, &nonce, &[0u8; 32]));
        request.set_file_transfer(Default::default());
        assert!(!verify_login_with_key(&request, &nonce, &public.0));
    }

    #[test]
    fn empty_or_malformed_pin_never_enables_pairing() {
        assert!(parse_pinned_key("").is_none());
        assert!(parse_pinned_key("not a key").is_none());
        assert!(parse_pinned_key(&base64::encode([1u8; 31], base64::Variant::Original)).is_none());
        assert_eq!(
            parse_pinned_key(&base64::encode([2u8; 32], base64::Variant::Original)),
            Some(vec![2u8; 32])
        );
    }
}
