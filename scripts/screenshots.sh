#!/bin/bash
# Cup Queen — App Store Screenshot Capture
# Usage: bash scripts/screenshots.sh
# Run from project root. Simulator must be booted with the app installed.

UDID="50282512-942F-4991-B223-C71DC01F715D"
BUNDLE="com.shellgame.magiccup"
OUT="screenshots/raw"
mkdir -p "$OUT"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

header() {
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${YELLOW}  📸  Screenshot $1 / 5: $2${RESET}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

instructions() {
    echo -e "${CYAN}  Steps:${RESET}"
    while IFS= read -r line; do
        echo -e "${CYAN}    $line${RESET}"
    done <<< "$1"
}

capture() {
    local filename="$1"
    echo ""
    echo -e "  Press ${GREEN}ENTER${RESET} when the screen looks right..."
    read -r
    xcrun simctl io "$UDID" screenshot "$OUT/$filename.png"
    echo -e "  ${GREEN}✓ Saved $OUT/$filename.png${RESET}"
}

# ── Launch ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Cup Queen — Screenshot Capture (5 shots)${RESET}"
echo "Launching app..."
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
sleep 0.5
xcrun simctl launch "$UDID" "$BUNDLE" > /dev/null
sleep 2

# ── 1. Home Screen ────────────────────────────────────────────────────────────
header "1" "Home Screen"
instructions "→ The app just launched — you should see the home screen.
→ Wait for the star field and cup animations to settle (~2s).
→ Best if best-stats badge is visible (play a round first if needed)."
capture "01_home"

# ── 2. Gameplay – Choosing Phase ─────────────────────────────────────────────
header "2" "Gameplay — Choose a Cup"
instructions "→ Tap 'Play Now' on the home screen.
→ Watch the ball get placed, then watch the shuffle.
→ Wait until the shuffle STOPS and the green eye icon appears.
→ Do NOT tap a cup yet — capture right here."
capture "02_choosing"

# ── 3. Win Result ─────────────────────────────────────────────────────────────
header "3" "Win Result Overlay"
instructions "→ From the choosing phase: tap the correct cup (find the ball!).
→ Wait for the 'You Found It! ✨' overlay to appear.
→ Capture with the '+X pts' badge visible."
capture "03_win"

# ── 4. Level Up ───────────────────────────────────────────────────────────────
header "4" "Level Up Badge"
instructions "→ Keep winning rounds until you see the yellow 'LEVEL UP!' badge.
→ Capture immediately when it appears (it fades after ~1.6s).
→ Tip: if you've already levelled up, wipe app data and replay:
       xcrun simctl privacy $UDID reset all $BUNDLE"
capture "04_levelup"

# ── 5. High Streak HUD ────────────────────────────────────────────────────────
header "5" "Streak on Fire"
instructions "→ Win 5+ rounds in a row so the streak shows '🔥5' or higher.
→ Capture just AFTER winning (choosing phase with HUD visible).
→ The score number should be high — 200+ pts ideally."
capture "05_streak"

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}  ✅  All 5 screenshots saved to ./$OUT/${RESET}"
echo ""
echo "  Next steps:"
echo "  1. Open screenshots/raw/ and review each PNG"
echo "  2. Upload 6.9\" shots in App Store Connect → your app → Media"
echo "     (iPhone 17 Pro Max simulator = 6.9\" device)"
echo "  3. Optional: add marketing text overlays with"
echo "     https://www.rottenwood.com/ or Sketch/Figma"
echo ""
echo "  Required sizes for App Store submission:"
echo "    6.9\"  — mandatory (iPhone 16/17 Pro Max) — these shots cover it"
echo "    6.5\"  — recommended (iPhone 14 Pro Max) — optional if 6.9\" provided"
echo "    5.5\"  — optional (iPhone 8 Plus)"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
