# Release Screenroom

Releases are prepared on a Mac. GitHub Actions checks tests and packaging; it does not hold signing credentials or publish releases.

The current public preview, **v1.0.4**, is an **Apple silicon, ad-hoc signed, unnotarized** download requiring **macOS 15 or later**. It is marked as a prerelease. A verified archive and checksum do not replace Apple's notarization. Keep that distinction explicit in release notes until Developer ID signing and notarization are available.

For v1.0.4, manual checks with full-screen apps, Spaces, Stage Manager, and physical keyboard shortcuts remain incomplete. Carry these limitations into the release notes.

## Prepare the source

1. Start from the intended release commit with a clean working tree. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `Resources/Info.plist` when releasing a new build.
2. Update `CHANGELOG.md`, the download version and architecture in `README.md` and `docs/SETUP.md`, and any affected setup instructions.
3. Run `swift test --configuration release`. Complete the relevant manual checks in [CONTRIBUTING.md](../CONTRIBUTING.md#validate-your-change), including a recording with audible software audio and start/stop from another app using the shortcut.
4. Record any checks that remain incomplete in the release notes. Do not label an architecture supported merely because it compiled.

The build script targets the build Mac's architecture. Packaging detects `arm64`, `x86_64`, or a universal executable and includes that architecture in the filename; it does not cross-compile or combine builds.

## Package an unnotarized preview

For a preview that does not embed a developer certificate:

```sh
SIGNING_IDENTITY=- ./scripts/build-app.sh
./scripts/package-release.sh
```

The build includes the MIT license in `Screenroom.app/Contents/Resources/LICENSE`. Packaging verifies the existing bundle signature and creates these files for version 1.0.4 on Apple silicon:

```text
dist/Screenroom-1.0.4-macos-arm64.zip
dist/Screenroom-1.0.4-macos-arm64.zip.sha256
```

The packager does not change the signature. It excludes resource-fork metadata and refuses to overwrite an existing archive or checksum. To package a different bundle or use an empty output folder:

```sh
./scripts/package-release.sh /path/to/Screenroom.app /path/to/output
```

Do not distribute your local Apple Development-signed build as a notarized release. For preview users, link to the [documented installation steps](SETUP.md#install-the-preview-download), explain the ad-hoc signature and permission limitations, and use GitHub's **prerelease** status.

## Developer ID signing and notarization

For regular public distribution, follow Apple's [Developer ID](https://developer.apple.com/developer-id/) and [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow). This requires an appropriate Apple Developer account, a **Developer ID Application** identity with its private key, and notarization credentials. An Apple Development certificate is not a substitute.

Keep certificates, private keys, app-specific passwords, and API keys outside Git. Store notarization credentials in the local Keychain using `notarytool store-credentials` as described by Apple. The commands below assume a Keychain profile named `screenroom-notary` already exists; replace the example signing identity with your own.

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh
mkdir -p dist/notary-submit dist/notarized
ditto -c -k --keepParent dist/Screenroom.app dist/notary-submit/Screenroom.zip
xcrun notarytool submit dist/notary-submit/Screenroom.zip --keychain-profile screenroom-notary --wait
```

Proceed only after notarization reports **Accepted**. If it fails, inspect the submission log and fix the cause before distributing the app. Then staple the ticket, verify the bundle, and create the final archive:

```sh
xcrun stapler staple dist/Screenroom.app
xcrun stapler validate dist/Screenroom.app
codesign --verify --strict dist/Screenroom.app
spctl --assess --type execute --verbose=2 dist/Screenroom.app
./scripts/package-release.sh dist/Screenroom.app dist/notarized
```

Upload the archive and checksum from `dist/notarized`, which were created **after stapling**. Do not upload the earlier submission ZIP or reuse its checksum. Do not rebuild or re-sign the app after notarization. Test installation of the final downloaded archive on another Mac or user account.

## Verify and publish

From the directory containing the final archive and checksum, check both:

```sh
shasum -a 256 -c Screenroom-1.0.4-macos-arm64.zip.sha256
unzip -t Screenroom-1.0.4-macos-arm64.zip
```

Also extract the ZIP into an empty temporary folder and run `codesign --verify --strict` against the extracted app. Check its version, architecture, and bundled license. Ensure the release contains no recordings, crash reports, development signing material, or local paths. Build output stays ignored by Git; only the ZIP and checksum belong in release assets.

Push the reviewed source and ensure macOS CI passes. In [GitHub Releases](https://github.com/SalehMuAm/Screenroom/releases), prepare a draft with a new `vVERSION` tag targeting that exact source commit. Attach the versioned ZIP and `.zip.sha256` file, and include:

- Required macOS version and supported architecture.
- Signing and notarization status, plus a link to setup instructions.
- Changes and any known limitations or incomplete manual checks.
- SHA-256 checksum or a reference to the attached checksum file.

Mark preview builds as prereleases. Review the draft, publish it, then verify the public download links and checksum. Never replace an already published binary with a different build under the same version; issue a new version instead.
