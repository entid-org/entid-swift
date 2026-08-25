#!/usr/bin/env bash
# `engine.md` section 11.4: the engine fetches the release, the release does not
# push into the engine.
#
#   compare [tag]              prints tag=, version= and sync= as key=value lines
#   sync <tag> <version>       downloads, verifies, and only then writes
#   pull-request <tag> <version> <verify-outcome>
#
# The order of `sync` is the order section 11.4 fixes: the SHA-256 sums, then
# the provenance attestation, and only then anything on disk. Everything is
# assembled in a temporary directory and copied into the working tree in one
# move at the very end, so a release whose attestation does not verify never
# touches it.
set -euo pipefail
cd "$(dirname "$0")/.."

SPEC_REPO="entid-org/spec"
SIGNER_WORKFLOW=".github/workflows/release.yml"
# The job of `.github/workflows/ci.yml` that runs the section 12.6 entry point.
# Auto-merge follows the required checks of the branch, so this name is what
# makes "merged" mean "make verify passed".
REQUIRED_CHECK="Verify"

die() { printf 'rules-sync: %s\n' "$*" >&2; exit 1; }

# Global, not a local of cmd_sync: an EXIT trap runs after the function has
# returned, and a `local` is out of scope by then -- which under `set -u` made
# the trap itself fail and turned a successful synchronization into exit 1.
WORK=""
trap 'rm -rf "${WORK}"' EXIT

lock() { sed -n "s/^$1 = \"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" rules.lock; }

# The tag of the newest published release.
#
# Not /releases/latest: the release workflow marks every non-stable bundle as a
# pre-release precisely so it stays out of that endpoint, and every release
# published so far is alpha. That endpoint answers 404 for this repository, so
# an engine that asked it would conclude there is nothing to synchronize and
# would say so every day, forever. The list is sorted here rather than trusted
# to arrive in order.
latest_tag() {
  gh api "repos/${SPEC_REPO}/releases?per_page=100" \
    --jq '[.[] | select(.draft == false)] | sort_by(.published_at) | last | .tag_name'
}

# The rules version of a release, read from the name of its manifest asset. The
# release title carries it too, in prose; the asset name is the machine's copy.
release_version() {
  gh api "repos/${SPEC_REPO}/releases/tags/$1" \
    --jq '.assets[].name | select(startswith("entid-manifest-") and endswith(".json"))' \
    | sed -e 's/^entid-manifest-//' -e 's/\.json$//' | head -1
}

cmd_compare() {
  local tag="${1:-}" forced="false" version locked_version locked_tag sync

  if [ -n "${tag}" ]; then
    # A tag named by hand is an instruction, not a question: it synchronizes
    # that release whether or not the lock already names it. That is also the
    # only way to exercise the whole path without waiting for a release.
    forced="true"
  else
    tag="$(latest_tag)"
  fi
  [ -n "${tag}" ] || die "no published release in ${SPEC_REPO}"

  version="$(release_version "${tag}")"
  [ -n "${version}" ] || die "release ${tag} publishes no entid-manifest-*.json"

  locked_version="$(lock rules_version)"
  locked_tag="$(lock attestation_identity | sed -n 's|.*@refs/tags/||p')"

  # An empty locked tag is a lock that was produced locally rather than from an
  # attested release. It never concords: it has to be replaced by an attested
  # one.
  if [ "${forced}" = "false" ] \
     && [ "${version}" = "${locked_version}" ] \
     && [ -n "${locked_tag}" ] && [ "${tag}" = "${locked_tag}" ]; then
    sync="false"
  else
    sync="true"
  fi

  printf 'tag=%s\n' "${tag}"
  printf 'version=%s\n' "${version}"
  printf 'sync=%s\n' "${sync}"
  printf 'rules-sync: release %s carries %s, rules.lock carries %s from %s, sync=%s\n' \
    "${tag}" "${version}" "${locked_version}" "${locked_tag:-a local build}" "${sync}" >&2
}

