# Testing

Nudge reads real apps, so testing has two halves: automated tests for logic, and checks by hand for everything that depends on what's on screen.

## Automated tests

```sh
make test          # everything
make test-swift    # Swift Testing tests in Tests/NudgeTests
make test-engine   # Rust unit tests and protocol replays in engine/
make lint          # formatting and lints, as CI runs them
```

- **Swift tests** cover models and services that don't need the screen: geometry, settings decoding and migration, feedback storage and shortcut names.
- **Engine tests** cover choosing and grouping items, text blocks, fallbacks and prompts. The protocol tests replay recorded sessions from `engine/tests/fixtures/` and compare every response line with its `.expected` file. See [engine/README.md](../engine/README.md) to add one.

## Diagnostics

The built app has a few command-line flags that don't read the screen:

| Flag | What it does |
|---|---|
| `--diagnostics` | Reports whether the on-device model and the bundled engine are ready, and the permission status |
| `--model-check` | Also makes one real on-device model request, using made-up controls |
| `--export-hero <file.png>` | Draws the README and website header image |
| `--export-character-sheet <file.png>` | Draws every expression of the character |
| `--export-theme-preview <path>` | Draws a sample card in light and dark (`<path>-light.png`, `<path>-dark.png`) |
| `--export-icon <folder>` | Writes the app icon set |

Run them from the bundle, for example `build/Nudge.app/Contents/MacOS/Nudge --diagnostics`. A command-line launch can see different permissions than the app launched from Finder; the Setup section of Nudge's settings is the source of truth.

## Checking by hand

Before a pull request that changes behavior, try the parts it touches in a few everyday apps (Safari or Chrome, Mail, Calculator, System Settings, Finder):

**Whole-window tours**
- [ ] The overview describes the window, then steps go through it in reading order.
- [ ] Similar controls (number keys, a row of tabs) are one step, highlighted together.
- [ ] In a browser, Nudge asks "This web page" or the browser's controls, and links say where they go.
- [ ] The highlight follows the window when you drag it, and hides then returns when you scroll.
- [ ] Back, Next, Space, Shift-Space, the progress dots, ⌃⇧← and ⌃⇧→ all move correctly.

**Area mode**
- [ ] The box stays framed, clear inside, while it's explained.
- [ ] Buttons come first, then pictures ("a photo of a dog"), then text blocks; nothing outside the box is mentioned.
- [ ] The card and character never cover the item being explained.

**Goal mode**
- [ ] One step at a time; Done waits for you; Skip pauses rather than pretending the task is done.

**The end of a guide**
- [ ] "Did I do good?" appears; Yes celebrates; No shows the note box with typing working and Space not skipping.
- [ ] "Look again" starts a fresh guide.

**Everywhere**
- [ ] Switching apps or Spaces pauses the guide; the shortcut resumes it; Esc closes it.
- [ ] Read-aloud starts, pauses and stops.
- [ ] With Reduce Motion on, nothing bounces or slides.
- [ ] Appearance changes show on the card, the highlight and the character right away.
- [ ] Nothing appears in Console that includes screen content.

## Resetting permissions

To see first-run behavior again, reset Nudge's own permission records (use your build's bundle identifier):

```sh
tccutil reset Accessibility com.ezrablack.nudge
tccutil reset ScreenCapture com.ezrablack.nudge
defaults delete com.ezrablack.nudge
```
