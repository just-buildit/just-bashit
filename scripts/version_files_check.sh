#!/usr/bin/env bash
# ############################################################################
# version_files_check.sh — repo gate, not a shipped library.                 #
# ############################################################################
# Three invariants over the [tool.bumpversion] table, each of which has       #
# already shipped broken once:                                               #
#                                                                            #
#   1. Every registered `filename` exists. The jb.toml -> bootstrap.toml     #
#      rename moved the file and updated every reader but not the entry      #
#      pointing at it, so `make bump-version` died with FileNotFoundError    #
#      and the release path stayed broken until someone tried to release.    #
#                                                                            #
#   2. Every registered `search` string actually MATCHES in its file. A      #
#      search that no longer matches is worse than a missing entry: bumping  #
#      succeeds, silently changes nothing, and the file drifts a version     #
#      behind. The `# PACKAGE:` headers are padded to a fixed width and two  #
#      of them are one space narrower than the other eighteen, so this is    #
#      one edited comment away from happening.                               #
#                                                                            #
#   3. Every LINE that declares the version is covered by a search. Not      #
#      every file -- every line. just-runit carried a `# PACKAGE:` header    #
#      entry and no `_VERSION` entry, so the file was registered, the bump   #
#      ran, and `_VERSION` sat at 0.1.4 through two releases. A file-level   #
#      check passes that bug green; it was written that way first and did.   #
#      make-run.sh shipped in 0.4.0 with no entry at all, which is the same  #
#      check with every line uncovered.                                      #
#                                                                            #
# Why `version-check` does not cover any of this: it compares the manifests  #
# to each other AFTER a bump. It cannot see a bump that never ran, an entry  #
# that quietly matched nothing, or a line it was never told to probe.        #
#                                                                            #
# Telling a DECLARATION from PROSE, without an exclusion list to drift:      #
# source and docs both narrate releases -- just-runit itself says "This      #
# triggered on jb until 0.5.0" -- and bumping those would make them false.   #
# A line counts as declaring only if the version is QUOTED ("1.2.3"), or the #
# line matches one of the search shapes already in the table. Prose names a  #
# version bare and in passing; a declaration quotes it or is a header this   #
# table already describes. That is derived from the config, so adding a new  #
# entry teaches the check a new shape for free.                              #
#                                                                            #
# The residual gap, stated rather than hidden: a NEW declaration shape that  #
# is also UNQUOTED, in a file already registered, is invisible here. Every   #
# shape in this repo today is one or the other.                              #
#                                                                            #
# Failures accumulate: all three checks always run and every offender is     #
# listed, so the set gets fixed once instead of one push at a time.          #
# ############################################################################

set -uo pipefail

# VERSION_FILES_ROOT exists so the suite can point this at a fixture tree.
# Without it the gate could only be proven by hand, and the check it replaced
# — a file-level one — passed the 0.1.4 bug green while looking correct.
cd "${VERSION_FILES_ROOT:-$(dirname "${BASH_SOURCE[0]}")/..}" || exit 1

rc=0
CONFIG="pyproject.toml"

current=$(sed -n 's/^current_version = "\(.*\)"/\1/p' "${CONFIG}" | head -1)
if [[ -z "${current}" ]]; then
	echo "ERROR: no [tool.bumpversion] current_version in ${CONFIG}"
	exit 1
fi

