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
#   4. Every job a pull request runs feeds `CI passed` (ci-passed), the one  #
#      required check, or comes after it. coverage did not: it went red on   #
#      main for #142 and the merge went through, because nothing that         #
#      gates a merge waited for it.                                           #
#                                                                            #
#   5. Every `actions/checkout` of THIS repo (a step with no `repository:`) #
#      sets `submodules: recursive` (or true), whatever its job runs. bats   #
#      and its helpers are submodules; the lint job's checkout had none, so  #
#      test-lint-gates died on a missing test/bats/bin/bats (#258) while     #
#      every test job passed. The rule is per STEP and structural: deciding  #
#      which jobs "run bats" is a spelling chase (`make -C . test`, a direct #
#      bats call), and another repo's checkout never counts for this one.    #
#      A job that must not fetch them is named in SUBMODULES_EXEMPT below,   #
#      with its reason: today only canonical's vendored workflows.           #
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
total_co=0
# workflow:job pairs whose checkout does not fetch the submodules, each with
# its reason. Both are canonical's workflows, vendored verbatim (standard.mk
# VENDORED_FILES): this repo cannot edit them, and neither runs bats.
SUBMODULES_EXEMPT=(
	# changes reads `git diff` to decide what CI runs; it runs no suite.
	changes.yml:changes
	# retire deletes a merged train's branches through the API.
	train-retire.yml:retire
)

