# Releasing a signed build — no Mac required

This is the Phase 4 piece: turning the CI simulator build (Phase 1) into a
real, signed build you can install on a device, entirely from GitHub Actions.
Everything below uses only `openssl` (works on Windows/Linux/macOS) and the
Apple Developer / App Store Connect **web** portals — no Xcode, no Mac.

Two paths, pick one:

- **TestFlight (recommended)** — install via the TestFlight app on any device
  signed into your Apple ID. No device UDID registration needed.
- **Ad-hoc** — a raw `.ipa` you sideload directly (AltStore, Sideloadly,
  etc.). Requires registering each device's UDID in the provisioning profile,
  which is the one step that's genuinely awkward without Xcode (see the note
  at the bottom).

Both need an Apple Developer Program account ($99/year) — that part isn't
avoidable, but enrolling itself is web-only.

## 1. Generate a distribution certificate (openssl, no Mac)

```bash
# Private key — keep this file safe, you'll need it again if you ever
# re-export the .p12 (e.g. cert renewal).
openssl genrsa -out ios_distribution.key 2048

# Certificate signing request
openssl req -new -key ios_distribution.key -out ios_distribution.csr \
  -subj "/emailAddress=you@example.com/CN=Your Name/C=US"
```

Upload `ios_distribution.csr` at
[developer.apple.com → Certificates, IDs & Profiles → Certificates → + →
Apple Distribution](https://developer.apple.com/account/resources/certificates/list).
Download the resulting `.cer`, then:

```bash
# Convert Apple's DER-format .cer to PEM
openssl x509 -in ios_distribution.cer -inform DER -out ios_distribution.pem -outform PEM

# Bundle key + cert into the .p12 CI actually needs. Pick a real password —
# it becomes the BUILD_CERTIFICATE_PASSWORD secret below.
openssl pkcs12 -export -inkey ios_distribution.key -in ios_distribution.pem \
  -out ios_distribution.p12 -passout pass:YOUR_P12_PASSWORD

# Base64-encode for a GitHub secret (Linux/Windows-WSL/macOS all work the same way)
base64 -i ios_distribution.p12 | tr -d '\n' > ios_distribution.p12.b64
```

## 2. Register an App ID

At [developer.apple.com → Identifiers → +](https://developer.apple.com/account/resources/identifiers/list),
register `com.privatemediastudio.app` (matching `PRODUCT_BUNDLE_IDENTIFIER`
in `project.yml`) as an explicit App ID.

## 3. Create a provisioning profile

At [developer.apple.com → Profiles → +](https://developer.apple.com/account/resources/profiles/list):

- **TestFlight path**: choose "App Store Connect" distribution, select the
  App ID from step 2 and the certificate from step 1.
- **Ad-hoc path**: choose "Ad Hoc" distribution instead — this is where
  you'd select registered device UDIDs (see the note at the bottom for how
  to get one without Xcode).

Download the `.mobileprovision` file, then:

```bash
base64 -i YourProfile.mobileprovision | tr -d '\n' > profile.b64
```

## 4. TestFlight path only: create an App Store Connect API key

At [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api),
create a key with **App Manager** role. Download the `.p8` **immediately**
(Apple only lets you download it once) and note the **Key ID** and
**Issuer ID** shown on that page.

```bash
base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '\n' > apikey.b64
```

You'll also need to create the app record itself once at
[App Store Connect → My Apps → +](https://appstoreconnect.apple.com/apps)
using the same bundle ID, so there's somewhere for the build to land.

## 5. Add GitHub repo secrets

Repo → Settings → Secrets and variables → Actions → New repository secret.
For TestFlight, add all of:

| Secret | Value |
|---|---|
| `BUILD_CERTIFICATE_P12_BASE64` | contents of `ios_distribution.p12.b64` |
| `BUILD_CERTIFICATE_PASSWORD` | the password you chose in step 1 |
| `PROVISIONING_PROFILE_BASE64` | contents of `profile.b64` |
| `APPSTORE_CONNECT_API_KEY_BASE64` | contents of `apikey.b64` |
| `APPSTORE_CONNECT_API_KEY_ID` | Key ID from step 4 |
| `APPSTORE_CONNECT_API_ISSUER_ID` | Issuer ID from step 4 |

(Ad-hoc path: just the first three.)

## 6. Fill in your Team ID and go

Replace `REPLACE_WITH_YOUR_TEAM_ID` in `ExportOptions.plist` (TestFlight) or
`ExportOptionsAdHoc.plist` (ad-hoc) with your 10-character Team ID, shown at
the top of any page in the Apple Developer portal's Membership section.

Then in `.github/workflows/ios-ci.yml`, uncomment the `archive-testflight`
job (or `archive-adhoc`) — every line is already written, this is purely
deleting `#` prefixes — and push. The build lands in TestFlight automatically
within a few minutes of the job finishing, or as a downloadable `.ipa`
artifact for the ad-hoc path.

## Getting a device UDID without Xcode (ad-hoc path only)

TestFlight sidesteps this entirely, which is the main reason it's the
recommended path above. If you specifically want ad-hoc sideloading instead,
you need each target device's UDID to register it in the provisioning
profile. Without a Mac, the practical options are: a UDID-detection
configuration profile from a third-party site (installed via Safari on the
device itself, e.g. udid.io — review what you're installing before trusting
any such service with device info), or borrowing Mac/Xcode access just once
for `Window → Devices and Simulators`.
