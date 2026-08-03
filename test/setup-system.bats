# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, HELP_REGEX set by bats/common-setup
# shellcheck disable=SC2016  # $HOME stays unexpanded on purpose in RC_LINE/PF_LINE
# shellcheck disable=SC2012  # ls -ld is the portable way to read a mode string
load 'test_helper/common-setup'
_common_setup

# Every test runs against a throwaway HOME so nothing here can touch the
# developer's real ~/.bashrc, ~/.ssh or ~/.gitconfig.
setup() {
	HOME="${BATS_TEST_TMPDIR}/home"
	XDG_CONFIG_HOME="${HOME}/.config"
	export HOME XDG_CONFIG_HOME
	mkdir -p "${HOME}"
	cd "${BATS_TEST_TMPDIR}" || return 1

	# Sourcing profile.sh starts a real ssh-agent, and a daemon that
	# outlives the test holds the output pipe bats reads from — its
	# formatter then never sees EOF and the whole run hangs until something
	# kills it (six hours, on a CI runner). Off by default here; the one
	# test that exercises the bootstrap turns it back on deliberately.
	export JB_SSH_AGENT=0

	RC_LINE='if [ -r "$HOME/.config/just-bashit/bashrc.sh" ]; then . "$HOME/.config/just-bashit/bashrc.sh"; fi'
	PF_LINE='if [ -r "$HOME/.config/just-bashit/profile.sh" ]; then . "$HOME/.config/just-bashit/profile.sh"; fi'
}

# Reap anything this test started that outlives it. `kill` on a recorded pid,
# not `pkill -f`: minimal images ship no procps at all — fedora:latest has
# neither pkill nor ps — and a cleanup that silently does not run is how a
# leaked daemon hangs the whole suite.
teardown() {
	local pidfile="${BATS_TEST_TMPDIR}/rt/agent.pid" pid
	if [ -r "${pidfile}" ]; then
		pid=$(cat "${pidfile}" 2>/dev/null || true)
		[ -n "${pid}" ] && kill "${pid}" 2>/dev/null
	fi
	return 0
}

# A jb.toml covering every package manager, so the deps step resolves
# whatever the host actually runs.
_write_deps_toml() {
	cat >"${1}" <<-'EOF'
		[runtime.apt]
		packages = ["curl"]

		[runtime.pacman]
		packages = ["curl"]

		[runtime.brew]
		packages = ["curl"]

		[runtime.dnf]
		packages = ["curl"]

		[runtime.zypper]
		packages = ["curl"]

		[runtime.apk]
		packages = ["curl"]

		[runtime.msys2]
		packages = ["curl"]
	EOF
}

# ---------------------------------------------------------------------------
# CLI surface
# ---------------------------------------------------------------------------

@test 'setup-system.sh help -h' {
	run setup-system.sh -h
	assert_success
	assert_output --regexp "${HELP_REGEX}"
}

@test 'setup-system.sh --help long form' {
	run setup-system.sh --help
	assert_success
	assert_output --partial "Steps:"
}

@test 'setup-system.sh unknown option' {
	run setup-system.sh -z
	assert_failure
	assert_output --partial "Invalid option: -z"
}

@test 'setup-system.sh -s requires an argument' {
	run setup-system.sh -s
	assert_failure
}

@test 'setup-system.sh --prefix requires an argument' {
	run setup-system.sh --prefix
	assert_failure
}

@test 'unknown step is rejected before anything runs' {
	run setup-system.sh -n -s bogus
	assert_failure
	assert_output --partial "unknown step 'bogus'"
	assert_output --partial "known steps"
}

@test 'unknown step in --skip is rejected' {
	run setup-system.sh -n -x nope
	assert_failure
	assert_output --partial "unknown step 'nope'"
}

# ---------------------------------------------------------------------------
# Templates
# ---------------------------------------------------------------------------

@test '--template prints the bashrc template' {
	run setup-system.sh --template
	assert_success
	assert_output --partial "history-search-backward"
	assert_output --partial "bashrc.d"
}

@test '--template writes the bashrc template to a file' {
	run setup-system.sh --template "${BATS_TEST_TMPDIR}/out.sh"
	assert_success
	run grep -q "history-search-backward" "${BATS_TEST_TMPDIR}/out.sh"
	assert_success
}

@test '--template-profile prints the profile template' {
	run setup-system.sh --template-profile
	assert_success
	assert_output --partial "ssh-agent"
	assert_output --partial "_jb_path_prepend"
}

# ---------------------------------------------------------------------------
# Dry run
# ---------------------------------------------------------------------------

