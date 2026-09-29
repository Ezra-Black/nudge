# Contributing to Nudge

Thank you for helping! Nudge exists for people who find computers confusing, often older adults, and every improvement makes someone's day a little easier. This guide covers how to get set up, the few rules that keep Nudge trustworthy, and how to send a pull request that's easy to review.

**Quick links:** [Architecture](docs/ARCHITECTURE.md) · [Engine protocol](docs/PROTOCOL.md) · [Testing](docs/TESTING.md) · [Code of Conduct](CODE_OF_CONDUCT.md) · [Security](SECURITY.md)

## Ways to help

- **Report a bug.** Use the [bug report form](https://github.com/Ezra-Black/nudge/issues/new?template=bug_report.yml). Tell us which app or website Nudge was explaining, what it said, and what you expected.
- **Tell us where Nudge got it wrong.** An explanation that confused you is a bug too.
- **Suggest an idea** with the [feature request form](https://github.com/Ezra-Black/nudge/issues/new?template=feature_request.yml).
- **Fix something.** Issues labeled [`good first issue`](https://github.com/Ezra-Black/nudge/labels/good%20first%20issue) are a friendly place to start.
- **Improve the words.** Clearer, kinder, shorter text is one of the most valuable things you can contribute.

## The rules that don't bend

These protect the people who use Nudge. A pull request that breaks one can't be merged, however good it is otherwise.

1. **Nothing leaves the Mac.** No network requests, servers, analytics, telemetry, crash reporting, remote models or update pings in the app. If a feature seems to need the network, open an issue to talk it through first.
2. **Nudge guides; it never acts.** It must never click, type, scroll or change anything in another app, or press people to share passwords or turn off protections.
3. **Read only when asked.** Screen content is read only after the person presses a shortcut, and only while a guide is showing. It's never written to disk or logged. Password fields are never read.
4. **Be kind to eyes and nerves.** Keep text large and readable, targets big, and motion calm. Respect Reduce Motion. Never blame the person for anything.
5. **Leave the brand alone unless asked.** The files in `Sources/Nudge/Brand/`, `docs/images/` and `marketing/` are covered by the [Nudge Brand License](LICENSE-BRAND.md). Improvements are welcome, but please open an issue before changing the character's look.

## Getting set up

You need a Mac with Apple silicon and **macOS 26** or later with **Apple Intelligence** turned on, **Xcode 26** (Swift 6.2) and **Rust** (from [rustup](https://rustup.rs)).

```sh
git clone https://github.com/<you>/nudge.git
cd nudge
cp .env.example .env
make run
```

`make run` builds the Rust engine and the Swift app, assembles `build/Nudge.app` and opens it. Grant **Accessibility** (and optionally **Screen Recording**) in System Settings when Nudge asks.

> [!TIP]
> Set `NUDGE_SIGN_IDENTITY` in `.env` to your Apple Development certificate (`security find-identity -v -p codesigning` lists yours). With the default ad-hoc signature, macOS forgets Nudge's permissions after every rebuild.

To work in Xcode, open `Package.swift`. Xcode can build, test and debug the Swift code, but the app needs the engine next to it, so use `make build` to produce a runnable `Nudge.app`.

### Useful commands

| Command | What it does |
|---|---|
| `make build` | Build `Nudge.app` |
| `make run` | Build and open it |
| `make test` | Run the Swift and Rust tests |
| `make lint` | Check formatting and lints, as CI does |
| `make format` | Format all Swift and Rust code |
| `build/Nudge.app/Contents/MacOS/Nudge --diagnostics` | Check the on-device model and the engine without reading the screen |

## Finding your way around

Nudge is a SwiftUI and AppKit app, organized as models, view models, views and services, plus a small Rust engine:

| Folder | What's there |
|---|---|
| `Sources/Nudge/Models/` | Plain data: observations, guide plans, settings, appearance |
| `Sources/Nudge/ViewModels/` | `AppController`, which runs a guide session, split by concern, and `GuideModel` for the card |
| `Sources/Nudge/Views/` | SwiftUI views: the guide card and the settings window |
| `Sources/Nudge/Services/` | Reading the screen, the on-device model, the engine bridge, speech, sound, feedback |
| `Sources/Nudge/Platform/` | AppKit windows: the overlay, the area selector, global shortcuts |
| `Sources/Nudge/Brand/` | The character and icons (brand licensed) |
| `engine/` | The Rust guide engine: what to explain, prompts, validation, the tour |

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) walks through how a guide flows through these pieces and where to make common changes.

## Making a change

1. **Talk first about big things.** For a new feature or a large refactor, open an issue so we can agree on the approach before you spend time on it. Small fixes can go straight to a pull request.
2. **Branch from `main`** with a short, descriptive name, like `fix-highlight-after-scroll`.
3. **Keep it focused.** One pull request, one change. Small pull requests get reviewed quickly.
4. **Match the code around you.** Run `make format`. Name things plainly. Comments explain *why*, not *what*, in a sentence or two.
5. **Test it.** Add or update tests where you can (see below), run `make test` and `make lint`, and try your change in real apps using the checklist in [docs/TESTING.md](docs/TESTING.md).
6. **Show it.** For anything visible, add a screenshot or a short screen recording to the pull request.

### Writing for Nudge

Everything Nudge says is read by someone who may be anxious or new to computers.

- Use short sentences and everyday words: "the button that goes back a page", not "the navigation control".
- Say what something does and why you'd use it, not just its name.
- Speak to the person as "you". Be warm, never condescending. Don't mention age, and don't call anything easy.
- Use curly quotes and apostrophes (’ “ ”) in text the app shows.

The instructions for the on-device model live in `Sources/Nudge/Services/LocalIntelligence.swift` and the prompts in `engine/src/`. Changes there can shift every explanation, so please include a few before-and-after examples.

### Tests

- **Swift:** [Swift Testing](https://developer.apple.com/documentation/testing) tests live in `Tests/NudgeTests/`. Run them with `make test-swift`.
- **Engine:** unit tests sit next to the code in `engine/src/`, and protocol tests replay the recorded sessions in `engine/tests/fixtures/`. Run them with `make test-engine`. If you intentionally change the engine's output, update the matching `.expected` file and explain why in your pull request.
- **By hand:** reading real apps can't be fully automated. [docs/TESTING.md](docs/TESTING.md) lists what to check.

### Commits

- Write the subject in the imperative, under about 70 characters: `Keep the highlight on text blocks after scrolling`.
- Use the body, if needed, to explain why.
- **Sign off every commit** (`git commit -s`). This adds a `Signed-off-by` line certifying that you wrote the change or have the right to submit it under the project's license, as described by the [Developer Certificate of Origin](https://developercertificate.org).

## Pull requests

When you open a pull request, the template asks for a short summary, how you tested it, and a checklist. Continuous integration then builds the app, runs every test and checks formatting. A maintainer will review it, usually within a week. We may suggest changes; that's a normal part of the process, not a judgment of your work. Once it's approved and green, a maintainer merges it.

## License

By contributing, you agree that your contributions are licensed under the [Apache License 2.0](LICENSE), like the rest of the code (see section 5 of the license). Contributions to brand assets fall under the [Nudge Brand License](LICENSE-BRAND.md#contributions-to-the-brand-assets).
