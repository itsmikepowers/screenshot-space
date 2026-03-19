# Signing And Install Workflow

`build.sh` expects a real code-signing identity and installs the app to `/Applications/Screenshot Space.app`.

That stable bundle path and signing identity are important because macOS Accessibility permissions are tied to the installed app identity. Running transient build outputs directly is much more likely to break TCC permission persistence.

## Supported Local Workflow

1. Make sure a code-signing identity exists in your keychain.
2. Build, sign, verify, and install the app with:

```bash
./build.sh
```

3. Grant Accessibility access to `/Applications/Screenshot Space.app`.
4. Launch the installed app:

```bash
open "/Applications/Screenshot Space.app"
```

Do not grant Accessibility access to `.build/release/ScreenshotSpace` or any other transient build output.

## Verify The Signing Identity Exists

The default identity name is `ScreenshotSpace Developer`.

Check for it with:

```bash
security find-identity -v -p codesigning
```

If you want to use a different identity name, override it when running the script:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name" ./build.sh
```

## Create A Local Signing Identity

For local development, create a certificate in Keychain Access that is valid for code signing and name it `ScreenshotSpace Developer`, or use another identity name and pass it through `SIGN_IDENTITY`.

Minimum expectations for the identity:

- It appears in `security find-identity -v -p codesigning`
- `codesign --verify --deep --strict` succeeds on the app bundle
- The identity name stays stable across rebuilds

For broader distribution or stricter Gatekeeper acceptance, prefer an Apple-issued Developer ID Application certificate.

## Verification Commands

After `./build.sh`, verify the installed bundle directly:

```bash
codesign --verify --deep --strict --verbose=2 "/Applications/Screenshot Space.app"
codesign -dv --verbose=4 "/Applications/Screenshot Space.app"
spctl --assess --type execute --verbose=4 "/Applications/Screenshot Space.app"
```

The script already runs these checks and prints the results, but these commands are useful when troubleshooting.

## Troubleshooting

If the signing identity is missing:

- Re-run `security find-identity -v -p codesigning`
- Confirm the certificate is installed in a keychain visible to the current user
- Pass the correct identity name through `SIGN_IDENTITY`

If Accessibility permission seems stuck after rebuilding:

1. Quit Screenshot Space.
2. Remove the old installed bundle from `/Applications` if the identity changed.
3. Rebuild and reinstall with `./build.sh`.
4. Reset the old TCC entry if needed:

```bash
tccutil reset Accessibility com.screenshotspace.app
```

5. Re-grant Accessibility access to `/Applications/Screenshot Space.app`.

If `spctl` fails but `codesign` succeeds:

- Local development can still use the stable signed identity for TCC testing
- Check whether the certificate is trusted for code signing on this Mac
- Use a Developer ID Application certificate if you need stronger Gatekeeper acceptance
