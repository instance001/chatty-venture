# Chatty-Venture

Chatty-Venture is a mobile-first, narration-led text-adventure app. Its reducer-owned ledger preserves confirmed story facts, objectives, and endings while a selected Dungeon Master narrates the moment-to-moment journey.

## Features

- Three guided adventures plus editable Free Mode adventures
- Durable story state, objective tracking, hints, and epilogues
- Built-in storyteller, optional imported local GGUFs, and optional user-configured cloud providers
- Separate Cloud and Local GGUF prompt editors, plus an optional cross-lane Dungeon Master style note
- Explicit fallback choices when narration fails
- Light and dark themes, private-data cleanup, in-app developer messaging, and an AGPLv3 source link

## Privacy

Local stories, models, prompts, and settings are stored in private app storage. Cloud narration occurs only after the user explicitly selects and configures a provider; requests go directly to that provider. The in-app Message developer form sends only the subject and message intentionally entered by the user.

The public privacy policy is published at <https://instance001.github.io/privacy/chatty-venture.html>.

## Store listing assets

Ready-to-upload Google Play artwork and emulator screenshots are in [store-listing/google-play](store-listing/google-play/README.md).

## Development

```powershell
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build appbundle --release
```

Release output is written to `build/app/outputs/bundle/release/app-release.aab`.

## Bring your own model

Chatty-Venture deliberately ships no LLM weights in public source or ordinary builds. Import a GGUF into private app storage through the in-app local-model manager. SmolLM2-360M-Instruct is a compact starting point; larger GGUFs may be more capable but require more memory. Model weights are ignored by Git and are never stored through Git LFS.

For a private Google Play release that includes the ignored Smol asset, run `./tool/build-play-bundled.ps1 -BuildNumber 4` from PowerShell and use a build number higher than every one already uploaded to Play. The script temporarily adds the model to Flutter's asset manifest, produces `build/app/outputs/bundle/release/app-release.aab`, and restores the clean source manifest afterward.

## Licence

Chatty-Venture is free software under the [GNU Affero General Public License v3.0](LICENSE). Source is intended for <https://github.com/Instance001/chatty-venture>.