cmd_sync() {
  local tag="$1" version="$2"
  local work art staged manifest commit subject schema package

  WORK="$(mktemp -d)"
  work="${WORK}"
  art="${work}/artifacts"
  staged="${work}/staged"

  # 1. the artefacts
  gh release download "${tag}" --repo "${SPEC_REPO}" --dir "${art}"

  # 2. the sums, then the attestation.
  #
  # shasum and not sha256sum: this runs on macOS, where coreutils is not
  # installed and sha256sum does not exist. --strict so a checksum line that
  # cannot be parsed is a failure rather than a skipped file.
  ( cd "${art}" && shasum -a 256 --check --strict SHA256SUMS >/dev/null )
  echo "rules-sync: SHA256SUMS checks out"

  # SHA256SUMS is attested as well as the bundle, and it is what carries the
  # schemas, ir.md, features.md and the JSONL: attesting the three big files
  # alone would leave those covered by an unsigned list.
  #
  # --repo and not --owner: they are mutually exclusive, and passing both makes
  # gh refuse the arguments before verifying anything.
  for subject in \
    "SHA256SUMS" \
    "entid-manifest-${version}.json" \
    "entid-rules-${version}.binpb" \
    "entid-conformance-${version}.binpb"
  do
    gh attestation verify "${art}/${subject}" \
      --repo "${SPEC_REPO}" \
      --signer-workflow "${SPEC_REPO}/${SIGNER_WORKFLOW}" \
      --source-ref "refs/tags/${tag}"
    echo "rules-sync: attested ${subject}"
  done

  manifest="${art}/entid-manifest-${version}.json"
  [ "$(jq -r .rulesVersion "${manifest}")" = "${version}" ] \
    || die "the manifest declares $(jq -r .rulesVersion "${manifest}"), not ${version}"
  commit="$(jq -r .sourceCommit "${manifest}")"

  # 3. spec/, rules.lock and spec/PROVENANCE.md, staged first.
  mkdir -p "${staged}/spec"
  cp "${art}/entid-rules-${version}.binpb"       "${staged}/spec/entid-rules.binpb"
  cp "${art}/entid-conformance-${version}.binpb" "${staged}/spec/entid-conformance.binpb"
  # Shipped decompressed, which is why rules.lock takes that digest on the file
  # that lands here and not on the archive.
  gzip -dc "${art}/entid-conformance-${version}.jsonl.gz" \
    > "${staged}/spec/entid-conformance.jsonl"
  # The prose contracts travel with the release since spec#87, and section 11.4
  # step 3 names them: an engine that fetched only the data would keep a stale
  # contract and not notice, because nothing digests them. Nothing in rules.lock
  # names their digest either -- what attests them is SHA256SUMS, whose own
  # attestation was verified above.
  for schema in rules.proto conformance.proto testee.proto ir.md features.md \
                spec.md engine.md engine-swift.md; do
    cp "${art}/${schema}" "${staged}/spec/${schema}"
  done

  # The provenance note travels with the release since 2026.08.38, assembled,
  # one per engine. It still has exactly one writer -- two writers drifted once,
  # and a released engine named one commit in its header and another in its lock
  # (spec#84) -- but that writer now runs in the release rather than here, so a
  # workflow that has verified a release no longer clones the specification
  # repository to write the last file of its synchronization. Measured before
  # the clone was removed: on v2026.08.38 the two paths produce the same bytes.
  cp "${art}/provenance-swift.md" "${staged}/spec/PROVENANCE.md"

  # The generator compiles against copies under proto/, which protoc needs in a
  # package shaped tree. The directory is the package the attested schema
  # declares, and not a literal written here: the package moved from
  # `libbusinessid.*` to `entid.*` in 2026.08.38 while the copies stayed where
  # they were, and verify-lock refused the release at the end of a
  # synchronization that had passed every digest and every attestation.
  for schema in rules.proto conformance.proto testee.proto; do
    package="$(sed -n 's/^package \(.*\);$/\1/p' "${art}/${schema}" | tr . /)"
    [ -n "${package}" ] || die "${schema} declares no package"
    mkdir -p "${staged}/proto/${package}"
    cp "${art}/${schema}" "${staged}/proto/${package}/${schema}"
  done

  # Every field read from the attested manifest, in the order the released
  # rules.lock already uses, so a synchronization that changes nothing produces
  # the same bytes.
  {
    printf 'rules_version = "%s"\n' "$(jq -r .rulesVersion "${manifest}")"
    printf 'format_version = %s\n' "$(jq -r .formatVersion "${manifest}")"
    printf 'rules_sha256 = "%s"\n' "$(jq -r .artifactSha256 "${manifest}")"
    printf 'conformance_sha256 = "%s"\n' "$(jq -r .conformanceSha256 "${manifest}")"
    printf 'conformance_jsonl_sha256 = "%s"\n' "$(jq -r .conformanceJsonlSha256 "${manifest}")"
    printf 'rules_proto_sha256 = "%s"\n' "$(jq -r .rulesProtoSha256 "${manifest}")"
    printf 'conformance_proto_sha256 = "%s"\n' "$(jq -r .conformanceProtoSha256 "${manifest}")"
    printf 'testee_proto_sha256 = "%s"\n' "$(jq -r .testeeProtoSha256 "${manifest}")"
    printf 'ir_doc_sha256 = "%s"\n' "$(jq -r .irDocSha256 "${manifest}")"
    printf 'features_doc_sha256 = "%s"\n' "$(jq -r .featuresDocSha256 "${manifest}")"
    printf 'stability = "%s"\n' "$(jq -r .stability "${manifest}")"
    printf 'source_commit = "%s"\n' "${commit}"
    printf 'attestation_identity = "%s/%s@refs/tags/%s"\n' \
      "${SPEC_REPO}" "${SIGNER_WORKFLOW}" "${tag}"
  } > "${staged}/rules.lock"

  cp "${staged}/rules.lock" rules.lock
  cp -R "${staged}/spec/." spec/
  # Replaced and not merged: a package rename leaves the old tree in place, and
  # `protoc -I proto` would then compile two copies of the same schema.
  rm -rf proto
  cp -R "${staged}/proto" proto

  # What was just written must match what was just attested. `make verify` runs
  # this too; running it here means a bad copy is caught by the step that made
  # it rather than four steps later.
  ./Tools/verify-lock.sh
  echo "rules-sync: wrote rules ${version} from ${tag} (${commit})"
}

