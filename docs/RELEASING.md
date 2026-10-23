# Releasing Window Shepherd

How a signed, notarized release gets made, so strangers can install the app without macOS saying "can't be opened because Apple cannot check it". Parts 1–4 happen **once**. Part 5 is every release.

Nothing secret ever goes in this repo. Certificates and passwords live in your Mac's Keychain; the Sparkle private key lives in the Keychain too.

## 1. Join the Apple Developer Program (once, $99/year)

1. Go to https://developer.apple.com/programs/enroll/ and click **Start your enrollment**.
2. Sign in with your Apple Account. Two-factor authentication must be on.
3. Choose **Individual / Sole Proprietor** and fill in your legal name. Apps are published under this name.
4. Pay the fee. Approval usually takes from a few hours to two days, and Apple emails you when it's done.

## 2. Make your signing certificate (once)

1. Open **Xcode → Settings → Accounts**, click **+**, choose **Apple Account**, and sign in.
2. Select your account. Next to your name (it says "Individual"), click **Manage Certificates…**
3. Click **+** at the bottom left and choose **Developer ID Application**. Xcode creates it and puts it in your Keychain.
4. In Terminal, run:

   ```sh
   security find-identity -v -p codesigning
   ```

   Copy the part inside the quotes after `Developer ID Application:`, for example `Charles Baynes (AB12CD34EF)`. That is your **DEVELOPER_ID_NAME**.
5. For everyday development builds, also create `Config/Local.xcconfig` (it's gitignored) containing:

   ```
   CODE_SIGN_IDENTITY = Apple Development
   ```

## 3. Let the release script notarize (once)

Notarization uploads each build to Apple for an automatic malware check.

1. Go to https://account.apple.com, open **Sign-In and Security → App-Specific Passwords**, and create one called `notarytool`. Copy it.
2. In Terminal:

   ```sh
   xcrun notarytool store-credentials window-shepherd \
     --apple-id "you@example.com" --team-id AB12CD34EF
   ```

   Use your Apple Account email, and the team ID in brackets from step 2.4. Paste the app-specific password when asked. `window-shepherd` is now your **NOTARY_PROFILE**.

## 4. Set up updates and the download page (once)

1. **Sparkle key.** Run `scripts/fetch-sparkle.sh`, then `vendor/Sparkle/bin/generate_keys`. It stores a private key in your Keychain and prints a public key. Put the public key in `Config/Base.xcconfig`:

   ```
   SPARKLE_PUBLIC_KEY = <the printed public key>
   ```

   The public key isn't secret, so commit that change. Back up the private key with `vendor/Sparkle/bin/generate_keys -x sparkle-private-key.txt` and keep that file somewhere safe outside the repo (`.gitignore` blocks `sparkle_private_key*` names, but don't rely on it). If you lose the private key, existing users can't receive updates.
2. **GitHub Pages** (serves the update feed). On github.com/cabaynes/window-shepherd go to **Settings → Pages**. Set Source to "Deploy from a branch", branch `main`, folder `/docs`, and save. The feed will be at https://cabaynes.github.io/window-shepherd/appcast.xml.
3. **windowshepherd.com.** Until the website exists, point the domain at the repo. In Squarespace → Domains → windowshepherd.com → **Domain forwarding**, forward to `https://github.com/cabaynes/window-shepherd`.
4. **Homebrew tap.** Create a public repo named `homebrew-tap` under cabaynes. Then `brew install --cask cabaynes/tap/window-shepherd` works once `Casks/window-shepherd.rb` is in it (step 5.5).

## 5. Make a release (every time)

1. Update `CHANGELOG.md`: move the "Unreleased" notes under a new version heading.
2. Build, sign and notarize:

   ```sh
   DEVELOPER_ID_NAME="Charles Baynes (AB12CD34EF)" NOTARY_PROFILE=window-shepherd scripts/release.sh 0.1.0
   ```

   This takes a few minutes, mostly waiting for Apple. It prints the DMG's path and SHA-256.
3. On GitHub, go to **Releases → Draft a new release**. Use tag `v0.1.0`, paste the changelog section, attach `dist/Window-Shepherd-0.1.0.dmg`, and publish.
4. Update the feed: `scripts/make-appcast.sh dist/Window-Shepherd-0.1.0.dmg 0.1.0`, then commit and push `docs/appcast.xml`. Existing users see the update within a day, or at once via **Check for Updates…**
5. Homebrew: copy `packaging/window-shepherd.rb` to `Casks/window-shepherd.rb` in the `homebrew-tap` repo, set `version` and `sha256` from step 2, and push.

## Checking a release

- `spctl --assess --type open --context context:primary-signature -v dist/Window-Shepherd-<version>.dmg` should print "accepted" and "source=Notarized Developer ID".
- Download the DMG from the release page on a Mac that has never run the app and open it. It should launch without any "cannot check" warning, show the Accessibility onboarding, and find the update feed.
