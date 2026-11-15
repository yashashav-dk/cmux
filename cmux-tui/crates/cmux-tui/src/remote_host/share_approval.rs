//! Share This Mac for a Mac already the owner's, confirmed on the device the
//! owner is at (Leo, 2026-11-14: "Let the owner confirm from the device they
//! are at (the same-account device asking, one click there, recorded in the
//! audit log)").
//!
//! - The asker: `cmux remote-host share on --device DEVICE` (or the
//!   `remote_share` MCP tool with `device`) asks the asker's own cmux app
//!   (`remote.confirm {action: share, device}`). The app shows "Share
//!   Studio's screen with your devices?" and only after the person clicks Allow
//!   signs a [`ShareApproval`] with its device key (the Secure Enclave key the
//!   device hub knows it by). An agent can call `remote.confirm`, but nothing
//!   signs without the click: no click, no approval, no share
//!   ([`share_from_here`]).
//! - The target: [`admit`] takes an approval only from a same-account machine
//!   its owner granted ([`SameAccountGrant`], hq#11046 cut 1's "control for my
//!   other signed-in machines"), with the asker's signature, naming this Mac,
//!   fresh, and with a nonce not seen before. The target then turns Share This
//!   Mac on itself: its own `PUT /v1/devices/:id/mac-screen`, as the device
//!   hub requires, which records the hub's `shared` audit event.
//! - Both sides write the host audit log (`audit.jsonl`): who confirmed, on
//!   which device, and when.

// The target half (admit, its audit) is called once hq#11046 cut 1's grant
// implements `SameAccountGrant`; the asker half runs on Unix only.
#![cfg_attr(not(test), allow(dead_code, reason = "the target half is wired with hq#11046 cut 1"))]

use std::collections::HashSet;

use base64::Engine as _;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

/// The approval format; the first line of [`ShareApproval::canonical`].
pub(crate) const VERSION: &str = "cmux.share-approval.v1";
/// How old an approval may be when the target reads it (the asker's dialog
/// waits 130 s; delivery takes seconds).
pub(crate) const MAX_AGE_SECS: u64 = 300;
/// How far ahead of the target's clock an approval may be.
pub(crate) const MAX_SKEW_SECS: u64 = 60;

/// The asker app's answer to one Allow click: what the person allowed, where
/// and when, signed by the asker's device key. Ids are the device hub's; the
/// names are for people (the audit and the dialog) and are not signed.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct ShareApproval {
    pub v: String,
    /// The Mac to share (its device hub id).
    pub target: String,
    #[serde(default)]
    pub target_name: String,
    /// The device the person clicked Allow on (its device hub id).
    pub asker: String,
    #[serde(default)]
    pub asker_name: String,
    /// The signed-in account (device hub user id) that clicked.
    pub confirmed_by: String,
    /// When the person clicked, Unix seconds (a JSON number or decimal string:
    /// the app sends a string, so no float rounding touches it).
    #[serde(deserialize_with = "unix_seconds")]
    pub confirmed_at: u64,
    /// Random per click; the target admits each once.
    pub nonce: String,
    /// base64 raw r||s ECDSA P-256 SHA-256 signature of [`Self::canonical`].
    pub signature: String,
}

fn unix_seconds<'de, D: serde::Deserializer<'de>>(deserializer: D) -> Result<u64, D::Error> {
    match Value::deserialize(deserializer)? {
        Value::Number(number) => number.as_u64(),
        Value::String(text) => text.parse().ok(),
        _ => None,
    }
    .ok_or_else(|| serde::de::Error::custom("confirmed_at must be whole Unix seconds"))
}

impl ShareApproval {
    /// The signed bytes, one field per line. The app builds the same string
    /// (`CmuxRemoteShareApproval.canonical`); `share_approval_vectors.json`
    /// holds both sides to it.
    pub(crate) fn canonical(&self) -> String {
        format!(
            "{}\ntarget={}\nasker={}\nconfirmed_by={}\nconfirmed_at={}\nnonce={}",
            self.v, self.target, self.asker, self.confirmed_by, self.confirmed_at, self.nonce
        )
    }

    fn display_target(&self) -> &str {
        if self.target_name.is_empty() { &self.target } else { &self.target_name }
    }

    fn display_asker(&self) -> &str {
        if self.asker_name.is_empty() { &self.asker } else { &self.asker_name }
    }
}

/// A machine asking the target, as the target sees it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Asker<'a> {
    /// Its device hub id.
    pub device: &'a str,
    /// The account it is signed in to (device hub user id).
    pub account: &'a str,
}

