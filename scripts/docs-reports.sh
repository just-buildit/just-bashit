#!/usr/bin/env bash
#
# docs-reports.sh -- which CI run's reports does deploy-docs publish?
#
# The docs site carries two pages built from a CI run's artifacts: the test
# report (artifact `test-report-xml`, rendered by junit2html into
# /test-report/) and the coverage report (artifact `coverage-report`: the
# /coverage/ page and the coverage-badge.json the README badge reads). Both
# are uploaded by the matrix run only.
#
# When this push ran the matrix, its own reports are the ones. When the
# matrix was skipped (the tree was already tested as a PR, or the commit is a
# pure version bump) the reports come from, in order:
#
#   1. the merged PR's head run, if it ran the matrix and kept the artifacts;
#   2. else the most recent successful `main` run that has both artifacts
#      unexpired. A release PR is a pure version bump, so its own run took
#      the fast path too and has nothing to offer (gh-151).
#
# Finding NO run is not a failure: a missing report must never block
# publishing the docs or the Pages mirror refresh. It emits `run-id=` (empty)
# and a ::warning:: the downstream steps key on. An API error IS a failure:
# a report we could not look for is not a report that does not exist.
#
# Usage:  docs-reports.sh
# Env:    GITHUB_REPOSITORY  owner/repo
#         GITHUB_SHA         the pushed commit
#         GITHUB_RUN_ID      this run
#         TESTED             `success` when this run's matrix ran
#         GH                 the gh binary (default `gh`; tests fake it)
#         DOCS_REPORTS_SCAN  how many recent main runs to search (default 30)
#         GITHUB_OUTPUT      `run-id=...` is appended to it when set
set -uo pipefail

gh="${GH:-gh}"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
sha="${GITHUB_SHA:-}"
scan="${DOCS_REPORTS_SCAN:-30}"

emit() {
	echo "run-id=$1"
	if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "run-id=$1" >>"$GITHUB_OUTPUT"; fi
}

# has_reports RUN -- 0 when RUN holds both unexpired artifacts, 1 when not,
# 2 on an API error.
has_reports() {
	local n
	n="$("$gh" api "repos/$repo/actions/runs/$1/artifacts" --paginate --jq \
		'[.artifacts[] | select(.expired == false)
          | select(.name == "test-report-xml" or .name == "coverage-report")
          | .name] | unique | length')" || return 2
	[ "$n" = 2 ]
}

if [ "${TESTED:-}" = success ]; then
	emit "${GITHUB_RUN_ID:?GITHUB_RUN_ID is required}"
	exit 0
fi

pr_run=""
candidates=""
head="$("$gh" api "repos/$repo/commits/$sha/pulls" \
	--jq '[.[] | select(.merged_at != null)][0].head.sha // empty')" || {
	echo "::error::cannot list the PRs for $sha"
	exit 1
}
if [ -n "$head" ]; then
	pr_run="$("$gh" run list -R "$repo" --workflow ci.yml --commit "$head" \
		--status success --json databaseId \
		--jq '.[0].databaseId // empty')" || {
		echo "::error::cannot list the CI runs for PR head $head"
		exit 1
	}
	candidates="$pr_run"
fi
main_runs="$("$gh" run list -R "$repo" --workflow ci.yml --branch main \
	--status success --limit "$scan" --json databaseId \
	--jq '.[].databaseId')" || {
	echo "::error::cannot list recent main CI runs"
	exit 1
}
candidates="$candidates $main_runs"

for run in $candidates; do
	has_reports "$run"
	rc=$?
	case "$rc" in
	0)
		if [ "$run" = "$pr_run" ]; then
			echo "reports from the merged PR's head $head, run $run"
		else
			echo "the PR's own run kept no reports (a version bump" \
				"skips the matrix); reusing the most recent main run" \
				"that has them: $run"
		fi
		emit "$run"
		exit 0
		;;
	2)
		echo "::error::cannot list the artifacts of run $run"
		exit 1
		;;
	esac
done

echo "::warning::no CI run among the PR's and the last $scan successful" \
	"main runs has test-report-xml and coverage-report; deploying the" \
	"docs WITHOUT the test and coverage reports"
emit ""