@test 'dry run announces itself and changes nothing' {
	run setup-system.sh -n
	assert_success
	assert_output --partial "dry run"
	assert [ ! -e "${HOME}/.bashrc" ]
	assert [ ! -e "${HOME}/.profile" ]
	assert [ ! -e "${HOME}/.config/just-bashit" ]
	assert [ ! -e "${HOME}/.ssh" ]
	assert [ ! -e "${HOME}/.gitconfig" ]
}

@test 'dry run covers every step' {
	run setup-system.sh -n
	assert_success
	assert_output --partial "deps —"
	assert_output --partial "shell —"
	assert_output --partial "ssh —"
	assert_output --partial "git —"
	assert_output --partial "tools —"
	assert_output --partial "claude —"
}

@test 'dry run prints a summary' {
	run setup-system.sh -n -s shell
	assert_success
	assert_output --partial "summary"
	assert_output --partial "shell:"
}

@test '-s selects a subset of steps' {
	run setup-system.sh -n -s git
	assert_success
	assert_output --partial "git —"
	refute_output --partial "claude —"
	refute_output --partial "shell —"
}

@test '--skip drops a step' {
	run setup-system.sh -n -x claude,deps
	assert_success
	assert_output --partial "shell —"
	refute_output --partial "claude —"
	refute_output --partial "deps —"
}

@test 'steps run in canonical order however they are listed' {
	run setup-system.sh -n -s claude,shell
	assert_success
	local shell_pos claude_pos
	shell_pos=$(echo "${output}" | grep -n "shell —" | cut -d: -f1)
	claude_pos=$(echo "${output}" | grep -n "claude —" | cut -d: -f1)
	assert [ "${shell_pos}" -lt "${claude_pos}" ]
}

@test '[tools.setup-system].steps restricts the default step set' {
	cat >jb.toml <<-'EOF'
		[tools.setup-system]
		source = "just-bashit:setup-system"
		steps = ["shell", "git"]
	EOF
	run setup-system.sh -n
	assert_success
	assert_output --partial "shell —"
	assert_output --partial "git —"
	refute_output --partial "claude —"
}

@test 'explicit -s overrides the toml steps key' {
	cat >jb.toml <<-'EOF'
		[tools.setup-system]
		steps = ["shell"]
	EOF
	run setup-system.sh -n -s git
	assert_success
	assert_output --partial "git —"
	refute_output --partial "shell —"
}

# ---------------------------------------------------------------------------
# shell step
# ---------------------------------------------------------------------------

@test 'shell step installs both templates and the drop-in directory' {
	run setup-system.sh -s shell
	assert_success
	assert [ -f "${HOME}/.config/just-bashit/bashrc.sh" ]
	assert [ -f "${HOME}/.config/just-bashit/profile.sh" ]
	assert [ -d "${HOME}/.config/just-bashit/bashrc.d" ]
}

@test 'shell step adds the source lines' {
	run setup-system.sh -s shell
	assert_success
	run grep -qxF "${RC_LINE}" "${HOME}/.bashrc"
	assert_success
	run grep -qxF "${PF_LINE}" "${HOME}/.profile"
	assert_success
}

@test 'shell step preserves existing bashrc content' {
	printf '# my own settings\nexport MINE=1\n' >"${HOME}/.bashrc"
	run setup-system.sh -s shell
	assert_success
	run grep -qxF 'export MINE=1' "${HOME}/.bashrc"
	assert_success
}

@test 'shell step is idempotent — one source line after three runs' {
	setup-system.sh -s shell >/dev/null
	setup-system.sh -s shell >/dev/null
	setup-system.sh -s shell >/dev/null
	assert_equal "$(grep -cxF "${RC_LINE}" "${HOME}/.bashrc")" 1
	assert_equal "$(grep -cxF "${PF_LINE}" "${HOME}/.profile")" 1
}

@test 'shell step reports up-to-date on the second run' {
	setup-system.sh -s shell >/dev/null
	run setup-system.sh -s shell
	assert_success
	assert_output --partial "up to date"
}

@test 'shell step backs up a modified copy before replacing it' {
	setup-system.sh -s shell >/dev/null
	echo '# hand edited' >>"${HOME}/.config/just-bashit/bashrc.sh"
	run setup-system.sh -s shell
	assert_success
	assert_output --partial "kept as"
	run grep -qxF '# hand edited' "${HOME}/.config/just-bashit/bashrc.sh.bak"
	assert_success
}

@test 'shell step also wires ~/.bash_profile when that file exists' {
	touch "${HOME}/.bash_profile"
	run setup-system.sh -s shell
	assert_success
	run grep -qxF "${PF_LINE}" "${HOME}/.bash_profile"
	assert_success
}

@test 'shell step leaves ~/.bash_profile alone when it does not exist' {
	run setup-system.sh -s shell
	assert_success
	assert [ ! -e "${HOME}/.bash_profile" ]
}

