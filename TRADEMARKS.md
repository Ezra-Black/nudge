# Trademark Policy

"Nudge" (as the name of this app) and the Nudge character are trademarks of Ezra Black. Nudge's code is open source, but the name and the character are not part of that license. The [Apache License 2.0](LICENSE) says so itself: it "does not grant permission to use the trade names, trademarks, service marks, or product names of the Licensor" (section 6).

This policy exists so that anyone who downloads something called Nudge, with that little guy on it, gets the real thing: the app that keeps everything on their Mac and never sends their screen anywhere. That matters most to the people Nudge is made for.

## Always fine

- Saying what Nudge is and does: "I use Nudge", "a pull request to Nudge", "an article about Nudge".
- Saying that your work is compatible with Nudge or based on it: "based on Nudge's source code", "works with Nudge".
- Building Nudge from this repository for your own use.
- Unmodified screenshots of Nudge in reviews, tutorials, news and teaching.

## Needs permission

- Publishing, sharing or selling an app, build or fork under the name Nudge, or under a confusingly similar name.
- Using the Nudge character, or a character that looks like him, in another app, product, logo or promotion.
- Using the name or the character in a way that suggests Ezra Black endorses, sponsors or makes your product.
- Using "Nudge" in the name of your company, product, domain or app store listing.

To ask, [open an issue](https://github.com/Ezra-Black/nudge/issues/new/choose) titled "Brand permission request" and say what you'd like to do.

## Making a fork

You're welcome to fork Nudge and publish your own version under the Apache License. Before you publish it:

1. **Choose a new name.** Change `CFBundleName`, `CFBundleDisplayName` and `CFBundleIdentifier` in [`Resources/Info.plist`](Resources/Info.plist), and the name in the app's text.
2. **Replace the character.** Delete [`Sources/Nudge/Brand/`](Sources/Nudge/Brand/) and write your own `MascotView` and `MascotArt`. [`Sources/Nudge/Brand/README.md`](Sources/Nudge/Brand/README.md) lists exactly what the rest of the app expects, and a plain SF Symbol is enough to get started.
3. **Remove the brand artwork and website**: [`docs/images/`](docs/images/), [`marketing/`](marketing/) and [`site/`](site/).
4. **Keep the notices.** The Apache License asks you to keep [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE), and to say that you changed the files.

You may say your fork is "based on Nudge", as long as it's clear that it isn't Nudge and isn't made or endorsed by Ezra Black.

## Official builds

The official, signed Nudge app is made and sold by Ezra Black. Building from this repository is and will stay free for your own use.
