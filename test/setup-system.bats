# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, HELP_REGEX, PROJECT_ROOT set by bats/common-setup
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
	assert_output --partial "pwsh —"
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
	if [[ ${OSTYPE:-} == msys* || ${OSTYPE:-} == cygwin* ]]; then
		skip "ssh step is not designed for Windows yet: a PATH-restricted \
ssh-keygen removal is not reproducible under MSYS2"
	fi
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
	if [[ ${OSTYPE:-} == msys* || ${OSTYPE:-} == cygwin* ]]; then
		skip "ssh step is not designed for Windows yet: Unix mode bits \
(drwx------) do not map onto the Windows filesystem"
	fi
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
	run setup-system.sh -s git </dev/null
	assert_success
	assert_equal "$(git config --global --get init.defaultBranch)" "main"
	assert_equal "$(git config --global --get pull.rebase)" "true"
	assert_equal "$(git config --global --get fetch.prune)" "true"
}

@test 'git step takes the identity from GIT_AUTHOR_NAME / GIT_AUTHOR_EMAIL' {
	command -v git >/dev/null 2>&1 || skip "git not installed"
	GIT_AUTHOR_NAME="Ada" GIT_AUTHOR_EMAIL="ada@example.com" \
		run setup-system.sh -s git </dev/null
	assert_success
	assert_equal "$(git config --global --get user.name)" "Ada"
	assert_equal "$(git config --global --get user.email)" "ada@example.com"
}

@test 'git step never overwrites an existing identity' {
	command -v git >/dev/null 2>&1 || skip "git not installed"
	git config --global user.email mine@example.com
	GIT_AUTHOR_EMAIL="other@example.com" run setup-system.sh -s git </dev/null
	assert_success
	assert_equal "$(git config --global --get user.email)" "mine@example.com"
}

# Not a terminal and nothing in the environment: say so, never guess. This is
# also the path every CI run takes, so it must not block on a read.
@test 'git step warns rather than guesses when it cannot ask' {
	command -v git >/dev/null 2>&1 || skip "git not installed"
	unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL
	run setup-system.sh -s git </dev/null
	assert_success
	assert_output --partial "user.email is not set — run: git config --global user.email"
	run git config --global --get user.email
	assert_failure
}

# The prompt needs a real terminal, which `script` supplies. util-linux's
# `-c` form; BSD script differs, so it is skipped there rather than faked.
@test 'git step asks for an unset identity at a terminal' {
	command -v git >/dev/null 2>&1 || skip "git not installed"
	script -qec true /dev/null >/dev/null 2>&1 || skip "no util-linux script"
	unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL
	run script -qec "setup-system.sh -s git" /dev/null \
		< <(printf 'Ada\nada@example.com\n')
	assert_success
	assert_equal "$(git config --global --get user.name)" "Ada"
	assert_equal "$(git config --global --get user.email)" "ada@example.com"
}

@test 'git step does not overwrite an existing value' {
	command -v git >/dev/null 2>&1 || skip "git not installed"
	git config --global pull.rebase false
	run setup-system.sh -s git </dev/null
	assert_success
	assert_equal "$(git config --global --get pull.rebase)" "false"
}

@test 'git step is idempotent' {
	command -v git >/dev/null 2>&1 || skip "git not installed"
	setup-system.sh -s git </dev/null >/dev/null
	run setup-system.sh -s git </dev/null
	assert_success
	assert_output --partial "0 default(s) set"
}

# ---------------------------------------------------------------------------
# deps step
# ---------------------------------------------------------------------------

# The fresh-machine case: run from a directory with no manifest, as from
# $HOME. It used to install nothing, which left a new box with no compiler.
# cmake is in every manager's baseline, so it is the host-independent tell.
@test 'deps step installs the baseline toolchain with no deps file' {
	run setup-system.sh -n -s deps
	assert_success
	assert_output --partial "installing packages from the baseline toolchain"
	assert_output --partial "cmake"
	assert_output --partial "deps:    ok (baseline toolchain)"
	refute_output --partial "skipped"
}

@test 'deps step delegates to install-deps' {
	_write_deps_toml jb.toml
	run setup-system.sh -n -s deps
	assert_success
	assert_output --partial "installing packages from the baseline toolchain"
	assert_output --partial "installing packages from jb.toml"
	assert_output --partial "curl"
	assert_output --partial "deps:    ok (baseline toolchain + jb.toml)"
}

