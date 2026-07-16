# Scratio Homebrew & Release Setup

This guide covers the one-time Apple / GitHub setup required to ship notarized DMGs and install Scratio via a personal Homebrew tap.

## What users run

After the tap is published and a release exists:

```bash
brew tap emilshr/scratio
brew install --cask scratio
```

Then grant **Screen Recording** under System Settings → Privacy & Security → Screen Recording, and relaunch Scratio if prompted.

## Prerequisites

1. Paid **Apple Developer Program** membership
2. Access to the GitHub repo `emilshr/scratio`
3. Ability to create a second GitHub repo for the tap: `emilshr/homebrew-scratio`

## 1. Developer ID certificate

1. Open [Apple Developer → Certificates](https://developer.apple.com/account/resources/certificates/list)
2. Create a **Developer ID Application** certificate (for distributing outside the Mac App Store)
3. Install it in Keychain Access on your Mac
4. Export it as a `.p12` (include the private key). Choose a strong password — this is `P12_PASSWORD`

Encode for GitHub Actions:

```bash
base64 -i DeveloperID.p12 | pbcopy
```

That clipboard value is `BUILD_CERTIFICATE_BASE64`.

Find your **Team ID** (10 characters) in the Apple Developer membership page — that is `APPLE_TEAM_ID`.

## 2. App Store Connect API key (notarization)

1. Open [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)
2. Create a key with **Developer** (or Admin) access
3. Download the `.p8` once — this is `APP_STORE_CONNECT_API_KEY_P8` (file contents)
4. Note **Key ID** → `APP_STORE_CONNECT_API_KEY_ID`
5. Note **Issuer ID** → `APP_STORE_CONNECT_ISSUER_ID`

Optional local credential store:

```bash
xcrun notarytool store-credentials "scratio-notary" \
  --key /path/to/AuthKey_XXXX.p8 \
  --key-id YOUR_KEY_ID \
  --issuer YOUR_ISSUER_ID
```

CI uses the env-var form via `scripts/notarize.sh`, not the keychain profile name.

## 3. GitHub Actions secrets

In `emilshr/scratio` → Settings → Secrets and variables → Actions, add:

| Secret | Value |
|--------|--------|
| `BUILD_CERTIFICATE_BASE64` | Base64 of the Developer ID `.p12` |
| `P12_PASSWORD` | Password for that `.p12` |
| `KEYCHAIN_PASSWORD` | Any random password for the ephemeral CI keychain |
| `APPLE_TEAM_ID` | Your 10-character Team ID |
| `APP_STORE_CONNECT_API_KEY_ID` | API Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID |
| `APP_STORE_CONNECT_API_KEY_P8` | Full PEM text of the `.p8` file |

The workflow [`.github/workflows/release-dmg.yml`](../.github/workflows/release-dmg.yml) fails fast if any of these are missing.

## 4. Ship a release

Tag and push (example `1.0.0`):

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow will:

1. Import the Developer ID cert and resolve the full signing identity
2. Run unit tests
3. Archive + export (hard-fail if export fails — no unsigned fallback)
4. Re-sign `Scratio.app`, verify with `codesign --verify`
5. Build `Scratio-<version>.dmg`
6. Notarize + staple + Gatekeeper assess
7. Publish a GitHub Release with the DMG and `.sha256` sidecar

### Local packaging (optional)

```bash
export APPLE_TEAM_ID=XXXXXXXXXX
export CODE_SIGN_IDENTITY="Developer ID Application: Your Name (XXXXXXXXXX)"
./scripts/package_dmg.sh 1.0.0

export APP_STORE_CONNECT_API_KEY_ID=...
export APP_STORE_CONNECT_ISSUER_ID=...
export APP_STORE_CONNECT_API_KEY_P8="$(cat AuthKey_xxx.p8)"
./scripts/notarize.sh build/dmg/Scratio-1.0.0.dmg
```

## 5. Create the Homebrew tap

1. Create a public GitHub repo named **`homebrew-scratio`** under your account  
   (`brew tap emilshr/scratio` maps to `emilshr/homebrew-scratio`)
2. Copy the in-repo template:

```bash
mkdir -p /path/to/homebrew-scratio/Casks
cp homebrew/Casks/scratio.rb /path/to/homebrew-scratio/Casks/scratio.rb
```

3. After each GitHub Release, update the cask:

```ruby
version "1.0.0"   # must match the tag without the leading v
sha256 "<hash>"   # contents of Scratio-1.0.0.dmg.sha256 (hash only)
```

The release asset URL must match:

`https://github.com/emilshr/scratio/releases/download/v#{version}/Scratio-#{version}.dmg`

4. Commit and push the tap repo.

### Updating the cask after a release

```bash
VERSION=1.0.0
HASH=$(curl -fsSL "https://github.com/emilshr/scratio/releases/download/v${VERSION}/Scratio-${VERSION}.dmg.sha256")
# Edit Casks/scratio.rb version + sha256, then:
cd /path/to/homebrew-scratio
git add Casks/scratio.rb
git commit -m "scratio ${VERSION}"
git push
```

Users upgrade with:

```bash
brew update
brew upgrade --cask scratio
```

## 6. Verify install

On a clean Mac (or a VM):

```bash
brew tap emilshr/scratio
brew install --cask scratio
open /Applications/Scratio.app
```

Confirm:

- Gatekeeper does not block the app
- Screen Recording permission can be granted
- Capture overlay works on all attached displays

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| Workflow fails at “Require release secrets” | Missing GitHub Actions secret |
| Workflow fails at identity resolution | `.p12` is not Developer ID Application, or wrong password |
| `exportArchive` fails | Team ID / Manual signing mismatch; check Xcode signing for Release |
| Notarization rejected | Unsigned or ad-hoc binary; ensure export + re-sign steps succeeded |
| `brew install` checksum error | Cask `sha256` / `version` not updated after release |
| Overlay does nothing | Screen Recording still denied — reopen app after granting |

## Reference files

- Release workflow: [`.github/workflows/release-dmg.yml`](../.github/workflows/release-dmg.yml)
- Package script: [`scripts/package_dmg.sh`](../scripts/package_dmg.sh)
- Notarize script: [`scripts/notarize.sh`](../scripts/notarize.sh)
- Cask template: [`homebrew/Casks/scratio.rb`](../homebrew/Casks/scratio.rb)
