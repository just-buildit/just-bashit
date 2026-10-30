# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, PROJECT_ROOT set by common-setup
load 'test_helper/common-setup'
_common_setup

# ---------------------------------------------------------------------------
# tree_unchanged.sh -- the gate that holds `make test` to leaving the tree
# as it found it.
#
# The defect it exists to catch shipped (#111): a cleanup line deleted the
# package.json both bats submodules track, so every `make test` left them
# dirty. The proof that the gate caught it was done once by hand; these keep
# it (#113).
#
# Every case runs in a scratch repository under BATS_TEST_TMPDIR, never the
# real checkout: this file itself runs inside `make test`, so dirtying the
# real tree would trip the very gate it tests. The git variables a hook sets
# are cleared for the same reason -- with GIT_DIR exported, "the scratch
# repo" would be the real one.
# ---------------------------------------------------------------------------

setup() {
	unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
	# A nested make inherits the outer one's command-line variables, through
	# MAKEFLAGS and the environment both: `make test-fast BATS_ARGS=...`
	# would otherwise leak into every case below.
	unset MAKEFLAGS MFLAGS MAKELEVEL BATS_ARGS
	export GIT_CEILING_DIRECTORIES="${BATS_TEST_TMPDIR}"
	export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
	export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

	REPO="${BATS_TEST_TMPDIR}/repo"
	mkdir -p "${REPO}/scripts"
	cp "${PROJECT_ROOT}/scripts/tree_unchanged.sh" "${REPO}/scripts/"
	echo one >"${REPO}/tracked.txt"
	git -C "${REPO}" init -q
	git -C "${REPO}" add -A
	git -C "${REPO}" commit -qm init
}

# _gate CMD... -- run CMD under the gate, from inside the scratch repo.
_gate() {
	cd "${REPO}" || return 1
	run bash scripts/tree_unchanged.sh "$@"
}

@test 'a command that leaves the tree alone passes' {
	_gate true
	assert_success
	refute_output --partial "changed the working tree"
}

@test 'a passing command that dirties a tracked file fails' {
	_gate sh -c 'echo two >>tracked.txt'
	assert_failure 1
	assert_output --partial "M tracked.txt"
	assert_output --partial "changed the working tree"
}

@test 'a new untracked file fails' {
	_gate sh -c ': >stray.txt'
	assert_failure 1
	assert_output --partial "?? stray.txt"
}

@test 'edits made before the run are not blamed on it' {
	echo local >>"${REPO}/tracked.txt"
	_gate true
	assert_success
}

@test 'a failing command keeps its own exit status' {
	_gate sh -c 'exit 3'
	assert_failure 3
	refute_output --partial "changed the working tree"
}

@test 'a failing command that dirties the tree reports both' {
	_gate sh -c 'echo two >>tracked.txt; exit 3'
	assert_failure 3
	assert_output --partial "M tracked.txt"
	assert_output --partial "changed the working tree"
}

@test 'damage inside a submodule is seen' {
	local sub="${BATS_TEST_TMPDIR}/sub"
	mkdir -p "${sub}"
	echo '{}' >"${sub}/package.json"
	git -C "${sub}" init -q
	git -C "${sub}" add -A
	git -C "${sub}" commit -qm init
	git -C "${REPO}" -c protocol.file.allow=always \
		submodule --quiet add "${sub}" sub
	# A plain `git status` already shows a dirty submodule; it stops doing so
	# once a .gitmodules or a user's diff.ignoreSubmodules says to ignore
	# it. --ignore-submodules=none is what keeps the gate looking anyway.
	git -C "${REPO}" config -f .gitmodules submodule.sub.ignore all
	git -C "${REPO}" add .gitmodules
	git -C "${REPO}" commit -qm 'add sub'

	# The #111 defect, exactly: a tracked json deleted inside the submodule.
	_gate rm sub/package.json
	assert_failure 1
	assert_output --partial "sub"
	assert_output --partial "changed the working tree"
}

@test 'outside a git checkout it refuses rather than passing' {
	local bare="${BATS_TEST_TMPDIR}/not-a-repo"
	mkdir -p "${bare}"
	cd "${bare}" || return 1
	run bash "${REPO}/scripts/tree_unchanged.sh" true
	assert_failure 1
	assert_output --partial "git cannot read this checkout"
}

# --- through make: the wiring, not just the script -------------------------
#
# A copy of the real Makefile and standard.mk, with BATS pointed at a fake
# that records its arguments and dirties a tracked file. This is the
# sabotage #113 asks to keep: it fails if either command loses the gate, or
# drops BATS_ARGS.

_make_repo() {
	cp "${PROJECT_ROOT}/Makefile" "${PROJECT_ROOT}/standard.mk" "${REPO}/"
	mkdir -p "${REPO}/src" "${REPO}/test/test_helper/bats-assert"
	: >"${REPO}/src/lib.sh"
	# The submodule stamp test/test-fast depend on, so make does not try to
	# initialise submodules this repo does not have.
	: >"${REPO}/test/test_helper/bats-assert/load.bash"
	printf '%s\n' '*.tar.gz' test-results/ >"${REPO}/.gitignore"
	cat >"${REPO}/fake-bats" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >"${FAKE_BATS_ARGS}"
[ -z "${FAKE_BATS_DIRTY}" ] || echo dirty >>tracked.txt
exit "${FAKE_BATS_RC:-0}"
SH
	chmod +x "${REPO}/fake-bats"
	git -C "${REPO}" add -A
	git -C "${REPO}" commit -qm 'make wiring'
	export FAKE_BATS_ARGS="${BATS_TEST_TMPDIR}/bats-args"
}

_make() {
	run make -C "${REPO}" --no-print-directory "$@" BATS=./fake-bats
}

@test 'make test and make test-fast pass a clean run' {
	_make_repo
	_make test
	assert_success
	_make test-fast
	assert_success
}

@test 'make test fails a run that dirties a tracked file' {
	_make_repo
	FAKE_BATS_DIRTY=1 _make test
	assert_failure
	assert_output --partial "M tracked.txt"
	assert_output --partial "changed the working tree"
}

@test 'make test-fast fails a run that dirties a tracked file' {
	_make_repo
	FAKE_BATS_DIRTY=1 _make test-fast
	assert_failure
	assert_output --partial "M tracked.txt"
	assert_output --partial "changed the working tree"
}

@test 'make test reports tree damage from a failing run too' {
	_make_repo
	FAKE_BATS_DIRTY=1 FAKE_BATS_RC=1 _make test
	assert_failure
	assert_output --partial "M tracked.txt"
	assert_output --partial "changed the working tree"
}

@test 'BATS_ARGS reaches bats in both commands, and defaults to test' {
	_make_repo
	_make test-fast
	assert_success
	run cat "${FAKE_BATS_ARGS}"
	assert_output "--abort test"

	_make test-fast BATS_ARGS='-f deps test/setup-system.bats'
	assert_success
	run cat "${FAKE_BATS_ARGS}"
	assert_output "--abort -f deps test/setup-system.bats"

	_make test BATS_ARGS='-f deps test/setup-system.bats'
	assert_success
	run cat "${FAKE_BATS_ARGS}"
	assert_output --regexp ' -f deps test/setup-system\.bats$'
}