# Every manager install-deps can drive must have a baseline, or the fresh
# machine on that manager is back to installing nothing. The manager list is
# read from install-deps' own dispatch, so adding a manager there without a
# baseline here fails this test rather than needing someone to remember.
@test 'baseline covers every package manager install-deps supports' {
	local src="${BATS_TEST_DIRNAME}/../src/just_bashit"
	local managers baseline m pkgs
	managers=$(sed -n '/^_do_install()/,/^}/p' "${src}/install-deps.sh" |
		sed -n 's/^\t\([a-z0-9]*\))$/\1/p')
	# A parser that finds nothing would pass the loop below vacuously.
	[ "$(wc -w <<<"${managers}")" -ge 7 ]

	baseline=$(sed -n "/^read -r -d '' _BASELINE_TOML/,/^EOF/p" \
		"${src}/setup-system.sh" | sed '1d;$d' | sed 's/^\t//')
	[ -n "${baseline}" ]

	# shellcheck source=/dev/null
	source "${src}/toml.sh"
	for m in ${managers}; do
		pkgs=$(toml_get_array baseline "${m}" packages <<<"${baseline}")
		[ -n "${pkgs}" ] || {
			echo "no [baseline.${m}] packages in setup-system.sh" >&2
			return 1
		}
	done
}

@test 'deps step prefers jb-deps.toml over jb.toml' {
	_write_deps_toml jb-deps.toml
	printf '[runtime.apt]\npackages = ["wget"]\n' >jb.toml
	run setup-system.sh -n -s deps
	assert_success
	assert_output --partial "installing packages from jb-deps.toml"
}

# ---------------------------------------------------------------------------
# ssh permissions
#
# The case these cover is a ~/.ssh that arrived from somewhere unable to
# carry POSIX modes -- a Windows filesystem under WSL, a FAT stick, a zip, a
# git checkout. rsync -a and tar preserve modes, so a Linux-to-Linux copy
# needs none of this; these are the crossings where no copy command helps.
# ---------------------------------------------------------------------------

