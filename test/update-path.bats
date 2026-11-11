# shellcheck disable=SC2154  # bats/common-setup export the harness vars
# shellcheck disable=SC2016  # rc-file lines as a user writes them: their $
load 'test_helper/common-setup'

# update-path.sh: ~/.local/bin on PATH for good, in every rc file, once. The
# Windows user Path is tested for real in test/get-jb-ps1.windows.ps1; here
# the uname is pinned, so no Windows half runs.

setup() {
	_common_setup
	export HOME="${BATS_TEST_TMPDIR}/home"
	mkdir -p "${HOME}"
	UP="${PROJECT_ROOT}/src/just_bashit/update-path.sh"
	BEGIN='# >>> just-bashit update-path >>>'
	export JB_UNAME_S=Linux
	unset JB_RELOAD_MARKER
}

@test 'update-path writes the ~/.bashrc block once, and a re-run changes nothing' {
	printf 'alias ll=ls\n' >"${HOME}/.bashrc"
	run bash "${UP}"
	assert_success
	assert_line 'update-path: ~/.bashrc: appended'
	local before
	before="$(cksum <"${HOME}/.bashrc")"
	run bash "${UP}"
	assert_success
	assert_line 'update-path: ~/.bashrc: already has the just-bashit block -- unchanged'
	assert_equal "$(cksum <"${HOME}/.bashrc")" "${before}"
	run grep -cxF "${BEGIN}" "${HOME}/.bashrc"
	assert_output 1
	run head -1 "${HOME}/.bashrc"
	assert_output 'alias ll=ls'
}

@test 'the block puts ~/.local/bin on PATH once, however often it is read' {
	run bash "${UP}"
	assert_success
	run bash -c '. ~/.bashrc; . ~/.bashrc; printf "%s\n" "${PATH}" | tr ":" "\n" | grep -cx "${HOME}/.local/bin"'
	assert_output 1
}

@test 'update-path writes ~/.zshrc on macOS, and when one exists' {
	JB_UNAME_S=Darwin run bash "${UP}"
	assert_success
	assert_line 'update-path: ~/.zshrc: appended'
	run grep -cxF "${BEGIN}" "${HOME}/.zshrc"
	assert_output 1
	JB_UNAME_S=Darwin run bash "${UP}"
	assert_line 'update-path: ~/.zshrc: already has the just-bashit block -- unchanged'
	run grep -cxF "${BEGIN}" "${HOME}/.zshrc"
	assert_output 1
}

@test 'update-path never rewrites a user line that already covers it' {
	printf '# mine\nexport PATH="$HOME/.local/bin:$PATH"\n' >"${HOME}/.zshrc"
	printf '. "$HOME/.config/just-bashit/bashrc.sh"\n' >"${HOME}/.bashrc"
	local z b
	z="$(cksum <"${HOME}/.zshrc")"
	b="$(cksum <"${HOME}/.bashrc")"
	run bash "${UP}"
	assert_success
	assert_line --partial 'update-path: ~/.zshrc: line 2 already covers it'
	assert_line --partial 'update-path: ~/.bashrc: line 1 already covers it'
	assert_equal "$(cksum <"${HOME}/.zshrc")" "${z}"
	assert_equal "$(cksum <"${HOME}/.bashrc")" "${b}"
}

@test 'a commented-out mention does not count as covering it' {
	printf '# export PATH=~/.local/bin:$PATH\n' >"${HOME}/.bashrc"
	run bash "${UP}"
	assert_line 'update-path: ~/.bashrc: appended'
}

# Through the jbx function the directory reaches the calling shell too: the
# marker gets a `path` line, appended after any other writer's.
@test 'update-path appends a path line to JB_RELOAD_MARKER' {
	local m="${BATS_TEST_TMPDIR}/state/reload"
	mkdir -p "${m%/*}"
	printf 'path /other\n' >"${m}"
	JB_RELOAD_MARKER="${m}" run bash "${UP}"
	assert_success
	assert_line 'update-path: this shell: jbx puts ~/.local/bin on PATH when this exits'
	run cat "${m}"
	assert_output "path /other
path ${HOME}/.local/bin"
}