# ---------------------------------------------------------------------------
# Extract the shape of one workflow: one record per line, so the shell side
# needs no second parser.
#
#   job<TAB>NAME
#   needs<TAB>NAME<TAB>DEP
#   up<TAB>NAME<TAB>ARTIFACT
#   down<TAB>NAME<TAB>ARTIFACT
#   mainonly<TAB>NAME
#   checkout<TAB>NAME<TAB>SUBMODULES<TAB>FOREIGN   (one per checkout step;
#                         SUBMODULES 1 when it sets recursive|true, FOREIGN
#                         1 when it names a `repository:`)
# ---------------------------------------------------------------------------
_shape() {
	awk '
		function trim(x) { gsub(/^[ \t]+|[ \t\r]+$/, "", x); return x }
		# LINE cut at its comment: the first `#` outside quotes that starts
		# the line or follows a blank. Everything a key could be read from
		# goes through this first, so a key in a comment is never a key.
		function decomment(line,   i, c, q, n) {
			n = length(line); q = ""
			for (i = 1; i <= n; i++) {
				c = substr(line, i, 1)
				if (q != "") { if (c == q) q = ""; continue }
				if (c == "\"" || c == "\047") { q = c; continue }
				if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t]/))
					return substr(line, 1, i - 1)
			}
			return line
		}
		# LINE with the contents of every quoted string blanked to "_", the quotes
		# kept and the length unchanged: where a key may be looked for, so
		# `name: "submodules: recursive"` holds no key but name.
		function mask(line,   i, c, q, n, out) {
			n = length(line); q = ""; out = ""
			for (i = 1; i <= n; i++) {
				c = substr(line, i, 1)
				if (q != "") {
					if (c == q) { q = ""; out = out c } else out = out "_"
					continue
				}
				if (c == "\"" || c == "\047") q = c
				out = out c
			}
			return out
		}
		# The value of KEY on this (decommented) line, block (`key: v`) or
		# flow (`{key: v, ...}`) form, quotes stripped; found in the masked
		# line, so only in a key position. "\001" when there is no such key.
		function val(line, key,   v) {
			if (!match(mask(line), "(^|[{, \t])" key ":[ \t]*")) return "\001"
			v = substr(line, RSTART + RLENGTH)
			if (v ~ /^"/) { v = substr(v, 2); sub(/".*$/, "", v); return v }
			if (v ~ /^\047/) { v = substr(v, 2); sub(/\047.*$/, "", v); return v }
			# An expression is kept whole: its braces are not the mapping
			# closing.
			if (v ~ /^\$\{\{/) { sub(/\}\}.*$/, "}}", v); return v }
			sub(/[ \t]+#.*$/, "", v); sub(/[,}].*$/, "", v)
			return trim(v)
		}
		function readitem(line,   v) {
			if (val(line, "uses") ~ /^actions\/checkout@/) co = 1
			v = val(line, "submodules")
			if (v == "recursive" || v == "true") subm = 1
			v = val(line, "repository")
			if (v != "\001") repo = v
			# An alias (`*name`, `<<: *name`) pulls keys from elsewhere,
			# which this line reader cannot see: refused, not guessed at.
			if (mask(line) ~ /(:|^[ \t]*-)[ \t]+\*[A-Za-z0-9_.-]+[ \t]*$/ ||
			    mask(line) ~ /<<:/) alias = 1
		}
		function flush() {
			if (initem && co)
				print "checkout\t" job "\t" subm "\t" (repo == "" ? "-" : repo) "\t" alias
			initem = 0; co = 0
		}
		END { flush() }

		# Comments are cut before anything is read (a full-line one leaves a
		# blank line, which ends nothing).
		{ $0 = decomment($0) }

		# A block scalar (`key: |`, `key: >-`, ...) is text, not keys: its
		# body is every following line indented deeper than the key, and
		# blank lines within it. Skipped whole, so nothing in a `run: |` or a
		# folded value is read as a key, a step or a job.
		inscalar {
			if ($0 !~ /[^ \t]/ || match($0, /[^ \t]/) - 1 > scalarind) next
			inscalar = 0
		}
		mask($0) ~ /:[ \t]+[|>][-+0-9]*[ \t]*$/ {
			inscalar = 1
			scalarind = match($0, /[^ \t]/) - 1
			# `- key: |`: the key, not the dash, sets the body indent.
			if ($0 ~ /^[ \t]*- /) scalarind = match($0, /-[ \t]+[^ \t]/) + 1
		}

		/^jobs:[ \t]*$/ { injobs = 1; next }
		# A top-level key other than jobs: ends the jobs block.
		/^[^ \t#]/ && !/^jobs:/ { flush(); injobs = 0 }
		!injobs { next }

		# Two-space indent under jobs: is a job name.
		/^  [A-Za-z0-9_-]+:[ \t]*$/ {
			flush()
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

		# Each list item (a step) is read on its own: its keys, up to the next
		# item or the first line back at its own indent. A comment is prose.
		/^[ \t]*#/ { next }
		/^[ \t]*- / {
			flush()
			initem = 1; itemind = match($0, /-/) - 1
			co = 0; subm = 0; repo = ""; alias = 0
		}
		initem && !/^[ \t]*- / && /[^ \t]/ && match($0, /[^ \t]/) - 1 <= itemind {
			flush()
		}
		initem { readitem($0) }

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

# This repo's own slug, owner/name, lower case: from Actions when it is set,
# else from the origin remote. Empty when neither says.
own_repo="${GITHUB_REPOSITORY:-}"
if [[ -z ${own_repo} ]]; then
	own_repo="$(git remote get-url origin 2>/dev/null |
		sed -n 's#^.*[:/]\([^/:]*/[^/]*\)$#\1#p' | sed 's#\.git$##')"
fi
own_repo="$(printf '%s' "${own_repo}" | tr '[:upper:]' '[:lower:]')"

# _foreign VALUE -- true only when a checkout's `repository:` VALUE is a
# literal slug other than this repo's. No key ("-"), an expression
# (`${{ github.repository }}`, or any other, which cannot be read here), or a
# repo whose own slug is unknown: all count as THIS repo, so a doubt fails
# closed.
_foreign() {
	local r="$1"
	# shellcheck disable=SC2016  # the literal `${{` of an Actions expression
	[[ ${r} != "-" && ${r} != *'${{'* && -n ${own_repo} ]] || return 1
	[[ "$(printf '%s' "${r}" | tr '[:upper:]' '[:lower:]')" != "${own_repo}" ]]
}

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

	# 5. Every checkout of this repo fetches the submodules.
	while IFS=$'\t' read -r _ job subm repo alias; do
		[[ -n "${job}" ]] || continue
		if [[ ${alias} == 1 ]]; then
			echo "ERROR: ${name}: job '${job}' has a checkout step that uses a"
			echo "  YAML alias. Its keys come from elsewhere, which this check"
			echo "  cannot read; write them out in the step."
			rc=1
			continue
		fi
		_foreign "${repo}" && continue
		total_co=$((total_co + 1))
		[[ ${subm} == 1 ]] && continue
		exempt=0
		for e in ${SUBMODULES_EXEMPT[@]+"${SUBMODULES_EXEMPT[@]}"}; do
			[[ "${e}" == "${name}:${job}" ]] && exempt=1
		done
		((exempt)) && continue
		echo "ERROR: ${name}: job '${job}' checks out this repo without"
		echo "  \`submodules: recursive\`. bats is a submodule, and whether a"
		echo "  job runs it is not read here: every checkout fetches them."
		rc=1
	done < <(printf '%s\n' "${wf}" | awk -F'\t' '$1=="checkout"')

	# 4. The required check waits for every job a pull request runs.
	if printf '%s\n' "${wf}" | awk -F'\t' '$1=="job" && $2=="ci-passed"' |
		grep . >/dev/null; then
		mainonly=$(printf '%s\n' "${wf}" | awk -F'\t' '$1=="mainonly" { print $2 }')
		while IFS=$'\t' read -r _ job; do
			[[ -n "${job}" && "${job}" != "ci-passed" ]] || continue
			grep -qxF -- "${job}" <<<"${mainonly}" && continue
			_reaches "${wf}" ci-passed "${job}" && continue
			_reaches "${wf}" "${job}" ci-passed && continue
			echo "ERROR: ${name}: job '${job}' runs on pull requests, but"
			echo "  'CI passed' (ci-passed) does not wait for it, so a red"
			echo "  '${job}' merges anyway. Add it to ci-passed's needs."
			rc=1
		done < <(printf '%s\n' "${wf}" | awk -F'\t' '$1=="job"')
	fi
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
	printf 'workflow-check: %d job(s), %d artifact hand-off(s) all awaited, %d checkout(s) of this repo fetch submodules or are named exempt\n' \
		"${total_jobs}" "${total_down}" "${total_co}"
fi

exit "${rc}"
