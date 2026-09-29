//! Portable guide engine. Versioned JSON-lines over private stdin/stdout; no network or OS APIs.
//!
//! The Nudge app starts the `nudge-engine` binary as a child process and writes one JSON command per line. Each
//! command gets exactly one line back: `{"ok":true,"data":…}` or `{"ok":false,"error":"…"}`. The engine never
//! talks to the model itself: it builds prompts, and the app sends back what the model wrote. Protocol v1 is
//! described in `docs/PROTOCOL.md` at the root of the repository.
//!
//! Modules:
//!
//! - `model`: the observation and plan types that cross the wire.
//! - `geometry`: rectangles as fractions of the window.
//! - `select`: what kind of thing each element is, and which ones the model is shown.
//! - `tour`: a tour's stops, grouping similar controls, and blocks of text in a chosen area.
//! - `prompt`: the text the model reads, and descriptions used when it says nothing.
//! - `session`: [`Engine`], its state between commands, and the commands themselves.

#![forbid(unsafe_code)]
#![warn(missing_docs)]

mod geometry;
mod model;
mod prompt;
mod select;
mod session;
mod tour;

use serde_json::{json, Value};

pub use session::Engine;

/// Items shown to the on-device model. Its context window is small, so the window is summarized.
const PROMPT_LIMIT: usize = 60;
/// Default most stops in a tour.
const TOUR_LIMIT: usize = 36;
/// How many stops the model explains per call.
const BATCH: usize = 6;
/// Most blocks of text a tour of a chosen area reads through, after its controls.
const TEXT_BLOCKS: usize = 8;

/// The first `n` characters of `s`.
fn clipped(s: &str, n: usize) -> String {
    s.chars().take(n).collect()
}

/// Handles one line of input and returns the one line of output, without its line break.
///
/// ```
/// let mut engine = nudge_engine::Engine::default();
/// let reply = nudge_engine::handle_line(&mut engine, r#"{"version":1,"command":"hello"}"#);
/// assert_eq!(reply, r#"{"data":{"engine":"Nudge","network":false,"protocol":1},"ok":true}"#);
/// ```
pub fn handle_line(engine: &mut Engine, line: &str) -> String {
    let result = match serde_json::from_str::<Value>(line) {
        Ok(v) => match engine.dispatch(&v) {
            Ok(data) => json!({"ok": true, "data": data}),
            Err(e) => json!({"ok": false, "error": e}),
        },
        Err(_) => json!({"ok": false, "error": "Invalid JSON"}),
    };
    result.to_string()
}
