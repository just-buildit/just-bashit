# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, HELP_REGEX set by bats/common-setup
# shellcheck disable=SC2016  # makefile fixtures hold literal $(VAR); expanding them is make's job, and is what is under test
load 'test_helper/common-setup'
source 'src/just_bashit/make-run.sh'
_common_setup

# A fixture repo shaped like a real one: a standard.mk-style file supplying
# sanctioned defaults with `?=`, and a Makefile that overrides some of them.
# The layering IS the thing under test — resolving only the default, or only
# the override, is the bug this library exists to prevent.
setup() {
	REPO="${BATS_TEST_TMPDIR}/repo"
	mkdir -p "${REPO}"

	# NOT a heredoc. `<<-EOF` strips leading TABS, and a make recipe is
	# defined by its leading tab — the fixture parses as garbage and every
	# query then returns empty. printf keeps the tab explicit and visible.
	{
		printf '%s\n' 'UV             ?= uv'
		printf '%s\n' 'DEV_RUN        ?= $(UV) run --group dev'
		printf '%s\n' 'ZENSICAL       ?= $(DEV_RUN) zensical'
		printf '%s\n' 'DOCS_BUILD_CMD ?= $(ZENSICAL) build --clean --strict'
		printf '%s\n' 'DOCS_CHECK_CMD ?='
		printf '%s\n' 'PRE_COMMIT     ?= $(DEV_RUN) pre-commit'
		printf '%s\n' ''
		printf '%s\n' 'docs: ## Build the docs'
		printf '\t%s\n' '@$(DOCS_BUILD_CMD)'
		printf '%s\n' ''
		printf '%s\n' 'greet: ## Print a greeting'
		printf '\t%s\n' '@echo hello-from-fixture'
	} >"${REPO}/standard.mk"

	# The override: this fixture builds docs from a `docs` dependency group,
	# exactly as doppler does, so a resolver that returns the default is
	# visibly wrong here.
	{
		printf '%s\n' 'ZENSICAL = $(UV) run --group docs zensical'
		printf '%s\n' 'include standard.mk'
	} >"${REPO}/Makefile"
}

@test 'mk-var help' {
	run mk-var -h
	# shellcheck disable=SC2154
	assert_output --regexp "${HELP_REGEX}"
}

@test 'mk-var resolves the repo override, not the sanctioned default' {
	run mk-var -C "${REPO}" DOCS_BUILD_CMD
	assert_success
	assert_output 'uv run --group docs zensical build --clean --strict'
}

@test 'mk-var resolves a default the repo did not override' {
	run mk-var -C "${REPO}" PRE_COMMIT
	assert_success
	assert_output 'uv run --group dev pre-commit'
}

@test 'mk-var fails on an undefined variable' {
	run mk-var -C "${REPO}" NO_SUCH_VAR
	assert_failure
	assert_output --partial 'not defined'
}

# The guard that matters: `DOCS_CHECK_CMD ?=` is legitimately empty. If this
# ever starts failing, an empty command and a typo'd name have collapsed into
# the same result and callers can no longer tell them apart.
@test 'mk-var succeeds with empty output for a defined-but-empty variable' {
	run mk-var -C "${REPO}" DOCS_CHECK_CMD
	assert_success
	assert_output ''
}

@test 'mk-origin distinguishes defined from undefined' {
	run mk-origin -C "${REPO}" DOCS_BUILD_CMD
	assert_output 'file'
	run mk-origin -C "${REPO}" NO_SUCH_VAR
	assert_output 'undefined'
}

@test 'mk-var fails cleanly where there is no makefile' {
	run mk-var -C "${BATS_TEST_TMPDIR}" DOCS_BUILD_CMD
	assert_failure
	assert_output --partial 'no makefile'
}

@test 'mk-vars dumps NAME=value and honours the filter' {
	run mk-vars -C "${REPO}" '^DOCS_BUILD_CMD$'
	assert_success
	assert_output 'DOCS_BUILD_CMD=uv run --group docs zensical build --clean --strict'
}

@test 'mk-vars takes no built-in variable list' {
	# A variable this library has never heard of must still appear, or the
	# implementation has grown exactly the hand-maintained list it exists
	# to abolish.
	echo 'PROJECT_SPECIFIC_CMD = echo custom' >>"${REPO}/Makefile"
	run mk-vars -C "${REPO}" '^PROJECT_SPECIFIC_CMD$'
	assert_success
	assert_output 'PROJECT_SPECIFIC_CMD=echo custom'
}

@test 'mk-has answers for defined and undefined targets' {
	run mk-has -C "${REPO}" docs
	assert_success
	run mk-has -C "${REPO}" no-such-target
	assert_failure
}

@test 'mk-run runs the repo target' {
	run mk-run -C "${REPO}" greet
	assert_success
	assert_output --partial 'hello-from-fixture'
}

# Regression: an unparseable makefile once returned empty and exit 0, so a
# caller published a blank command believing it had asked and been answered.
@test 'an unreadable makefile fails loudly instead of answering empty' {
	printf '%s\n' 'this is not a makefile' >"${REPO}/Makefile"
	printf '%s\n' '<<<broken' >>"${REPO}/Makefile"

	run mk-var -C "${REPO}" DOCS_BUILD_CMD
	assert_failure
	refute_output ''

	run mk-vars -C "${REPO}"
	assert_failure

	run mk-has -C "${REPO}" docs
	assert_failure
}

@test 'mk-run refuses an undefined target' {
	run mk-run -C "${REPO}" no-such-target
	assert_failure
	assert_output --partial "no target 'no-such-target'"
}

# `--eval` is GNU make 3.82+ (28 Jul 2010), and macOS still ships 3.81 as
# /usr/bin/make. Reaching for it breaks on exactly one runner and passes
# everywhere else — cheaper to catch here than in a macOS-only CI failure.
@test 'the library avoids --eval, which GNU make 3.81 lacks' {
	run grep -nE '^[^#]*--eval' \
		"${BATS_TEST_DIRNAME}/../src/just_bashit/make-run.sh"
	assert_failure
}
