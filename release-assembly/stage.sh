#!/bin/bash
set -euo pipefail
# An explicitly dispatched job operates only on the pending v0.1.7 draft.
repo=Lee-xeo/Claude-Cage
tag=v0.1.7
[[ "$SOURCE" =~ ^[a-f0-9]{40}$ && "$WIN_RUN" =~ ^[0-9]+$ && "$LINUX_RUN" =~ ^[0-9]+$ ]]
test "$SOURCE" = "5c24a6fc658153269cabf5c9773e72c36df87721"
test "$WIN_RUN" = 43027324230
test "$LINUX_RUN" = 43027324230
test "$(git rev-parse HEAD)" = "$SOURCE"
test "$(cat VERSION)" = '0.1.7'
work=$(mktemp -d)
gh api "repos/$repo/releases/441640942" > "$work/draft.json"
jq -e --arg h "$SOURCE" '.tag_name=="v0.1.7" and .draft and (.prerelease|not) and .target_commitish==$h' "$work/draft.json" >/dev/null
mkdir "$work/mac"
for platform in windows linux; do
  run=$WIN_RUN
  if [[ $platform = linux ]]; then run=$LINUX_RUN; fi
  gh run download "$run" -R "$repo" -n "release-$platform" -D "$work/$platform"
  meta=$(find "$work/$platform" -name build-metadata.json)
  test -f "$meta"
  jq -e --arg p "$platform" --arg h "$SOURCE" '.schema==1 and .platform==$p and .version=="0.1.7" and .commitSha==$h' "$meta" >/dev/null
  realpath "$(dirname "$meta")" > "$work/$platform.dir"
done
cp "$HELPER/macos.SHA256SUMS" "$work/mac/SHA256SUMS"
while read -r digest file; do
  [[ $digest =~ ^[a-f0-9]{64}$ && $file =~ ^[A-Za-z0-9._-]+$ ]]
  gh release download "$tag" -R "$repo" -p "$file" -D "$work/mac"
done < "$work/mac/SHA256SUMS"
(cd "$work/mac"; sha256sum -c SHA256SUMS)
node scripts/prepare-release-assets.mjs --output "$work/assets" "$work/mac" "$(cat "$work/windows.dir")" "$(cat "$work/linux.dir")"
apk=Cage-0.1.7-android-arm64.apk
gh release download "$tag" -R "$repo" -p "$apk" -D "$work/assets"
(cd "$work/assets"; sha256sum -c "$HELPER/android.SHA256SUMS"; cat "$HELPER/android.SHA256SUMS" >> SHA256SUMS; sort -k 2 SHA256SUMS -o SHA256SUMS; sha256sum -c SHA256SUMS)
for path in "$work/assets/"*; do
  name=${path##*/}
  expected="sha256:$(sha256sum "$path" | cut -d' ' -f1)"
  prior=$(jq -r --arg n "$name" '.assets[]|select(.name==$n)|.digest' "$work/draft.json")
  if [[ -n $prior ]]; then test "$prior" = "$expected"; else gh release upload "$tag" "$path" -R "$repo"; fi
done
gh api "repos/$repo/releases/441640942" > "$work/final.json"
test "$(jq '.assets|length' "$work/final.json")" = 11
for path in "$work/assets/"*; do
  sha="sha256:$(sha256sum "$path" | cut -d' ' -f1)"
  jq -e --arg n "${path##*/}" --arg sha "$sha" --argjson size "$(stat --format=%s "$path")" '.assets[]|select(.name==$n and .digest==$sha and .size==$size and .state=="uploaded")' "$work/final.json" >/dev/null
done
cat "$work/assets/SHA256SUMS"
