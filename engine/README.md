# Nudge guide engine

`nudge-engine` is the small Rust program behind Nudge's guides. It decides what a guide explains and in what order, writes the prompts for the on-device model, checks the model's answers against what is really on screen, and keeps track of where the guide is. It has no platform code, makes no network requests and keeps nothing outside memory.

## How the app talks to it

The app bundles the binary as `Nudge.app/Contents/MacOS/nudge-engine`, and `EngineBridge` (in `Sources/Nudge/Services/`) starts it as a child process. The app writes one JSON command per line on the engine's stdin, and the engine answers each one with exactly one line on stdout:

```sh
$ echo '{"version":1,"command":"hello"}' | cargo run -q
{"data":{"engine":"Nudge","network":false,"protocol":1},"ok":true}
```

The engine never calls the model itself. `prepare` returns prompts; the app runs them through the model and sends the answers back with `install` and `explain`. Every command, field and reply is described in [docs/PROTOCOL.md](../docs/PROTOCOL.md).

## Layout

| Path | What's there |
|---|---|
| `src/main.rs` | The stdin/stdout loop. Nothing else. |
| `src/lib.rs` | `handle_line` (one line in, one line out), the module list and the tuning constants. |
| `src/session.rs` | `Engine`: the commands, the pending prompt, the active guide and the tour cache. |
| `src/model.rs` | The types that cross the wire: observations, elements, plans, steps. |
| `src/select.rs` | What kind of thing each element is, and which ones the model is shown. |
| `src/tour.rs` | A tour's stops and their order, grouping similar controls, text blocks in a chosen area. |
| `src/prompt.rs` | The prompts, and the plain descriptions used when the model says nothing. |
| `src/geometry.rs` | Rectangles as fractions of the window. |
| `tests/protocol.rs` | Replays every fixture through the library and through the built binary. |
| `tests/fixtures/` | Recorded sessions: `name.jsonl` in, `name.expected` out. |

The limits the protocol documents (60 items shown to the model, 36 tour stops, batches of 6, 8 text blocks) are the constants at the top of `src/lib.rs`. If you change one, update `docs/PROTOCOL.md` too.

## Build and test

You need Rust 1.78 or later ([rustup](https://rustup.rs)).

```sh
cargo build --release --locked                       # target/release/nudge-engine
cargo test --locked                                  # unit tests and fixture replays
cargo fmt -- --check
cargo clippy --all-targets --locked -- -D warnings
```

From the repository root, `make test-engine` and `make lint` run the same checks, as CI does.

## Fixtures

A fixture is a recorded session. `tests/fixtures/name.jsonl` holds commands, one per line, exactly as the app would send them. `tests/fixtures/name.expected` holds the engine's replies, one per line. The tests replay every `.jsonl` file and require every reply to match byte for byte, so any change in behavior shows up as a failing line.

To add one:

1. Write `tests/fixtures/name.jsonl`. Each line is one command with `"version":1`. Start from a similar fixture; a short script that prints the JSON is easier than writing long observations by hand.
2. Record the replies:

   ```sh
   cargo run --release --locked < tests/fixtures/name.jsonl > tests/fixtures/name.expected
   ```

3. Read `name.expected` and check each reply is what you meant. Keys are sorted, and line *n* answers line *n* of the script.
4. Run `cargo test`. New files are picked up automatically.

If a change is meant to change what the engine says, re-record the affected `.expected` files the same way and review the diff: every changed line is a changed reply. A refactor should leave every fixture untouched.