/// The target's owner consent for its other signed-in machines. hq#11046 cut
/// 1's grant ("control for my other signed-in machines", off by default, one
/// click on the target Mac) implements it; until then nothing does, and every
/// approval is refused.
pub(crate) trait SameAccountGrant {
    /// Whether the target's owner granted `asker` (a machine signed in to the
    /// target's own account) control of this Mac.
    fn covers(&self, asker: &Asker<'_>) -> bool;
}

/// The device keys the target trusts: the device hub's list for its own
/// account (each device's `signingKey`, base64 X9.63 P-256).
pub(crate) trait AskerKeys {
    fn signing_key(&self, device: &str) -> Option<String>;
}

/// This Mac, reading an approval.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Target<'a> {
    /// Its device hub id.
    pub device: &'a str,
    /// The account it is signed in to.
    pub account: &'a str,
    /// Now, Unix seconds.
    pub now: u64,
}

/// Why the target refused an approval: a stable code and the person's words.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct Refused {
    pub code: &'static str,
    pub message: String,
}

impl Refused {
    fn new(code: &'static str, message: impl Into<String>) -> Self {
        Self { code, message: message.into() }
    }

    pub(crate) fn json(&self) -> Value {
        json!({"code": self.code, "message": self.message})
    }
}

/// Whether this Mac takes `approval`: every check passes, in this order, or
/// the first that fails says why. A taken nonce goes into `seen`.
pub(crate) fn admit(
    approval: &ShareApproval,
    target: &Target<'_>,
    grant: &impl SameAccountGrant,
    keys: &impl AskerKeys,
    seen: &mut HashSet<String>,
) -> Result<(), Refused> {
    if approval.v != VERSION {
        return Err(Refused::new(
            "share.bad_version",
            format!("unknown approval format {:?}", approval.v),
        ));
    }
    if approval.target != target.device {
        return Err(Refused::new(
            "share.wrong_target",
            format!("the approval is for {}, not this Mac", approval.display_target()),
        ));
    }
    if approval.confirmed_at > target.now.saturating_add(MAX_SKEW_SECS)
        || target.now.saturating_sub(approval.confirmed_at) > MAX_AGE_SECS
    {
        return Err(Refused::new(
            "share.stale",
            "the approval is too old (or from the future); confirm again on your device",
        ));
    }
    if approval.confirmed_by != target.account {
        return Err(Refused::new(
            "share.other_account",
            "the approval comes from another account; only this Mac's own account may share it",
        ));
    }
    let asker = Asker { device: &approval.asker, account: &approval.confirmed_by };
    if !grant.covers(&asker) {
        return Err(Refused::new(
            "share.not_granted",
            format!(
                "{} may not control this Mac: its owner has not turned on control for their other signed-in machines here",
                approval.display_asker()
            ),
        ));
    }
    let Some(key) = keys.signing_key(&approval.asker) else {
        return Err(Refused::new(
            "share.unknown_device",
            format!("{} is not one of this account's devices", approval.display_asker()),
        ));
    };
    if !signature_valid(approval, &key) {
        return Err(Refused::new(
            "share.bad_signature",
            "the approval is not signed by the device it names; nobody clicked Allow there",
        ));
    }
    if !seen.insert(approval.nonce.clone()) {
        return Err(Refused::new("share.replayed", "this approval was already used"));
    }
    Ok(())
}

/// Whether `approval.signature` is `signing_key`'s signature of its canonical bytes.
fn signature_valid(approval: &ShareApproval, signing_key: &str) -> bool {
    let engine = base64::engine::general_purpose::STANDARD;
    let (Ok(key), Ok(signature)) = (engine.decode(signing_key), engine.decode(&approval.signature))
    else {
        return false;
    };
    ring::signature::UnparsedPublicKey::new(&ring::signature::ECDSA_P256_SHA256_FIXED, key)
        .verify(approval.canonical().as_bytes(), &signature)
        .is_ok()
}

/// The asker's audit fields for a confirmed approval: what was allowed, who
/// clicked, on which device, when.
pub(crate) fn asker_fields(approval: &ShareApproval) -> Value {
    json!({
        "device": approval.target,
        "device_name": approval.display_target(),
        "confirmed_by": approval.confirmed_by,
        "confirmed_on": approval.asker,
        "confirmed_on_name": approval.display_asker(),
        "confirmed_at": super::grant::rfc3339(approval.confirmed_at),
        "nonce": approval.nonce,
    })
}

/// The target's audit line for one decision.
pub(crate) fn target_entry(approval: &ShareApproval, decision: &Result<(), Refused>) -> Value {
    let mut entry = json!({
        "event": if decision.is_ok() { "remote_host.share_admitted" } else { "remote_host.share_refused" },
        "via": "same-account",
        "asker": approval.asker,
        "asker_name": approval.display_asker(),
        "confirmed_by": approval.confirmed_by,
        "confirmed_on": approval.asker,
        "confirmed_at": super::grant::rfc3339(approval.confirmed_at),
        "nonce": approval.nonce,
    });
    if let (Err(refused), Some(map)) = (decision, entry.as_object_mut()) {
        map.insert("code".into(), json!(refused.code));
        map.insert("reason".into(), json!(refused.message));
    }
    entry
}

