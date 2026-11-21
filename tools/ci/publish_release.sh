#!/bin/bash
# GitHub release of a LineageOS build of this tree (signed zip, images, checksums) and feed of the LineageOS Updater
# app (updater.json of the release "lineage-<version>-ota", replaced at every build; packages/apps/Updater,
# Utils.parseJsonUpdate: datetime = ro.build.date.utc, romtype, version).
#
#   tools/ci/publish_release.sh <version 16.0|17.1> <folder of the images artifact> <commit of the build>
#
# Called by the "publish" job of the build workflow (after the build job uploaded its images artifact) and by the
# "publish an existing build" workflow (images artifact of an earlier run, kept 14 days): a refused release (HTTP 403
# "Resource not accessible by integration", runs 44473470443 and 44675551801 of lineage-17.1, the build itself
# succeeded) is published again without building again. Every GitHub call is tried 3 times, 90 s apart; a release
# created by an earlier attempt or run (same tag) only gets its files uploaded again (--clobber).
set -euo pipefail
VERSION=$1 DIR=$2 SHA=$3
R=$GITHUB_REPOSITORY
cd "$DIR"

retry() {
	local i
	for i in 1 2 3; do
		"$@" && return 0
		echo "attempt $i of 3 failed: $*" >&2
		[ $i = 3 ] || sleep 90
	done
	return 1
}

Z=$(ls LibreHU-LineageOS-"$VERSION"-*.zip)
DT=$(sed -n 's/^ro.build.date.utc=//p' build.prop)
TYPE=$(sed -n 's/^ro.lineage.releasetype=//p' build.prop)
VER=$(sed -n 's/^ro.lineage.build.version=//p' build.prop)
[ -n "$VER" ] || [ "$VERSION" != 16.0 ] || VER=16.0   # as the 16.0 workflow did before (${VER:-16.0})
# Only builds of this version in this feed (the Updater installs only the same ro.lineage.build.version)
[ "$VER" = "$VERSION" ] || { echo "::error::ro.lineage.build.version=$VER, not $VERSION: not published"; exit 1; }
# One tag per build: the build date (ro.build.date.utc), not the time of publishing, so that publishing again
# reuses the same release.
TAG=lineage-$VERSION-$(date -u -d "@$DT" +%Y%m%d-%H%M)-${SHA::7}
case "$TAG" in lineage-"$VERSION"-*) ;; *) echo "::error::tag $TAG"; exit 1;; esac
FILES=("$Z" boot-librehu-bootmenu.img boot-librehu.img system.img.zst build.prop SHA256SUMS)
sha256sum -c --quiet SHA256SUMS || { echo "::error::images artifact damaged (SHA256SUMS)"; exit 1; }

case "$VERSION" in
16.0)
	TITLE="LineageOS 16.0, $(date -u -d "@$DT" +%d/%m/%Y) (${SHA::7})"
	NOTES="LineageOS 16.0 pour l'UJC201, arbre ${SHA::7}. Installation et mises a jour : docs/BUILD.md (section 8). Zip signe (test-keys) : TWRP ou l'appli Mises a jour de LineageOS. Le vendor reste celui de l'unite."
	OTA_TITLE="LineageOS 16.0 : flux de mises a jour";;
17.1)
	TITLE="LineageOS 17.1 EXPERIMENTALE, $(date -u -d "@$DT" +%d/%m/%Y) (${SHA::7})"
	NOTES="LineageOS 17.1 (Android 10) EXPERIMENTALE pour l'UJC201, arbre ${SHA::7} (branche lineage-17.1). Sauvegarde TWRP (system, boot, data) avant, et effacer data (pas de mise a jour par-dessus une 16.0). Installation : docs/BUILD.md. Zip signe (test-keys) : TWRP. Le vendor reste celui de l'unite."
	OTA_TITLE="LineageOS 17.1 (experimentale) : flux de mises a jour";;
*) echo "::error::version $VERSION"; exit 1;;
esac

# Commit the new tag points to. GitHub refuses the workflow token (GITHUB_TOKEN, never given the "workflows"
# permission) a new tag on a commit whose .github/workflows differ from the tip of its branch: HTTP 403 "Resource not
# accessible by integration" (this repository: every refused release had a CI commit pushed on the branch while it
# built, d66936b after c81fa57, 2d4292e after ae64541; every published one was still the tip; same pattern in
# github.com/blinkbitcoin/shared-workflows/issues/29). The release is then tagged on the tip of the branch when only
# files that are not in the ROM changed since the build commit: same ROM sources. Otherwise it stops, explained.
# Not in the ROM: .github/, tools/ci/, tools/wifi/ (CI checks), docs (docs/, *.md), and the separate WPA3 hotspot
# zips (tools/make_hotspot_zips.py, tools/flashable/wifi-hotspot-wpa3.sh: the ROM zip does not take them).
BRANCH=lineage-$VERSION
TARGET=$SHA
CHANGED=$(gh api "repos/$R/compare/$SHA...$BRANCH" --jq 'if .status == "identical" then "" elif .status == "ahead" then ([.files[].filename] | join("\n")) else "DIVERGED" end' || echo FAILED)
if [ -n "$CHANGED" ] && grep -q '^\.github/workflows/' <<<"$CHANGED" && ! gh release view "$TAG" --repo "$R" >/dev/null 2>&1; then
	if ! grep -v -q -E '^(\.github/|tools/ci/|tools/wifi/|docs/|tools/make_hotspot_zips\.py$|tools/flashable/wifi-hotspot-wpa3\.sh$)|\.md$' <<<"$CHANGED"; then
		TARGET=$(gh api "repos/$R/commits/$BRANCH" --jq .sha)
		NOTES="$NOTES Tag sur ${TARGET::7}, pointe de $BRANCH : memes sources que ${SHA::7} (seuls des fichiers hors ROM ont change)."
		echo "build commit ${SHA::7}, workflows changed since on $BRANCH (files not in the ROM only): tag on ${TARGET::7}"
	else
		echo "::error::workflows of $BRANCH changed since ${SHA::7} together with other files ($(tr '\n' ' ' <<<"$CHANGED")): the workflow token cannot tag ${SHA::7}. Build again from the tip of $BRANCH."
		exit 1
	fi
fi

publish() {
	if gh release view "$TAG" --repo "$R" >/dev/null 2>&1; then
		gh release upload "$TAG" "${FILES[@]}" --clobber --repo "$R"
	else
		gh release create "$TAG" "${FILES[@]}" --repo "$R" --target "$TARGET" --prerelease --title "$TITLE" --notes "$NOTES"
	fi
}
retry publish

printf '{"response":[{"datetime":%s,"filename":"%s","id":"%s","romtype":"%s","size":%s,"url":"%s","version":"%s"}]}\n' \
	"$DT" "$Z" "$(sha256sum "$Z" | cut -d' ' -f1)" "${TYPE:-UNOFFICIAL}" "$(stat -c %s "$Z")" \
	"https://github.com/$R/releases/download/$TAG/$Z" "$VER" > updater.json
cat updater.json
feed() {
	gh release view "lineage-$VERSION-ota" --repo "$R" >/dev/null 2>&1 || \
		gh release create "lineage-$VERSION-ota" --repo "$R" --target "$TARGET" --prerelease --title "$OTA_TITLE" \
			--notes "updater.json lu par l'appli Mises a jour de LineageOS (overlay de packages/apps/Updater) ; remplace a chaque build."
	gh release upload "lineage-$VERSION-ota" updater.json --clobber --repo "$R"
}
retry feed
echo "published: https://github.com/$R/releases/tag/$TAG"