# `stat -c` is GNU; BSD stat (macOS) wants -f '%Lp'. Both are tried rather
# than branching on OSTYPE, which would guess where it can measure.
_mode() {
	stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

# Skip where the filesystem does not honour chmod at all -- MSYS2 on NTFS
# reports what it likes. Probing beats naming platforms: it skips exactly
# where the assertion is meaningless, and nowhere else.
_require_modes() {
	local probe="${BATS_TEST_TMPDIR}/mode-probe"
	: >"${probe}"
	chmod 0600 "${probe}" 2>/dev/null || skip "chmod unavailable"
	[[ "$(_mode "${probe}")" == "600" ]] || skip "filesystem ignores chmod"
}

# A private key is identified by its PEM header, so the fixture needs one.
_write_key() {
	{
		echo '-----BEGIN OPENSSH PRIVATE KEY-----'
		echo 'b3BlbnNzaA=='
		echo '-----END OPENSSH PRIVATE KEY-----'
	} >"$1"
}

@test 'ssh step strips group and other from a world-readable private key' {
	_require_modes
	mkdir -p "${HOME}/.ssh"
	_write_key "${HOME}/.ssh/id_ed25519"
	touch "${HOME}/.ssh/id_ed25519.pub"
	chmod 0777 "${HOME}/.ssh/id_ed25519"
	run setup-system.sh -s ssh
	assert_success
	assert_equal "$(_mode "${HOME}/.ssh/id_ed25519")" "700"
}

@test 'ssh step hardens a key that has no matching .pub' {
	# Name-based detection would miss this one; the PEM header does not.
	_require_modes
	mkdir -p "${HOME}/.ssh"
	_write_key "${HOME}/.ssh/some-odd-name"
	touch "${HOME}/.ssh/other.pub" "${HOME}/.ssh/other"
	chmod 0644 "${HOME}/.ssh/some-odd-name"
	run setup-system.sh -s ssh
	assert_success
	assert_equal "$(_mode "${HOME}/.ssh/some-odd-name")" "600"
}

@test 'ssh step hardens config and authorized_keys' {
	_require_modes
	mkdir -p "${HOME}/.ssh"
	touch "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_ed25519.pub"
	printf 'Host x\n' >"${HOME}/.ssh/config"
	printf 'ssh-ed25519 AAAA\n' >"${HOME}/.ssh/authorized_keys"
	chmod 0666 "${HOME}/.ssh/config" "${HOME}/.ssh/authorized_keys"
	run setup-system.sh -s ssh
	assert_success
	assert_equal "$(_mode "${HOME}/.ssh/config")" "600"
	assert_equal "$(_mode "${HOME}/.ssh/authorized_keys")" "600"
}

@test 'ssh step only tightens: a 0400 key keeps 0400' {
	# A literal `chmod 600` would hand this key owner-write it did not ask
	# for. go-rwx leaves the owner bits alone.
	_require_modes
	mkdir -p "${HOME}/.ssh"
	_write_key "${HOME}/.ssh/id_ed25519"
	touch "${HOME}/.ssh/id_ed25519.pub"
	chmod 0400 "${HOME}/.ssh/id_ed25519"
	run setup-system.sh -s ssh
	assert_success
	assert_equal "$(_mode "${HOME}/.ssh/id_ed25519")" "400"
}

@test 'ssh step leaves a .pub file alone' {
	_require_modes
	mkdir -p "${HOME}/.ssh"
	touch "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_ed25519.pub"
	chmod 0644 "${HOME}/.ssh/id_ed25519.pub"
	run setup-system.sh -s ssh
	assert_success
	assert_equal "$(_mode "${HOME}/.ssh/id_ed25519.pub")" "644"
}

@test 'ssh step does not touch a file that is neither a key nor named' {
	# known_hosts is not secret and not a key; rewriting it would be churn.
	_require_modes
	mkdir -p "${HOME}/.ssh"
	touch "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_ed25519.pub"
	printf 'host ssh-ed25519 AAAA\n' >"${HOME}/.ssh/known_hosts"
	chmod 0644 "${HOME}/.ssh/known_hosts"
	run setup-system.sh -s ssh
	assert_success
	assert_equal "$(_mode "${HOME}/.ssh/known_hosts")" "644"
}

@test 'ssh step hardens a subdirectory' {
	_require_modes
	mkdir -p "${HOME}/.ssh/sockets"
	touch "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_ed25519.pub"
	chmod 0777 "${HOME}/.ssh/sockets"
	run setup-system.sh -s ssh
	assert_success
	assert_equal "$(_mode "${HOME}/.ssh/sockets")" "700"
}

@test 'ssh step hardening is idempotent' {
	_require_modes
	mkdir -p "${HOME}/.ssh"
	_write_key "${HOME}/.ssh/id_ed25519"
	touch "${HOME}/.ssh/id_ed25519.pub"
	chmod 0777 "${HOME}/.ssh/id_ed25519"
	run setup-system.sh -s ssh
	assert_success
	local first
	first="$(_mode "${HOME}/.ssh/id_ed25519")"
	run setup-system.sh -s ssh
	assert_success
	assert_equal "$(_mode "${HOME}/.ssh/id_ed25519")" "${first}"
}

@test 'ssh step changes no mode on disk during a dry run' {
	_require_modes
	mkdir -p "${HOME}/.ssh"
	_write_key "${HOME}/.ssh/id_ed25519"
	touch "${HOME}/.ssh/id_ed25519.pub"
	chmod 0777 "${HOME}/.ssh/id_ed25519"
	run setup-system.sh -n -s ssh
	assert_success
	assert_equal "$(_mode "${HOME}/.ssh/id_ed25519")" "777"
}

# ---------------------------------------------------------------------------
# pwsh step
#
# Every case pins the platform with JB_UNAME_S/JB_UNAME_M rather than by
# editing PATH. PATH cannot do this job: /bin is a symlink to /usr/bin on
# Debian, so a command hidden from one is still found through the other, and
# a test that "passed" that way would pass with the step deleted.
#
# All of them are dry runs. The real step writes to /opt and /usr/bin, which
# is not something a test suite may do to the machine running it.
# ---------------------------------------------------------------------------

# The pinned version, read from the script rather than restated here: a test
# carrying its own copy would keep passing after a bump that touched only the
# URL, which is the drift worth catching.
_ps_ver() {
	sed -n 's/^_PS_VER="\(.*\)"$/\1/p' \
		"${PROJECT_ROOT}/src/just_bashit/setup-system.sh"
}

@test 'pwsh step derives the x64 tarball on x86_64' {
	local ver
	ver="$(_ps_ver)"
	assert [ -n "${ver}" ]
	run env JB_UNAME_S=Linux JB_UNAME_M=x86_64 setup-system.sh -n -s pwsh
	assert_success
	assert_output --partial "powershell-${ver}-linux-x64.tar.gz"
	assert_output --partial "/releases/download/v${ver}/"
}

@test 'pwsh step derives the arm64 tarball on aarch64' {
	run env JB_UNAME_S=Linux JB_UNAME_M=aarch64 setup-system.sh -n -s pwsh
	assert_success
	assert_output --partial "linux-arm64.tar.gz"
	refute_output --partial "linux-x64.tar.gz"
}

@test 'pwsh step derives the arm64 tarball when uname says arm64' {
	run env JB_UNAME_S=Linux JB_UNAME_M=arm64 setup-system.sh -n -s pwsh
	assert_success
	assert_output --partial "linux-arm64.tar.gz"
}

@test 'pwsh step derives the arm32 tarball on armv7l' {
	run env JB_UNAME_S=Linux JB_UNAME_M=armv7l setup-system.sh -n -s pwsh
	assert_success
	assert_output --partial "linux-arm32.tar.gz"
}

@test 'pwsh step downloads nothing for an architecture with no build' {
	run env JB_UNAME_S=Linux JB_UNAME_M=riscv64 setup-system.sh -n -s pwsh
	assert_success
	assert_output --partial "no PowerShell build for riscv64"
	assert_output --partial "pwsh:    skipped"
	refute_output --partial "releases/download"
}

@test 'pwsh step links the unpacked tree onto PATH' {
	run env JB_UNAME_S=Linux JB_UNAME_M=x86_64 setup-system.sh -n -s pwsh
	assert_success
	assert_output --partial "/opt/microsoft/powershell/7"
	# -f, not a bare ln: re-running the step is how an upgrade lands, and a
	# second ln over the existing link is an error rather than a no-op.
	assert_output --regexp "ln -sf .*/pwsh /usr/bin/pwsh"
}

@test 'pwsh step never fetches a linux tarball on macOS' {
	run env JB_UNAME_S=Darwin JB_UNAME_M=arm64 setup-system.sh -n -s pwsh
	assert_success
	refute_output --partial "linux-arm64.tar.gz"
	refute_output --partial "releases/download"
}

@test 'pwsh step skips a platform it cannot provision' {
	run env JB_UNAME_S=MINGW64_NT-10.0 JB_UNAME_M=x86_64 \
		setup-system.sh -n -s pwsh
	assert_success
	assert_output --partial "pwsh:    skipped"
	refute_output --partial "releases/download"
}

@test 'pwsh step installs PSScriptAnalyzer for the current user only' {
	run env JB_UNAME_S=Linux JB_UNAME_M=x86_64 setup-system.sh -n -s pwsh
	assert_success
	assert_output --partial "Install-Module PSScriptAnalyzer -Scope CurrentUser -Force"
}

@test 'pwsh step downloads nothing during a dry run' {
	# TMPDIR is where the tarball would land, pointed somewhere this test
	# can inspect — otherwise "no file appeared" proves nothing.
	run env TMPDIR="${BATS_TEST_TMPDIR}" JB_UNAME_S=Linux JB_UNAME_M=x86_64 \
		setup-system.sh -n -s pwsh
	assert_success
	assert_output --partial "${BATS_TEST_TMPDIR}/powershell-$(_ps_ver)-linux-x64.tar.gz"
	assert [ ! -e "${BATS_TEST_TMPDIR}/powershell-$(_ps_ver)-linux-x64.tar.gz" ]
}

# ---------------------------------------------------------------------------
# The step list is declared in four places — the array, the string, --help
# and the docs table. These two keep them from drifting apart; the array and
# the string are already covered by every step running above.
# ---------------------------------------------------------------------------

# The steps this build actually knows, taken from the error the validator
# prints rather than restated here.
_known_steps() {
	setup-system.sh -n -s bogus 2>&1 | sed -n 's/.*known steps: //p'
}

@test 'every known step is described in --help' {
	local steps help_out step
	steps="$(_known_steps)"
	assert [ -n "${steps}" ]
	help_out="$(setup-system.sh --help)"
	for step in ${steps}; do
		echo "${help_out}" | grep -qE "^  ${step}[[:space:]]+[A-Z]" ||
			fail "step '${step}' has no entry in the --help step list"
	done
}

@test 'every known step is in the docs steps table' {
	local steps step
	steps="$(_known_steps)"
	assert [ -n "${steps}" ]
	for step in ${steps}; do
		grep -qE "^\| \`${step}\`" \
			"${PROJECT_ROOT}/docs/setup-system.md" ||
			fail "step '${step}' has no row in docs/setup-system.md"
	done
}
