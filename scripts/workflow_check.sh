#!/usr/bin/env bash
# ############################################################################
# workflow_check.sh — repo gate, not a shipped library.                      #
# ############################################################################
# gates-home-check asks whether every gate in GATES_DEPS is reached by some   #
# CI target. This asks the question one level up, of the workflow itself:     #
#                                                                            #
#   1. Every artifact a job DOWNLOADS is uploaded by a job that job WAITS     #
#      for. deploy-docs downloaded test-report-xml while declaring only       #
#      `needs: [coverage, lint]`, so it consumed an artifact from a job it    #
#      never waited for. It worked only because the test job happened to      #
#      finish first, and stopped the moment the container jobs began          #
#      installing from bootstrap.toml and grew slower. main went red on two   #
#      commits whose pull requests were both green.                          #
#                                                                            #
#   2. Every artifact a job downloads is uploaded by SOMETHING. A renamed     #
#      upload leaves the download asking for a name nobody produces, which    #
#      fails the same way and reads the same in the log.                     #
#                                                                            #
#   3. A job with no pre-merge run is DECLARED. deploy-docs is gated on       #
#      refs/heads/main, so it is skipped on every pull request and can only   #
#      fail after a merge -- there is no arrangement of `needs` that fixes    #
#      that, which is exactly why adding another such job should be a         #
#      decision that shows up in a diff rather than a discovery. The list     #
#      may only shrink; a stale entry fails too, so it cannot quietly         #
#      describe a job that has since gained a pre-merge run.                 #
#                                                                            #
# Parsing is deliberately shallow and stdlib-only: awk over the keys this     #
# needs, not a YAML library, because the gate has to run in the same          #
# containers as the suite and those carry no Python. A parser that reads      #
# nothing would pass everything, so finding no jobs, no uploads or no         #
# downloads is an ERROR rather than a clean bill of health.                  #
# ############################################################################

set -uo pipefail

cd "${WORKFLOW_CHECK_ROOT:-$(dirname "${BASH_SOURCE[0]}")/..}" || exit 1

WF_DIR=".github/workflows"
ALLOW_FILE=".github/no-pre-merge-run"

rc=0
total_jobs=0
total_up=0
total_down=0

