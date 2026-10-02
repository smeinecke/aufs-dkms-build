#!/usr/bin/env bash
# Compare upstream aufs-standalone branch heads against the last built state
# (.github/upstream-state.json) and dispatch a build-full run for every
# flavor whose module source moved. Also follows newer point branches
# (e.g. aufs5.10.140 -> aufs5.10.141) within each series and reports
# completely new upstream series as a tracking issue.
#
# Rebuild releases use VERSION_TAG "<branch-tag>+<yyyymmdd>" so the debian
# version stays ordered even when the same upstream branch is rebuilt.
set -euo pipefail

STATE=".github/upstream-state.json"
DATE="$(date -u +%Y%m%d)"

# upstream split the standalone tree into per-major-version repositories
repo_for() {
    case "$1" in
        4) echo "https://github.com/sfjro/aufs4-standalone" ;;
        *) echo "https://github.com/sfjro/aufs-standalone" ;;
    esac
}

# version-ish compare: true if $1 is numerically newer than $2
newer() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n | tail -1)" = "$1" ] && [ "$1" != "$2" ]; }

state_tag() { jq -r --arg f "$1" '.[$f].tag' "${STATE}"; }
state_sha() { jq -r --arg f "$1" '.[$f].sha' "${STATE}"; }
save_state() {
    jq --arg f "$1" --arg t "$2" --arg s "$3" '.[$f] = {tag: $t, sha: $s}' \
        "${STATE}" > "${STATE}.new" && mv "${STATE}.new" "${STATE}"
}

changed=0
for flavor in buster bullseye bookworm trixie; do
    tag="$(state_tag "${flavor}")"
    sha="$(state_sha "${flavor}")"
    series="$(cut -d. -f1-2 <<<"${tag}")"
    repo="$(repo_for "${series%%.*}")"

    # upstream adds point branches when a stable kernel breaks the API;
    # follow the newest one within our series
    new_point="$(git ls-remote "${repo}" "refs/heads/aufs${series}.*" \
        | sed -n "s|.*refs/heads/aufs${series}\.\([0-9]*\)\$|\1|p" \
        | sort -n | tail -1)"
    cur_point="$(cut -d. -f3 -s <<<"${tag}")"
    if [ -n "${new_point}" ] && [ "${cur_point:-0}" -lt "${new_point}" ]; then
        echo "${flavor}: newer upstream point branch aufs${series}.${new_point} (was aufs${tag})"
        tag="${series}.${new_point}"
    fi

    head="$(git ls-remote "${repo}" "refs/heads/aufs${tag}" | cut -f1)"
    if [ -z "${head}" ]; then
        echo "::warning::${flavor}: upstream branch aufs${tag} not found in ${repo}"
        continue
    fi

    if [ "${head}" = "${sha}" ] && [ "${tag}" = "$(state_tag "${flavor}")" ]; then
        echo "${flavor}: aufs${tag} unchanged"
        continue
    fi

    # same branch moved -> rebuild release with date suffix; a point-branch
    # bump is a new upstream version and needs no suffix
    reltag="${tag}"
    [ "${tag}" = "$(state_tag "${flavor}")" ] && reltag="${tag}+${DATE}"
    echo "${flavor}: upstream changed -> dispatching release ${reltag}"
    gh workflow run build-full.yml -f version_tag="${reltag}"
    save_state "${flavor}" "${tag}" "${head}"
    changed=1
done

# report the newest upstream series when it is newer than anything we ship
newest="$(git ls-remote https://github.com/sfjro/aufs-standalone 'refs/heads/aufs[0-9]*.[0-9]*' \
    | sed -n 's|.*refs/heads/aufs\([0-9]*\.[0-9]*\)$|\1|p' | sort -t. -k1,1n -k2,2n | tail -1)"
max_known="$(jq -r '.notified_series' "${STATE}")"
if [ -n "${newest}" ] && newer "${newest}" "${max_known}"; then
    echo "new upstream series aufs${newest} (tracked max: ${max_known})"
    gh issue create \
        --title "New upstream aufs series: aufs${newest}" \
        --body "Upstream sfjro/aufs-standalone now has branch \`aufs${newest}\`, newer than the newest packaged series (\`${max_known}\`).

A future Debian release (e.g. forky) will ship a kernel in this series. To support it: add a matrix entry, a matching \`scripts/kernel/${newest}/\` patch set, and push a \`${newest}\` tag." \
        || echo "::warning::could not create tracking issue"
    jq --arg s "${newest}" '.notified_series = $s' "${STATE}" > "${STATE}.new" && mv "${STATE}.new" "${STATE}"
    changed=1
fi

if [ "${changed}" -eq 1 ]; then
    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    git add "${STATE}"
    git diff --cached --quiet || {
        git commit -m "chore: update upstream aufs heads"
        git push
    }
fi
