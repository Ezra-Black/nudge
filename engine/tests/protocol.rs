//! Replays each script in `tests/fixtures` and compares every reply with the recorded one, byte for byte.
//!
//! A fixture is a pair: `name.jsonl` holds one protocol command per line, as the app would send them, and
//! `name.expected` holds the engine's replies, one per line. See the README for how to add one.

use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
};

use nudge_engine::{handle_line, Engine};

fn fixtures_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests").join("fixtures")
}

/// Every fixture script's name, sorted.
fn fixture_names() -> Vec<String> {
    let mut names: Vec<String> = fs::read_dir(fixtures_dir())
        .expect("tests/fixtures exists")
        .map(|entry| entry.expect("readable fixture entry").path())
        .filter(|path| path.extension().is_some_and(|ext| ext == "jsonl"))
        .map(|path| path.file_stem().expect("fixture name").to_string_lossy().into_owned())
        .collect();
    names.sort();
    names
}

fn read(name: &str, extension: &str) -> String {
    let path = fixtures_dir().join(format!("{name}.{extension}"));
    fs::read_to_string(&path).unwrap_or_else(|e| panic!("reading {}: {e}", path.display()))
}

/// Points at the first reply that differs, so a failure is readable without a diff tool.
fn assert_same_replies(name: &str, actual: &str, expected: &str) {
    let (actual_lines, expected_lines): (Vec<&str>, Vec<&str>) = (actual.lines().collect(), expected.lines().collect());
    for (n, (a, e)) in actual_lines.iter().zip(&expected_lines).enumerate() {
        assert_eq!(a, e, "{name}.jsonl line {}: reply differs from {name}.expected", n + 1);
    }
    assert_eq!(actual_lines.len(), expected_lines.len(), "{name}: number of replies");
    assert_eq!(actual, expected, "{name}: output differs from {name}.expected");
}

#[test]
fn fixtures_are_present_and_paired() {
    let names = fixture_names();
    assert!(names.len() >= 8, "expected the recorded fixtures, found {names:?}");
    for name in &names {
        assert!(
            fixtures_dir().join(format!("{name}.expected")).is_file(),
            "{name}.jsonl has no {name}.expected"
        );
    }
}

#[test]
fn library_replays_every_fixture() {
    for name in fixture_names() {
        let mut engine = Engine::default();
        let mut output = String::new();
        for line in read(&name, "jsonl").lines() {
            output.push_str(&handle_line(&mut engine, line));
            output.push('\n');
        }
        assert_same_replies(&name, &output, &read(&name, "expected"));
    }
}

#[test]
fn binary_replays_every_fixture() {
    for name in fixture_names() {
        let mut child = Command::new(env!("CARGO_BIN_EXE_nudge-engine"))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .expect("start nudge-engine");
        // Write from another thread: the engine answers as it reads, and a full stdout pipe would stall both sides.
        let mut stdin = child.stdin.take().expect("stdin is piped");
        let script = read(&name, "jsonl");
        let writer = thread::spawn(move || stdin.write_all(script.as_bytes()));
        let output = child.wait_with_output().expect("nudge-engine runs");
        writer.join().expect("writer thread").expect("write the script");
        assert!(
            output.status.success(),
            "{name}: nudge-engine exited with {}",
            output.status
        );
        let stdout = String::from_utf8(output.stdout).expect("replies are UTF-8");
        assert_same_replies(&name, &stdout, &read(&name, "expected"));
    }
}

/// A malformed request is answered with an error; it must never bring the engine down.
#[test]
fn area_scope_without_a_region_is_an_error() {
    let mut engine = Engine::default();
    let request = r#"{"version":1,"command":"prepare","request":"r","scope":"area","observation":{"app":"A","bundle":"b","window":"W","window_id":1,"elements":[{"id":"1","label":"OK","role":"AXButton","bounds":{"x":0.1,"y":0.1,"width":0.1,"height":0.1},"source":"ax"}]}}"#;
    let reply: serde_json::Value = serde_json::from_str(&handle_line(&mut engine, request)).expect("a JSON reply");
    assert_eq!(reply["ok"], false);
    assert!(reply["error"].as_str().is_some_and(|e| e.contains("region")));
    // The engine still answers afterwards.
    let hello: serde_json::Value =
        serde_json::from_str(&handle_line(&mut engine, r#"{"version":1,"command":"hello"}"#)).unwrap();
    assert_eq!(hello["ok"], true);
}