# ---------------------------------------------------------------------------
# Extract the shape of one workflow: one record per line, so the shell side
# needs no second parser.
#
#   job<TAB>NAME
#   needs<TAB>NAME<TAB>DEP
#   up<TAB>NAME<TAB>ARTIFACT
#   down<TAB>NAME<TAB>ARTIFACT
#   mainonly<TAB>NAME
# ---------------------------------------------------------------------------
_shape() {
	awk '
		function trim(x) { gsub(/^[ \t]+|[ \t\r]+$/, "", x); return x }

		/^jobs:[ \t]*$/ { injobs = 1; next }
		# A top-level key other than jobs: ends the jobs block.
		/^[^ \t#]/ && !/^jobs:/ { injobs = 0 }
		!injobs { next }

		# Two-space indent under jobs: is a job name.
		/^  [A-Za-z0-9_-]+:[ \t]*$/ {
			job = trim($0); sub(/:$/, "", job)
			print "job\t" job
			pending_art = 0
			next
		}
		job == "" { next }

		# needs: inline list, single scalar, or a block of "- dep" lines.
		/^    needs:/ {
			v = $0; sub(/^    needs:[ \t]*/, "", v); v = trim(v)
			inneeds = 0
            if (v == "") { inneeds = 1; next }
			gsub(/[][]/, "", v); gsub(/,/, " ", v)
			n = split(v, parts, /[ \t]+/)
			for (i = 1; i <= n; i++)
				if (parts[i] != "") print "needs\t" job "\t" parts[i]
			next
		}
		inneeds && /^      *- / {
			v = $0; sub(/^[ \t]*-[ \t]*/, "", v)
			print "needs\t" job "\t" trim(v)
			next
		}
		inneeds && /^    [A-Za-z]/ { inneeds = 0 }

		# `if:` mentioning the default branch means no pull-request run.
		/^    if:/ && /refs\/heads\/main/ { print "mainonly\t" job; next }

		/uses:.*upload-artifact/ { pending_art = 1; kind = "up";   next }
		/uses:.*download-artifact/ { pending_art = 1; kind = "down"; next }

		# The first `name:` after such a `uses:` is the artifact name. Step
		# names come BEFORE their uses:, so this cannot capture one.
		pending_art && /^[ \t]+name:[ \t]*/ {
			v = $0; sub(/^[ \t]*name:[ \t]*/, "", v)
			print kind "\t" job "\t" trim(v)
			pending_art = 0
			next
		}
		# A new step ends the window without a name (e.g. a matrix upload
		# using the default artifact name).
		pending_art && /^[ \t]*- / { pending_art = 0 }
	' "$1"
}

# Depth-first closure over needs, so a transitive wait counts.
_reaches() {
	local wf="$1" from="$2" target="$3" dep
	for dep in $(printf '%s\n' "${wf}" |
		awk -F'\t' -v j="${from}" '$1=="needs" && $2==j { print $3 }'); do
		[[ "${dep}" == "${target}" ]] && return 0
		_reaches "${wf}" "${dep}" "${target}" && return 0
	done
	return 1
}

declare -a declared=()
if [[ -f "${ALLOW_FILE}" ]]; then
	while IFS= read -r line; do
		line="${line%%#*}"
		line="${line// /}"
		[[ -n "${line}" ]] && declared+=("${line}")
	done <"${ALLOW_FILE}"
fi

seen_mainonly=()

for wf_path in "${WF_DIR}"/*.yml; do
	[[ -f "${wf_path}" ]] || continue
	wf="$(_shape "${wf_path}")"
	name="${wf_path##*/}"

	njob=$(printf '%s\n' "${wf}" | awk -F'\t' '$1=="job"' | grep -c . || true)
	total_jobs=$((total_jobs + njob))

	while IFS=$'\t' read -r kind consumer artifact; do
		[[ "${kind}" == "down" ]] || continue
		total_down=$((total_down + 1))

		producers=$(printf '%s\n' "${wf}" |
			awk -F'\t' -v a="${artifact}" '$1=="up" && $3==a { print $2 }')
		if [[ -z "${producers}" ]]; then
			echo "ERROR: ${name}: job '${consumer}' downloads '${artifact}',"
			echo "  which no job in this workflow uploads. A renamed upload"
			echo "  fails exactly like a race and reads the same in the log."
			rc=1
			continue
		fi
		while IFS= read -r producer; do
			[[ -n "${producer}" ]] || continue
			if ! _reaches "${wf}" "${consumer}" "${producer}"; then
				echo "ERROR: ${name}: job '${consumer}' downloads '${artifact}'"
				echo "  from '${producer}', which is not in its needs closure."
				echo "  Nothing makes it wait, so this passes or fails on"
				echo "  timing. Add '${producer}' to ${consumer}'s needs."
				rc=1
			fi
		done <<<"${producers}"
	done < <(printf '%s\n' "${wf}" | awk -F'\t' '$1=="down"')

	total_up=$((total_up + $(printf '%s\n' "${wf}" |
		awk -F'\t' '$1=="up"' | grep -c . || true)))

	while IFS=$'\t' read -r _ job; do
		[[ -n "${job}" ]] || continue
		seen_mainonly+=("${job}")
		found=0
		for d in ${declared[@]+"${declared[@]}"}; do
			[[ "${d}" == "${job}" ]] && found=1
		done
		if [[ ${found} -eq 0 ]]; then
			echo "ERROR: ${name}: job '${job}' runs only on the default branch,"
			echo "  so no pull request ever exercises it and it can only fail"
			echo "  after a merge. If that is intended, add it to"
			echo "  ${ALLOW_FILE} with a reason."
			rc=1
		fi
	done < <(printf '%s\n' "${wf}" | awk -F'\t' '$1=="mainonly"')
done

# A stale declaration must not quietly describe a fixed problem.
for d in ${declared[@]+"${declared[@]}"}; do
	found=0
	for j in ${seen_mainonly[@]+"${seen_mainonly[@]}"}; do
		[[ "${d}" == "${j}" ]] && found=1
	done
	if [[ ${found} -eq 0 ]]; then
		echo "ERROR: ${ALLOW_FILE} lists '${d}', which no longer runs only on"
		echo "  the default branch. The list may only shrink — remove it."
		rc=1
	fi
done

# A parser that reads nothing would pass everything.
if ((total_jobs == 0 || total_up == 0 || total_down == 0)); then
	echo "ERROR: parsed ${total_jobs} job(s), ${total_up} upload(s),"
	echo "  ${total_down} download(s) from ${WF_DIR}. Reading nothing is a"
	echo "  broken parser, not a clean workflow."
	rc=1
fi

if ((rc == 0)); then
	printf 'workflow-check: %d job(s), %d artifact hand-off(s) all awaited\n' \
		"${total_jobs}" "${total_down}"
fi

exit "${rc}"