cmd_pull_request() {
  local tag="$1" version="$2" outcome="$3"
  local branch="rules/${version}" url state body contexts repo failure verdict
  # Exactly what a synchronization is allowed to change: the release under
  # spec/, the copies of its schemas under proto/, the lock that attests them,
  # and the code emitted from the bundle. Not `add -A`, which would sweep in
  # whatever `swift package resolve` touched on the way through.
  local -a paths=(spec proto rules.lock Sources/EntID/Generated)

  if [ -z "$(git status --porcelain -- "${paths[@]}")" ]; then
    echo "rules-sync: ${version} changes nothing here; no pull request to open"
    return 0
  fi

  git switch -c "${branch}"
  git add -- "${paths[@]}"
  git -c user.name="github-actions[bot]" \
      -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
      commit -q -m "chore(rules): update to ${version}"

  # A re-run after a fixed defect replaces its own branch rather than being
  # refused as non fast forward. --force-with-lease needs its expected value
  # spelled out: a shallow checkout cannot establish the history relationship a
  # bare lease needs and refuses with "stale info", and a bare fetch leaves the
  # lease nothing to read, so the refspec writes a remote-tracking ref first.
  if git ls-remote --exit-code --heads origin "${branch}" >/dev/null 2>&1; then
    git fetch --depth 1 origin "+${branch}:refs/remotes/origin/${branch}"
    git push "--force-with-lease=${branch}:$(git rev-parse "refs/remotes/origin/${branch}")" \
      --set-upstream origin "${branch}"
  else
    git push --set-upstream origin "${branch}"
  fi

  repo="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"

  # The verdict of the section 12.6 entry point, published as a commit status
  # under the name the branch protection requires.
  #
  # A pull request opened with a repository's own GITHUB_TOKEN starts no
  # `pull_request` workflow -- GitHub cuts there so an action cannot call itself
  # in a loop -- so the check the protection waits for would never start, and
  # auto-merge would wait forever. This workflow has already run the entry point;
  # publishing its result is not a second definition of green, it is the same one
  # under the expected name. A repository writes its own statuses, so this needs
  # no wider token than the one already in hand.
  if [ "${outcome}" = "success" ]; then verdict="success"; else verdict="failure"; fi
  gh api -X POST "repos/${repo}/statuses/$(git rev-parse HEAD)" \
    -f "state=${verdict}" \
    -f "context=${REQUIRED_CHECK}" \
    -f "description=make verify on the synchronization runner" \
    -f "target_url=${GITHUB_SERVER_URL:-https://github.com}/${repo}/actions/runs/${GITHUB_RUN_ID:-0}" \
    --silent
  echo "rules-sync: published ${REQUIRED_CHECK} = ${verdict} on $(git rev-parse --short HEAD)"

  if [ "${outcome}" = "success" ]; then
    state="\`make verify\` passed on the runner that wrote this, and is published on the
head commit as the \`${REQUIRED_CHECK}\` status."
  else
    state="\`make verify\` **failed** on the runner that wrote this. Section 11.4: a red
pull request is not merged to unblock the chain. It is fixed, or the release is
refused with the reason written down."
  fi

body="$(cat <<BODY
Automated synchronization of the EntID rules, \`engine.md\` section 11.4.

- rules version: \`${version}\`
- source release: [\`${tag}\`](https://github.com/${SPEC_REPO}/releases/tag/${tag})
- verified before anything was written: \`SHA256SUMS\`, then the provenance
  attestation of \`SHA256SUMS\`, the manifest, the bundle and the corpus —
  repository, signing workflow and tag
- the emitted code was regenerated from the new bundle by this workflow

${state}

This automation opens the pull request and enables auto-merge. It cannot approve
it, and auto-merge only merges once the \`${REQUIRED_CHECK}\` status on the head
commit is green.
BODY
)"

  # A re-run pushes over its own branch, and the pull request it already opened
  # is still there: creating a second one is refused, and that refusal would be
  # reported below as the permission problem it is not.
  url="$(gh pr list --head "${branch}" --state open --json url -q '.[0].url')"
  if [ -n "${url}" ]; then
    echo "rules-sync: ${branch} already has a pull request open"
  else
    # --head and --base explicitly: gh otherwise infers them from the checkout,
    # and has refused with "you must first push the current branch to a remote"
    # on a branch it had just pushed.
    url="$(gh pr create --head "${branch}" --base main \
      --title "chore(rules): update to ${version}" --body "${body}")" || die \
"could not open the pull request. If gh reports that GitHub Actions is not permitted
to create pull requests, it is \"Allow GitHub Actions to create and approve pull
requests\", under Actions > General > Workflow permissions -- for the organization
first, since the repository box is refused while the organization forbids it, and
for the repository second. GITHUB_TOKEN cannot set either: there is no repository
administration permission for a workflow to request. The branch ${branch} is
pushed, so a re-run picks it up."
  fi
  echo "rules-sync: ${url}"

  # Auto-merge merges as soon as nothing *blocks* the pull request, which is not
  # the same as merging on green: without a required check on main it would
  # merge this one immediately, red or not. That check must also be the only
  # required one, or "green" has two definitions and auto-merge follows the
  # weaker.
  # Whether main is protected at all is readable with the token in hand -- it is
  # a field of the branch object. Which checks it requires is not: there is no
  # `administration` permission for a workflow to request, so that read is
  # attempted and its refusal reported rather than treated as an answer.
  [ "$(gh api "repos/${repo}/branches/main" --jq .protected)" = "true" ] || die \
"main is not protected, so auto-merge would merge this pull request at once, green
or red. Require exactly [${REQUIRED_CHECK}] on main first. The pull request is open
at ${url}."

  failure="$(mktemp)"
  if contexts="$(gh api "repos/${repo}/branches/main/protection/required_status_checks" \
       --jq '[.checks[].context] | sort | join(",")' 2>"${failure}")"; then
    [ "${contexts}" = "${REQUIRED_CHECK}" ] || die \
"main requires [${contexts:-nothing}] but auto-merge is only safe when the section 12.6
entry point is the one required check. Set the required status checks of main to
exactly [${REQUIRED_CHECK}]. The pull request is open at ${url}."
    echo "rules-sync: main requires ${contexts}, and nothing else"
  elif grep -qiE 'not protected|not enabled' "${failure}"; then
    # Protected, but requiring nothing to pass. Auto-merge would merge the moment
    # the pull request is mergeable, which is at once.
    die \
"main requires no status check, so auto-merge would merge this pull request at once,
green or red. Require exactly [${REQUIRED_CHECK}] on main first. The pull request is
open at ${url}."
  else
    echo "rules-sync: could not read main's branch protection ($(tr -d '\n' < "${failure}"))." \
         "Auto-merge is only safe if [${REQUIRED_CHECK}] is the one required check there."
  fi
  rm -f "${failure}"

  # Squash: the history of this repository is one commit per merged pull request.
  gh pr merge "${url}" --auto --squash || die \
"could not enable auto-merge on ${url}.
If gh reports that auto-merge is not allowed: Settings > General > Pull Requests >
\"Allow auto-merge\". GITHUB_TOKEN cannot set it; there is no repository
administration permission for it to request. A human has to click it once."
  echo "rules-sync: auto-merge enabled on ${url}"
}

case "${1:-}" in
  compare)      shift; cmd_compare "$@" ;;
  sync)         shift; cmd_sync "$@" ;;
  pull-request) shift; cmd_pull_request "$@" ;;
  *) die "usage: rules-sync.sh compare [tag] | sync <tag> <version> | pull-request <tag> <version> <outcome>" ;;
esac
