# Glyph — Release (M4: sign · notarize · DMG)

Produces a notarized `dist/Glyph.dmg` for direct download. Notarizing also makes the
**Quick Look** preview/thumbnail extensions register reliably in Finder.

## Prerequisites (one-time)

1. **Join the Apple Developer Program** ($99/yr): <https://developer.apple.com/programs/>
   (Free Personal-Team signing runs the app locally but cannot notarize, and does not
   reliably activate the Quick Look extensions — see `docs/SETUP.md`.)

2. **Create a “Developer ID Application” certificate** (Xcode ▸ Settings ▸ Accounts ▸
   your team ▸ Manage Certificates ▸ “+” ▸ *Developer ID Application*). Verify:
   ```sh
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```
   Note the full name, e.g. `Developer ID Application: Paolo Bozzola (TEAMID)`.

3. **Store notary credentials** in the keychain (once). Create an app-specific password at
   <https://appleid.apple.com> (Sign-In & Security ▸ App-Specific Passwords), then:
   ```sh
   xcrun notarytool store-credentials glyph-notary \
     --apple-id "paolo.bozzola@moviri.com" \
     --team-id "PAID_TEAM_ID" \
     --password "xxxx-xxxx-xxxx-xxxx"
   ```
   (`PAID_TEAM_ID` is your paid team's ID — may differ from the free Personal Team
   `537QQR9WVW`. It's the `(TEAMID)` in your Developer ID cert name.)

## Build the release

```sh
DEV_ID="Developer ID Application: Paolo Bozzola (PAID_TEAM_ID)" make dist
```

This runs `scripts/package.sh`: builds Release, signs the app + both Quick Look extensions
inside-out with hardened runtime + secure timestamp, builds the DMG, submits to Apple for
notarization (waits), and staples the ticket. Result: `dist/Glyph.dmg`.

Also set `DEVELOPMENT_TEAM` in `project.yml` to your paid team ID so local Xcode builds use it.

## After first install

- Drag Glyph to /Applications from the DMG and launch once.
- `pluginkit -m | grep -i glyph` should now list the preview + thumbnail extensions.
- If a `.md` preview/thumbnail still doesn't use Glyph, enable it in
  **System Settings ▸ General ▸ Login Items & Extensions ▸ Quick Look**.

## Verify

```sh
spctl -a -vvv -t open --context context:primary-signature dist/Glyph.dmg   # accepted
xcrun stapler validate dist/Glyph.dmg                                      # validated
```

## Still TODO (post first release)

- **Sparkle auto-updates**: add the Sparkle framework, a public EdDSA key, and host an
  `appcast.xml` (e.g. GitHub Releases). Deferred until there's a hosting URL for the appcast.
