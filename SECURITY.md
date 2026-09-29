# Security and Privacy

Nudge reads what's on people's screens, so we take security and privacy problems very seriously. Thank you for helping keep Nudge's users safe.

## Reporting a problem

**Please don't open a public issue.** Report it privately through GitHub instead:

1. Go to [**Report a vulnerability**](https://github.com/Ezra-Black/nudge/security/advisories/new) on this repository.
2. Describe the problem, how to reproduce it, and what someone could do with it.

We'll acknowledge your report within **3 business days**, keep you updated as we investigate, and credit you in the release notes if you'd like. Please give us a reasonable amount of time to fix the problem before you talk about it publicly.

## What we especially want to hear about

- Any way that screen content, feedback notes or other data could **leave the Mac**, or be written somewhere it shouldn't be.
- Any way Nudge could be made to **click, type or act** in another app, or to read the screen without the person pressing a shortcut.
- **Password fields** or other secure text being read.
- Text on a web page or in an app that makes Nudge give **harmful or misleading guidance**, such as telling someone to share a password or turn off a protection. Screen text is untrusted input to the on-device model, and we treat instruction injection as a security bug.
- Problems in how the app talks to its bundled engine (`engine/`), or in how it asks for and uses macOS permissions.

## Supported versions

Security fixes go into the latest release. Nudge is young, so older versions aren't patched separately; please update to the newest version.
