//! `nudge-engine`: the guide engine as a child process. Reads one protocol command per line on stdin and writes
//! one reply per line on stdout, until stdin closes or stdout goes away.

use std::io::{self, BufRead, Write};

use nudge_engine::{handle_line, Engine};

fn main() {
    let mut engine = Engine::default();
    let mut out = io::BufWriter::new(io::stdout());
    for line in io::stdin().lock().lines() {
        // A read error, or input that isn't UTF-8, ends the session.
        let Ok(line) = line else { break };
        let reply = handle_line(&mut engine, &line);
        if writeln!(out, "{reply}").and_then(|_| out.flush()).is_err() {
            break;
        }
    }
}
