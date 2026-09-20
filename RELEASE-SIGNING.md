# Release signing — Jetlet: Solar Escape

Non-secret provenance for the upload key. **No password is stored here.**
Keep the password in a password manager alongside the keystore file itself.

## Upload key

| | |
|---|---|
| Keystore file | `jetlet-release.keystore` (2568 bytes) |
| Working copy | `~/jetlet-release.keystore` — **not in this repo, by design** |
| SHA-256 of the file | `cc586eaba9598adcf3d77e92a3bbd94666d1ab79cbaaf37b6bb989521035e4d1` |
| Certificate subject | `O=Eternal Sky` |
| Certificate SHA-1 | `6F:A1:E2:BA:E7:77:EF:AF:B3:8C:02:D3:9C:17:D5:24:71:B7:35:2E` |
| Certificate SHA-256 | `B8:32:5B:38:E3:68:20:BD:B3:24:B5:5D:D0:FD:62:5C:52:54:14:10:83:D9:E0:EC:BE:0F:EF:A9:62:C0:56:F2` |
| Serial | `d089947b3a2b0f08` |
| Valid | 2026-09-16 → 2054-02-01 |
| Key | 2048-bit RSA, SHA384withRSA |
| Package | `com.eternalsky.jetlet` |

Verified against `builds/jetlet-release.aab` (1.0.2, code 3).

## Verify a build was signed with the right key

The two artifacts need different tools, and using the wrong one reports a
perfectly good build as unsigned:

**AAB** — JAR-signed, so keytool reads it:

    keytool -printcert -jarfile builds/jetlet-release.aab

**APK** — with `minSdk 24` Godot signs using APK Signature Scheme v2 only, with
no v1/JAR signature. `keytool -printcert -jarfile` therefore prints nothing for
an APK and looks like a signing failure. Use apksigner:

    apksigner verify --print-certs builds/jetlet-release.apk

Either way the SHA-256 must match the table above (keytool prints it uppercase
with colons, apksigner lowercase without -- same value).

`tools/export_release.sh` runs the correct check for each artifact
automatically and fails the build on a mismatch.

## Where the keystore path lives

Godot does **not** persist it to `export_presets.cfg`. It is held in
`.godot/export_credentials.cfg`, which is gitignored — and on this machine that
file currently reads `keystore/release=""`, meaning the working value exists
only in the running editor's memory.

So: after a fresh editor start, re-check
**Project > Export > Android > Options > Keystore > Release** before exporting.
A blank field silently falls back to the debug key.

## If the keystore is lost

Recoverable *only* if Play App Signing is enrolled (it is, for any app created
after Aug 2021): request an upload-key reset in Play Console >
Setup > App integrity. Google keeps the app signing key; you only replace the
upload key. Without Play App Signing, a lost key means the app can never be
updated again under this package name.

## Backup checklist

- [ ] Keystore file stored in a password manager or encrypted cloud vault
- [ ] Password stored separately from the file
- [ ] Alias name recorded
- [ ] Restore tested on a second machine