@test '--prefix installs somewhere else and points the source line there' {
	local prefix="${BATS_TEST_TMPDIR}/elsewhere"
	run setup-system.sh -s shell --prefix "${prefix}"
	assert_success
	assert [ -f "${prefix}/bashrc.sh" ]
	run grep -qF "${prefix}/bashrc.sh" "${HOME}/.bashrc"
	assert_success
}

@test 'installed bashrc is syntactically valid bash' {
	setup-system.sh -s shell >/dev/null
	run bash -n "${HOME}/.config/just-bashit/bashrc.sh"
	assert_success
}

@test 'installed profile is syntactically valid sh' {
	setup-system.sh -s shell >/dev/null
	run sh -n "${HOME}/.config/just-bashit/profile.sh"
	assert_success
}

@test 'installed profile sets PATH and starts no agent when one exists' {
	setup-system.sh -s shell >/dev/null
	mkdir -p "${HOME}/.local/bin"
	run bash -c ". '${HOME}/.config/just-bashit/profile.sh'; echo \"\${PATH}\""
	assert_success
	assert_output --partial "${HOME}/.local/bin"
}

@test 'the ssh-agent bootstrap does not hold the caller output pipe' {
	command -v ssh-agent >/dev/null 2>&1 || skip "ssh-agent not installed"
	setup-system.sh -s shell >/dev/null
	local rt="${BATS_TEST_TMPDIR}/rt"
	mkdir -p "${rt}"
	chmod 700 "${rt}"

	# The regression: starting the agent through `eval "$(ssh-agent ...)"`
	# hands the daemon the write end of a pipe, which it never closes, so
	# anything reading that pipe waits forever. Here the reader is a
	# `timeout`ed cat, which turns "waits forever" into a failed assertion
	# instead of a hung suite — the reader must die on its own, because
	# killing the writer would leave the orphaned agent holding the pipe.
	# SSH_AUTH_SOCK is unset for the inner shell on purpose: with one
	# inherited the bootstrap correctly adopts it and starts nothing, which
	# is the path this test is not about.
	#
	# `3>&-` closes bats' own TAP descriptor before the agent can inherit
	# it. Redirecting the daemon's 0/1/2 is not enough on its own — any fd
	# above 2 that happens to be open gets inherited too, and bats' fd 3 is
	# read by its formatter, so an agent holding it hangs the run just as
	# thoroughly as one holding stdout.
	run bash -c "env -u SSH_AUTH_SOCK XDG_RUNTIME_DIR='${rt}' JB_SSH_AGENT=1 \
		bash -c '. \"${HOME}/.config/just-bashit/profile.sh\"; \
		         printf %s \"\$SSH_AGENT_PID\" > \"${rt}/agent.pid\"; \
		         echo done' 3>&- \
		| timeout 15 cat"
	assert_success
	assert_output --partial "done"
	assert [ -S "${rt}/just-bashit-agent.sock" ]
	assert [ -s "${rt}/agent.pid" ]
}

@test 'installed bashrc is a no-op for non-interactive shells' {
	setup-system.sh -s shell >/dev/null
	run bash -c ". '${HOME}/.config/just-bashit/bashrc.sh'; echo \"rc=\${JB_BASHRC:-unset}\""
	assert_success
	assert_output --partial "rc=unset"
}

@test 'installed bashrc binds the arrow keys in an interactive shell' {
	setup-system.sh -s shell >/dev/null
	run bash --norc -ic ". '${HOME}/.config/just-bashit/bashrc.sh'; bind -q history-search-backward"
	assert_success
	# Readline renders ESC as \e on some builds and \M- on others (Debian's
	# prints "\M-[A"), so match the rendering-independent tail.
	assert_output --regexp '\\(e|M-)\[A'
}

@test 'installed bashrc sources profile when no login shell has' {
	setup-system.sh -s shell >/dev/null
	run bash --norc -ic ". '${HOME}/.config/just-bashit/bashrc.sh'; echo \"pf=\${JB_PROFILE:-unset}\""
	assert_success
	assert_output --partial "pf=1"
}

@test 'bashrc.d drop-ins are sourced' {
	setup-system.sh -s shell >/dev/null
	echo 'JB_DROPIN=yes' >"${HOME}/.config/just-bashit/bashrc.d/99-test.sh"
	run bash --norc -ic ". '${HOME}/.config/just-bashit/bashrc.sh'; echo \"d=\${JB_DROPIN:-unset}\""
	assert_success
	assert_output --partial "d=yes"
}

@test 'JB_PROMPT=0 leaves PS1 alone' {
	setup-system.sh -s shell >/dev/null
	run bash --norc -ic "JB_PROMPT=0; . '${HOME}/.config/just-bashit/bashrc.sh'; echo \"pc=\${PROMPT_COMMAND:-unset}\""
	assert_success
	refute_output --partial "_jb_prompt"
}

