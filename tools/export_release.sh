#!/usr/bin/env bash
# Export the Android release APK and AAB from the "Android" preset.
#
# Run this from a shell where the release keystore credentials are exported:
#
#   export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$HOME/jetlet-release.keystore"
#   export GODOT_ANDROID_KEYSTORE_RELEASE_USER="<alias>"
#   export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="<password>"
#   ./tools/export_release.sh            # both artifacts
#   ./tools/export_release.sh aab        # just the AAB
#   ./tools/export_release.sh apk        # just the APK
#
# The preset's gradle_build/export_format decides APK (0) vs AAB (1) -- the
# output filename on the command line does NOT. So this flips it per run and
# restores it on exit, including on failure.

set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRESET="Android"
GODOT="${GODOT:-godot}"
CFG="$PROJECT/export_presets.cfg"
KEYTOOL="${KEYTOOL:-$HOME/Android/jdk17/bin/keytool}"
APKSIGNER="${APKSIGNER:-$(ls -d "$HOME/Android/Sdk/build-tools"/*/apksigner 2>/dev/null | sort -V | tail -1)}"

# Upload key fingerprint -- see RELEASE-SIGNING.md. Normalised to lowercase hex
# with no colons, because the two tools below disagree on formatting.
EXPECTED="b8325b38e36820bdb324b55dd0fd625c5254141083d9e0ecbe0fefa962c056f2"

WANT="${1:-both}"
case "$WANT" in both|apk|aab) ;; *) echo "usage: $0 [both|apk|aab]" >&2; exit 2 ;; esac

for v in GODOT_ANDROID_KEYSTORE_RELEASE_PATH \
         GODOT_ANDROID_KEYSTORE_RELEASE_USER \
         GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD; do
    if [[ -z "${!v:-}" ]]; then
        echo "error: $v is not set -- see the header of this script." >&2
        exit 1
    fi
done

[[ -f "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" ]] || {
    echo "error: keystore not found at $GODOT_ANDROID_KEYSTORE_RELEASE_PATH" >&2; exit 1; }
[[ -x "$APKSIGNER" ]] || {
    echo "error: apksigner not found; set APKSIGNER=/path/to/apksigner" >&2; exit 1; }

if pgrep -x godot >/dev/null; then
    echo "error: the Godot editor is running. It rewrites export_presets.cfg" >&2
    echo "       from memory on save and would clobber the format flip." >&2
    exit 1
fi

echo "==> version: $(grep -E '^version/(code|name)' "$CFG" | tr '\n' ' ')"
echo "==> features: $(grep -E '^custom_features' "$CFG")"

set_format() { sed -i "s|^gradle_build/export_format=.*|gradle_build/export_format=$1|" "$CFG"; }
trap 'set_format 1' EXIT

# An APK with minSdk >= 24 is signed with APK Signature Scheme v2/v3 and carries
# no v1/JAR signature, so `keytool -printcert -jarfile` reports it as unsigned.
# Only apksigner can read it. An AAB *is* JAR-signed, and apksigner rejects it
# as not-an-APK. Hence one tool each.
cert_sha256() {
    case "$1" in
    *.apk) "$APKSIGNER" verify --print-certs "$1" 2>/dev/null \
               | awk '/certificate SHA-256 digest:/ {print $NF; exit}' ;;
    *)     "$KEYTOOL" -printcert -jarfile "$1" 2>/dev/null \
               | awk '/SHA256:/ {print $2; exit}' | tr -d ':' | tr 'A-Z' 'a-z' ;;
    esac
}

export_one() {  # $1 = format (0 apk / 1 aab), $2 = output filename
    local out="$PROJECT/builds/$2"
    echo
    echo "==> exporting $2"
    set_format "$1"
    rm -f "$out"
    "$GODOT" --headless --path "$PROJECT" --export-release "$PRESET" "$out"
    [[ -f "$out" ]] || { echo "error: $2 was not produced" >&2; exit 1; }

    local got; got="$(cert_sha256 "$out")"
    if [[ "$got" != "$EXPECTED" ]]; then
        echo "error: $2 is signed with the WRONG key" >&2
        echo "  expected $EXPECTED" >&2
        echo "  got      ${got:-<unreadable/unsigned>}" >&2
        exit 1
    fi
    echo "    ok  $(du -h "$out" | cut -f1)  signature verified"
}

[[ "$WANT" == both || "$WANT" == apk ]] && export_one 0 jetlet-release.apk
[[ "$WANT" == both || "$WANT" == aab ]] && export_one 1 jetlet-release.aab

echo
echo "==> done. builds/:"
ls -lh "$PROJECT/builds/" | grep -E 'jetlet-release\.(apk|aab)$'
