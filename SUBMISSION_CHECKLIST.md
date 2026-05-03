# Cup Queen — App Store Submission Checklist

## ✅ Done (code complete)
- [x] NSUserTrackingUsageDescription added to Info.plist
- [x] Privacy policy HTML written (`privacy-policy/index.html`)
- [x] AdMob stub wired (ATT → interstitial → rewarded)
- [x] StoreKit 2 IAP (`com.shellgame.magiccup.removeads`)
- [x] Game Center leaderboards (`cq.leaderboard.score`, `cq.leaderboard.survival`)

---

## Step 1 — Host the Privacy Policy ✅ DONE

Privacy policy is live at:
**https://ericwang19832003.github.io/cupqueen-privacy/**

---

## Step 2 — Set Up AdMob

1. Go to [admob.google.com](https://admob.google.com)
2. Create app → iOS → "Cup Queen" → bundle ID: `com.shellgame.magiccup`
3. Create two ad units:
   - **Interstitial** → copy the Ad Unit ID (format: `ca-app-pub-xxx/xxx`)
   - **Rewarded** → copy the Ad Unit ID
4. Open `ShellGame/ShellGameApp.swift` and replace the test IDs:
   ```swift
   // Line ~47-48
   static let interstitial = "ca-app-pub-YOUR_ID/YOUR_INTERSTITIAL_ID"
   static let rewarded     = "ca-app-pub-YOUR_ID/YOUR_REWARDED_ID"
   ```
5. Add AdMob SDK via Xcode → File → Add Package Dependencies:
   - URL: `https://github.com/googleads/swift-package-manager-google-mobile-ads`
   - Version: latest
6. Add your AdMob App ID to Info.plist:
   - In Xcode → target → Info tab → add:
     `GADApplicationIdentifier` = `ca-app-pub-YOUR_APP_ID~YOUR_APP_ID`
7. Uncomment all `// TODO: ADMOB` lines in `ShellGameApp.swift`

---

## Step 3 — Register IAP in App Store Connect

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. Your App → In-App Purchases → `+`
3. Type: **Non-Consumable**
4. Product ID: `com.shellgame.magiccup.removeads`
5. Reference Name: `Remove Ads`
6. Price: $1.99 (Tier 1)
7. Localisation → English:
   - Display Name: `Remove Ads`
   - Description: `Enjoy Cup Queen ad-free forever.`
8. Status: **Ready to Submit**

---

## Step 4 — Register Game Center Leaderboards in App Store Connect

1. Your App → Features → Game Center → `+` Leaderboard → **Classic Leaderboard**
2. **Leaderboard 1:**
   - Leaderboard ID: `cq.leaderboard.score`
   - Name: `High Score`
   - Score Format: Integer, suffix "pts", ascending: No
3. **Leaderboard 2:**
   - Leaderboard ID: `cq.leaderboard.survival`
   - Name: `Survival — Level 7`
   - Score Format: Integer, suffix "rounds", ascending: No
4. Enable Game Center capability in Xcode:
   - Target → Signing & Capabilities → `+` → Game Center

---

## Step 5 — Add Privacy Policy URL

Paste this URL in both places:
**https://ericwang19832003.github.io/cupqueen-privacy/**

- **App Store Connect** → App Information → Privacy Policy URL
- **AdMob dashboard** → App settings → Privacy & messaging → Privacy policy URL

---

## Final Pre-Submission Checklist

- [ ] Privacy policy hosted and URL accessible in browser
- [ ] Privacy policy URL in App Store Connect + AdMob
- [ ] AdMob SDK added, real Ad Unit IDs in code, all TODO lines uncommented
- [ ] `GADApplicationIdentifier` in Info.plist
- [ ] IAP `com.shellgame.magiccup.removeads` registered and Ready to Submit
- [ ] Game Center leaderboard IDs registered + capability enabled in Xcode
- [ ] App tested on real device (haptics, ATT prompt, ads, IAP, Game Center)
- [ ] Screenshots captured for 6.9" (`bash scripts/screenshots.sh`)
- [ ] App version set to 1.0 in Xcode
- [ ] Age rating: 12+ (no gambling/casino classification)
- [ ] Category: Games → Puzzle / Family
- [ ] Subtitle: "Shell Game — Find the Ball" (28 chars)