/// [`admit`], with the decision written to this Mac's host audit log.
pub(crate) fn admit_and_record(
    approval: &ShareApproval,
    target: &Target<'_>,
    grant: &impl SameAccountGrant,
    keys: &impl AskerKeys,
    seen: &mut HashSet<String>,
) -> Result<(), Refused> {
    let decision = admit(approval, target, grant, keys, seen);
    super::audit::append(&target_entry(approval, &decision));
    decision
}

/// Gets a confirmed approval to the target Mac.
pub(crate) trait Deliver {
    fn deliver(&self, approval: &ShareApproval) -> Result<Value, Value>;
}

/// The delivery until hq#11046 cut 1 lands: the target has no same-account
/// grant to admit an approval with yet, so it says so instead of trying.
pub(crate) struct AwaitingSameAccountControl;

impl Deliver for AwaitingSameAccountControl {
    fn deliver(&self, approval: &ShareApproval) -> Result<Value, Value> {
        Err(json!({
            "code": "share.needs_same_account_control",
            "message": format!(
                "you allowed sharing {} here, and it is recorded; {} admits it once control for your other signed-in machines is on there (hq#11046). Until then, run `cmux remote-host share on` on {} itself.",
                approval.display_target(), approval.display_target(), approval.display_target()
            ),
            "details": {"confirmed": true, "delivered": false, "device": approval.target},
        }))
    }
}

/// The app's answer to `remote.confirm {action: share, device}`, read.
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum AskerOutcome {
    /// The person clicked Allow; the app signed this.
    Confirmed(ShareApproval),
    /// The person clicked Cancel (or closed the dialog).
    Declined,
    /// No signed approval came back: an older app, or an answer that is not one.
    NotConfirmed(String),
}

/// Reads the app's answer for `device` (the id or name the caller passed).
pub(crate) fn asker_outcome(answer: &Value, device: &str) -> AskerOutcome {
    if answer.get("declined").and_then(Value::as_bool) == Some(true)
        || answer.get("ok").and_then(Value::as_bool) == Some(false)
    {
        return AskerOutcome::Declined;
    }
    let Some(raw) = answer.get("approval") else {
        return AskerOutcome::NotConfirmed(
            "the cmux app answered without a signed approval; check it with `cmux app version`"
                .into(),
        );
    };
    let approval: ShareApproval = match serde_json::from_value(raw.clone()) {
        Ok(approval) => approval,
        Err(error) => return AskerOutcome::NotConfirmed(format!("unreadable approval: {error}")),
    };
    if approval.signature.is_empty() || approval.nonce.is_empty() {
        return AskerOutcome::NotConfirmed("the approval is not signed".into());
    }
    let wanted = device.trim();
    if approval.target != wanted && !approval.target_name.eq_ignore_ascii_case(wanted) {
        return AskerOutcome::NotConfirmed(format!(
            "the app approved {}, not {wanted}",
            approval.display_target()
        ));
    }
    AskerOutcome::Confirmed(approval)
}

/// The params of `remote.confirm` for sharing `device`.
pub(crate) fn confirm_params(device: &str) -> Value {
    json!({"action": "share", "on": true, "device": device.trim()})
}

/// The asker's whole flow: ask the person in this device's app (`ask` sends
/// `remote.confirm`), record the answer, deliver a signed approval. Only a
/// signed approval reaches `deliver`; a decline, a timeout or an unsigned
/// answer ends here as a refusal.
pub(crate) fn share_from_here(
    device: &str,
    ask: impl FnOnce(Value) -> Result<Value, Value>,
    deliver: &impl Deliver,
    mut record: impl FnMut(&str, Value),
) -> Result<Value, Value> {
    let device = device.trim();
    if device.is_empty() {
        return Err(
            json!({"code": "bad_request", "message": "--device needs a device id or name"}),
        );
    }
    let answer = match ask(confirm_params(device)) {
        Ok(answer) => answer,
        Err(error) => {
            record("remote_host.share_not_confirmed", json!({"device": device, "error": error}));
            return Err(error);
        }
    };
    match asker_outcome(&answer, device) {
        AskerOutcome::Declined => {
            record("remote_host.share_declined", json!({"device": device}));
            Err(
                json!({"code": "share.declined", "message": format!("not shared: the person did not allow sharing {device}")}),
            )
        }
        AskerOutcome::NotConfirmed(why) => {
            record("remote_host.share_not_confirmed", json!({"device": device, "error": why}));
            Err(json!({"code": "share.not_confirmed", "message": format!("not shared: {why}")}))
        }
        AskerOutcome::Confirmed(approval) => {
            record("remote_host.share_confirmed", asker_fields(&approval));
            let delivered = deliver.deliver(&approval)?;
            Ok(json!({
                "shared": true,
                "device": approval.target,
                "device_name": approval.display_target(),
                "confirmed_by": approval.confirmed_by,
                "confirmed_on": approval.asker,
                "confirmed_at": super::grant::rfc3339(approval.confirmed_at),
                "target": delivered,
            }))
        }
    }
}

#[cfg(test)]
#[path = "share_approval_tests.rs"]
mod tests;