# ---------------------------------------------------------------------------
# Parse the table once into filename/search pairs — ONE declaration, read by
# all three checks, so they cannot disagree about which entries exist.
#
# `search` defaults to the bare version when an entry omits it, which is what
# bump-my-version itself does. Values are TOML basic strings, so \" unescapes.
# ---------------------------------------------------------------------------
entries=$(awk '
	/^\[tool\.bumpversion\]/            { region = 1; next }
	!region                             { next }
	/^\[\[tool\.bumpversion\.files\]\]/ { flush(); next }
	/^filename = / { fn = substr($0, 13, length($0) - 13); next }
	/^search = / {
		se = substr($0, 11, length($0) - 11)
		gsub(/\\"/, "\"", se)
		next
	}
	END { flush() }
	function flush() {
		if (fn != "") print fn "\t" (se == "" ? "{current_version}" : se)
		fn = ""; se = ""
	}
' "${CONFIG}")

if [[ -z "${entries}" ]]; then
	echo "ERROR: no [[tool.bumpversion.files]] entries found in ${CONFIG}"
	exit 1
fi

# ---------------------------------------------------------------------------
# 1. Registered files exist.  2. Registered searches match.
# ---------------------------------------------------------------------------
missing=()
unmatched=()
while IFS=$'\t' read -r fn search; do
	[[ -z "${fn}" ]] && continue
	if [[ ! -f "${fn}" ]]; then
		missing+=("${fn}")
		continue
	fi
	# A fixed string to bump-my-version too, not a regex.
	if ! grep -qF -- "${search//\{current_version\}/${current}}" "${fn}"; then
		unmatched+=("${fn}: ${search}")
	fi
done <<<"${entries}"

if ((${#missing[@]} > 0)); then
	echo "ERROR: bumpversion registers files that do not exist:"
	printf '  %s\n' "${missing[@]}"
	echo "  \`make bump-version\` fails outright on these. Fix the filename in"
	echo "  ${CONFIG}, or drop the entry if the file is gone for good."
	rc=1
fi

if ((${#unmatched[@]} > 0)); then
	echo "ERROR: bumpversion search strings that match nothing in their file:"
	printf '  %s\n' "${unmatched[@]}"
	echo "  These bump SILENTLY: the release succeeds and the file keeps the"
	echo "  old version. Make the search match the file byte for byte."
	rc=1
fi

# ---------------------------------------------------------------------------
# 3. Every version-declaring LINE is covered by a search for its own file.
#
# What ships, plus the root manifests. pyproject.toml is exempt because
# bump-my-version rewrites its own config file natively — the v0.5.0 commit
# changed both `version` and `current_version` there with no entry for it.
# ---------------------------------------------------------------------------
uncovered=()
while IFS= read -r path; do
	[[ -f "${path}" ]] || continue
	[[ "${path}" == "${CONFIG}" ]] && continue

	while IFS= read -r hit; do
		[[ -z "${hit}" ]] && continue
		lineno="${hit%%:*}"
		line="${hit#*:}"

		# Prose or declaration? See the note at the top.
		declaring=0
		[[ "${line}" == *"\"${current}\""* ]] && declaring=1
		[[ "${line}" == *"'${current}'"* ]] && declaring=1
		if ((declaring == 0)); then
			while IFS=$'\t' read -r _ shape; do
				shape="${shape//\{current_version\}/${current}}"
				if [[ "${line}" == *"${shape}"* ]]; then
					declaring=1
					break
				fi
			done <<<"${entries}"
		fi
		((declaring)) || continue

		covered=0
		while IFS=$'\t' read -r fn search; do
			[[ "${fn}" == "${path}" ]] || continue
			pat="${search//\{current_version\}/${current}}"
			if [[ "${line}" == *"${pat}"* ]]; then
				covered=1
				break
			fi
		done <<<"${entries}"
		((covered)) || uncovered+=("${path}:${lineno}")
	done < <(grep -nF -- "${current}" "${path}")
done < <(
	find src/just_bashit -type f
	# A glob, not `find -maxdepth 1 -printf`: -printf is GNU-only and BSD
	# find just errors, which would have left the root manifests unscanned
	# on macOS — the gate silently checking less than it claims to.
	printf '%s\n' *.toml
)

if ((${#uncovered[@]} > 0)); then
	echo "ERROR: lines declare the version but no bumpversion search covers them:"
	printf '  %s\n' "${uncovered[@]}"
	echo "  They will keep ${current} through the next release. Add a"
	echo "  [[tool.bumpversion.files]] entry whose search matches each line."
	rc=1
fi

if ((rc == 0)); then
	printf 'version-files-check: %d entries, every declaring line covered\n' \
		"$(printf '%s\n' "${entries}" | grep -c .)"
fi

exit "${rc}"