# ---------------------------------------------------------------------------
# ssh step
# ---------------------------------------------------------------------------

@test 'ssh step generates no key during a dry run' {
	run setup-system.sh -n -s ssh
	assert_success
	assert [ ! -e "${HOME}/.ssh" ]
}

@test 'ssh step skips cleanly when ssh-keygen is unavailable' {
	# A PATH containing only what the script needs to reach the ssh step,
	# which is everything except ssh-keygen itself: the step still fixes
	# permissions, and only generation needs the binary.
	local stub="${BATS_TEST_TMPDIR}/stub" cmd
	mkdir -p "${stub}"
	for cmd in bash dirname tr mkdir chmod; do
		ln -sf "$(command -v "${cmd}")" "${stub}/${cmd}"
	done
	run env PATH="${stub}" \
		bash "${PROJECT_ROOT}/src/just_bashit/setup-system.sh" -s ssh
	assert_success
	assert_output --partial "skipping"
}

@test 'ssh step does not replace an existing key' {
	mkdir -p "${HOME}/.ssh"
	touch "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_ed25519.pub"
	run setup-system.sh -s ssh
	assert_success
	assert_output --partial "not generating another"
	assert_equal "$(cat "${HOME}/.ssh/id_ed25519")" ""
}

@test 'ssh step creates a key and prints it' {
	command -v ssh-keygen >/dev/null 2>&1 || skip "ssh-keygen not installed"
	run setup-system.sh -y -s ssh
	assert_success
	assert_output --partial "ssh-ed25519"
	assert_output --partial "EMPTY passphrase"
	assert_equal "$(find "${HOME}/.ssh" -name '*.pub' | wc -l)" 1
}

@test 'ssh step honours --key-name' {
	command -v ssh-keygen >/dev/null 2>&1 || skip "ssh-keygen not installed"
	run setup-system.sh -y -s ssh --key-name testkey
	assert_success
	assert [ -f "${HOME}/.ssh/testkey" ]
	assert [ -f "${HOME}/.ssh/testkey.pub" ]
}

@test 'ssh step tightens ~/.ssh permissions' {
	command -v ssh-keygen >/dev/null 2>&1 || skip "ssh-keygen not installed"
	mkdir -p "${HOME}/.ssh"
	chmod 777 "${HOME}/.ssh"
	run setup-system.sh -y -s ssh
	assert_success
	assert_equal "$(ls -ld "${HOME}/.ssh" | cut -c1-10)" "drwx------"
}

# ---------------------------------------------------------------------------
# git step
# ---------------------------------------------------------------------------

@test 'git step sets the defaults' {
	command -v git >/dev/null 2>&1 || skip "git not installed"
	run setup-system.sh -s git
	assert_success
	assert_equal "$(git config --global --get init.defaultBranch)" "main"
	assert_equal "$(git config --global --get pull.rebase)" "true"
	assert_equal "$(git config --global --get fetch.prune)" "true"
}

@test 'git step never sets an identity' {
	command -v git >/dev/null 2>&1 || skip "git not installed"
	run setup-system.sh -s git
	assert_success
	assert_output --partial "user.name / user.email deliberately untouched"
	run git config --global --get user.email
	assert_failure
}

@test 'git step does not overwrite an existing value' {
	command -v git >/dev/null 2>&1 || skip "git not installed"
	git config --global pull.rebase false
	run setup-system.sh -s git
	assert_success
	assert_equal "$(git config --global --get pull.rebase)" "false"
}

@test 'git step is idempotent' {
	command -v git >/dev/null 2>&1 || skip "git not installed"
	setup-system.sh -s git >/dev/null
	run setup-system.sh -s git
	assert_success
	assert_output --partial "0 default(s) set"
}

# ---------------------------------------------------------------------------
# deps step
# ---------------------------------------------------------------------------

@test 'deps step skips when there is no deps file' {
	run setup-system.sh -n -s deps
	assert_success
	assert_output --partial "nothing to install"
	assert_output --partial "skipped"
}

@test 'deps step delegates to install-deps' {
	_write_deps_toml jb.toml
	run setup-system.sh -n -s deps
	assert_success
	assert_output --partial "installing packages from jb.toml"
	assert_output --partial "curl"
}

@test 'deps step prefers jb-deps.toml over jb.toml' {
	_write_deps_toml jb-deps.toml
	printf '[runtime.apt]\npackages = ["wget"]\n' >jb.toml
	run setup-system.sh -n -s deps
	assert_success
	assert_output --partial "installing packages from jb-deps.toml"
}
