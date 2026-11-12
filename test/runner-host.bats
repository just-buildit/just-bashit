# shellcheck disable=SC2154  # BATS_TEST_TMPDIR, HELP_REGEX set by bats/common-setup
load 'test_helper/common-setup'
_common_setup

# tart and curl are stubbed: CI has Linux runners, and the one thing worth
# proving offline is the contract with them -- which VM is cloned, booted
# and always deleted, and that the PAT reaches curl only on stdin and never
# enters a VM. Every stub call is logged with its argv, so a secret on any
# command line shows up in the log and fails the test.
setup() {
	# runner-host is macOS-only, and Windows jq writes CRLF, which no name
	# survives. The tests prove the host logic, so they run on every
	# Linux and macOS leg instead.
	case "$(uname -s)" in
	MINGW* | MSYS*) skip "runner-host is macOS-only; not tested on Windows" ;;
	*) ;;
	esac
	# jq is real: the script parses with it. bootstrap.toml installs it on
	# every other CI leg, so missing it there FAILS rather than skips.
	if ! command -v jq >/dev/null 2>&1; then
		[[ -z ${CI:-} ]] || fail "jq is not installed: bootstrap.toml must install it on every CI leg"
		skip "jq is not installed"
	fi
	STUBS="${BATS_TEST_TMPDIR}/stubs"
	LOG="${BATS_TEST_TMPDIR}/calls.log"
	STATE="${BATS_TEST_TMPDIR}/vms"
	REGISTERED="${BATS_TEST_TMPDIR}/registered"
	export STUBS LOG STATE REGISTERED
	mkdir -p "${STUBS}" "${STATE}"
	: >"${LOG}"
	: >"${REGISTERED}"
	touch "${STATE}/jb-base"

	printf 'pat-SECRET-123\n' >"${BATS_TEST_TMPDIR}/token"
	chmod 600 "${BATS_TEST_TMPDIR}/token"
	export JB_RUNNER_TOKEN_FILE="${BATS_TEST_TMPDIR}/token"
	export JB_RUNNER_OS=Darwin
	export JB_RUNNER_BOOT_TIMEOUT=10
	export JB_RUNNER_LOCK="${BATS_TEST_TMPDIR}/lock"
	export JB_RUNNER_HOST_TAG=testhost
	# The CI containers run as root, which install refuses. Stand in as a
	# user; the refuse-root test sets 0.
	export JB_RUNNER_EUID=4242
	# One slot unless a test says otherwise, so counts stay simple; the
	# two-slot tests set 2, and one checks 2 is the default.
	export JB_RUNNER_VMS=1

	# A tart that keeps its VMs as files, so clone/delete/list agree.
	cat >"${STUBS}/tart" <<-'EOF'
		#!/bin/bash
		printf 'tart %s\n' "$*" >>"${LOG}"
		case "$1" in
		list)
			printf '['; sep=''
			for f in "${STATE}"/*; do
				[ -e "$f" ] || continue
				printf '%s{"Name":"%s","State":"stopped"}' "$sep" "${f##*/}"; sep=,
			done
			printf ']\n' ;;
		clone)
			touch "${STATE}/$3"
			# A clone that dies halfway still leaves a VM on disk.
			exit "${TART_CLONE_RC:-0}" ;;
		delete) rm -f "${STATE}/$2" ;;
		rename) mv "${STATE}/$2" "${STATE}/$3" ;;
		run)
			# Which softnet tart would find: the first on its PATH.
			printf 'tart-softnet %s\n' "$(command -v softnet)" >>"${LOG}"
			sleep 0.1 ;;
		exec)
			shift
			# The boot probe always answers; only the job can fail.
			[ "$1" = -i ] || exit 0
			shift
			printf 'stdin %s\n' "$(cat)" >>"${LOG}"
			# The runner registers with GitHub, which outlives the VM.
			printf '%s\n' "$1" >>"${REGISTERED}"
			# A job that waits for work, as a real idle runner does.
			[ -n "${TART_EXEC_SLEEP:-}" ] && exec sleep "${TART_EXEC_SLEEP}"
			# A job that fails in one slot only.
			case "$1" in *"-${TART_EXEC_FAIL_SLOT:-none}-"*) exit 3 ;; esac
			exit "${TART_EXEC_RC:-0}" ;;
		esac
	EOF

	# A curl that records its argv and its stdin (where the header goes).
	cat >"${STUBS}/curl" <<-'EOF'
		#!/bin/bash
		printf 'curl %s\n' "$*" >>"${LOG}"
		if [[ " $* " == *" @- "* ]]; then
			hdr="$(cat)"
			printf 'curl-stdin %s\n' "${hdr}" >>"${LOG}"
			# One line, one write: which PAT went to which URL, even with
			# two slots calling at once.
			printf 'curl-as %s %s\n' "${@: -1}" "${hdr}" >>"${LOG}"
		fi
		case "$*" in
		*registration-token*) printf '{"token":"REG-TOKEN-456"}\n' ;;
		*-X\ DELETE*) ;;
		*/runners*)
			# Every runner a VM registered, as GitHub still lists one whose
			# VM was killed mid-wait.
			printf '{"runners":['; sep=''
			while read -r name; do
				printf '%s{"id":7,"name":"%s"}' "$sep" "$name"; sep=,
			done <"${REGISTERED}"
			printf ']}\n' ;;
		esac
	EOF
	# sudo runs the command unprivileged, so install writes where told.
	cat >"${STUBS}/sudo" <<-'EOF'
		#!/bin/bash
		printf 'sudo %s\n' "$*" >>"${LOG}"
		[ "$1" = install ] && cp "${@: -2:1}" "${@: -1}"
		exit 0
	EOF
	printf '#!/bin/bash\nexit 0\n' >"${STUBS}/launchctl"
	# Its own directory, as /usr/local/bin is. Only its owner and mode are
	# checked; tart, which would run it, is a stub. The tests cannot make
	# root-owned files, so this uid is trusted beside root, and the
	# directories above it lose any group or other write a umask gave them.
	SBIN="${BATS_TEST_TMPDIR}/sbin"
	export SBIN
	mkdir -p "${SBIN}"
	printf '#!/bin/bash\nexit 0\n' >"${SBIN}/softnet"
	chmod 4755 "${SBIN}/softnet"
	export JB_RUNNER_SOFTNET="${SBIN}/softnet"
	JB_RUNNER_TRUSTED_UID="$(id -u)"
	export JB_RUNNER_TRUSTED_UID
	local d="${SBIN}"
	while [[ ${d} != / ]]; do
		# macOS's per-user temp root refuses chmod; it is mode 700 anyway.
		if [[ -O ${d} ]]; then chmod go-w "${d}" 2>/dev/null || :; fi
		d="$(dirname "${d}")"
	done
	chmod +x "${STUBS}/tart" "${STUBS}/curl" "${STUBS}/sudo" "${STUBS}/launchctl"
	PATH="${STUBS}:${PATH}"
}

# org-b's own PAT, beside the default one, as token.<org>.
_org_b_token() {
	printf 'pat-OTHER-789\n' >"${BATS_TEST_TMPDIR}/token.org-b"
	chmod 600 "${BATS_TEST_TMPDIR}/token.org-b"
}

@test 'runner-host --help prints usage' {
	run runner-host.sh --help
	assert_success
	assert_output --regexp "${HELP_REGEX}"
}

@test 'runner-host refuses no command and an unknown one' {
	run runner-host.sh
	assert_failure
	assert_output --partial 'no command'
	run runner-host.sh frobnicate
	assert_failure
	assert_output --partial 'unknown argument'
}

@test 'runner-host refuses to run off macOS' {
	JB_RUNNER_OS=Linux run runner-host.sh run --once
	assert_failure
	assert_output --partial 'macOS only'
}

@test 'run --once: clones, boots, runs one job, deletes the VM' {
	run runner-host.sh run --once
	assert_success
	# The host is in the name, so two hosts' runners never --replace each
	# other.
	run grep -c '^tart clone jb-base jb-job-testhost-s1-' "${LOG}"
	assert_output 1
	run grep -E '^tart delete jb-job-' "${LOG}"
	assert_success
	# Only the image is left.
	run ls "${STATE}"
	assert_output jb-base
}

@test 'run --once: the PAT goes to curl on stdin, and never into a VM' {
	run runner-host.sh run --once
	assert_success
	run grep -F 'curl-stdin Authorization: Bearer pat-SECRET-123' "${LOG}"
	assert_success
	# On no command line, and never in what a VM is sent.
	run grep -F 'pat-SECRET-123' <(grep -vE '^curl-(stdin|as) ' "${LOG}")
	assert_failure
	# The VM gets the short-lived registration token, on stdin.
	run grep -Fx 'stdin REG-TOKEN-456' "${LOG}"
	assert_success
	run grep -E '^tart .*REG-TOKEN-456' "${LOG}"
	assert_failure
}

@test 'run --once: a failed job still deletes its VM' {
	TART_EXEC_RC=3 run runner-host.sh run --once
	assert_failure 3
	run ls "${STATE}"
	assert_output jb-base
}

@test 'run: stale job VMs from a crash are deleted first' {
	touch "${STATE}/jb-job-1"
	run runner-host.sh run --once
	assert_success
	run grep -Fx 'tart delete jb-job-1' "${LOG}"
	assert_success
}

@test 'run: refuses a label shaped like a GitHub-hosted image' {
	local label
	for label in macos-latest ubuntu-24.04 windows-2025 MacOS-14 ' macos-latest'; do
		: >"${LOG}"
		JB_RUNNER_LABELS="self-hosted,${label}" run runner-host.sh run --once
		assert_failure
		assert_output --partial "refusing label ${label# }"
		# Refused before any token is minted or VM cloned.
		run cat "${LOG}"
		assert_output ''
	done
	# The default set is fine, and macOS alone is not an image name.
	run runner-host.sh run --once
	assert_success
}

@test 'run: no image is an error that names the fix' {
	rm "${STATE}/jb-base"
	run runner-host.sh run --once
	assert_failure
	assert_output --partial 'runner-host.sh image'
}

@test 'install --dry-run changes nothing' {
	JB_RUNNER_INSTALL_DIR="${BATS_TEST_TMPDIR}/libexec" \
		JB_RUNNER_PLIST="${BATS_TEST_TMPDIR}/daemon.plist" \
		run runner-host.sh --dry-run install
	assert_success
	assert_output --partial 'would: sudo launchctl bootstrap system'
	[ ! -e "${BATS_TEST_TMPDIR}/libexec" ]
	[ ! -e "${BATS_TEST_TMPDIR}/daemon.plist" ]
}

@test 'run: SIGTERM mid-job deletes the VM and deregisters its runner' {
	TART_EXEC_SLEEP=61.5 runner-host.sh run --once >"${BATS_TEST_TMPDIR}/out" 2>&1 &
	local pid=$!
	local _
	for _ in $(seq 50); do
		[ -s "${REGISTERED}" ] && break
		sleep 0.1
	done
	kill -TERM "${pid}"
	local rc=0
	wait "${pid}" || rc=$?
	assert_equal "${rc}" 143
	run ls "${STATE}"
	assert_output jb-base
	run grep -E '^curl .*-X DELETE .*/actions/runners/7' "${LOG}"
	assert_success
	# The job's `tart exec` is ended too, not orphaned to run on.
	sleep 0.5
	run pgrep -f 'sleep 61.5'
	assert_failure
}

@test 'run: a token readable by others is refused' {
	chmod 644 "${JB_RUNNER_TOKEN_FILE}"
	run runner-host.sh run --once
	assert_failure
	assert_output --partial 'mode 644'
	run cat "${LOG}"
	assert_output ''
	chmod 400 "${JB_RUNNER_TOKEN_FILE}"
	run runner-host.sh run --once
	assert_success
}

@test 'run and image: a live lock refuses; a dead one is taken over' {
	sleep 30 &
	local live=$!
	mkdir "${JB_RUNNER_LOCK}"
	printf '%s\n' "${live}" >"${JB_RUNNER_LOCK}/pid"
	run runner-host.sh run --once
	assert_failure
	assert_output --partial "pid ${live}"
	run runner-host.sh image
	assert_failure
	assert_output --partial "pid ${live}"
	# Nothing was swept or cloned under the holder.
	run grep -E '^tart (clone|delete|stop)' "${LOG}"
	assert_failure
	kill "${live}"
	wait "${live}" || :
	run runner-host.sh run --once
	assert_success
	# And released on exit.
	[ ! -e "${JB_RUNNER_LOCK}" ]
}

@test 'run: a clone that fails halfway is deleted' {
	TART_CLONE_RC=1 run runner-host.sh run --once
	assert_failure
	run ls "${STATE}"
	assert_output jb-base
}

@test 'install: writes the effective configuration into the daemon' {
	_org_b_token
	JB_RUNNER_PLIST="${BATS_TEST_TMPDIR}/daemon.plist" \
		JB_RUNNER_INSTALL_DIR="${BATS_TEST_TMPDIR}/libexec" \
		JB_RUNNER_LABELS='self-hosted, macOS ,ARM64' \
		JB_RUNNER_IMAGE='a&b' \
		JB_RUNNER_ORG=org-a JB_RUNNER_ORGS='org-a,org-b' JB_RUNNER_VMS=2 \
		run runner-host.sh install
	assert_success
	local plist="${BATS_TEST_TMPDIR}/daemon.plist"
	run grep -F '<key>JB_RUNNER_LABELS</key><string>self-hosted,macOS,ARM64</string>' "${plist}"
	assert_success
	run grep -F '<key>JB_RUNNER_IMAGE</key><string>a&amp;b</string>' "${plist}"
	assert_success
	run grep -F '<key>JB_RUNNER_ORGS</key><string>org-a,org-b</string>' "${plist}"
	assert_success
	run grep -F '<key>JB_RUNNER_HOST_TAG</key><string>testhost</string>' "${plist}"
	assert_success
	if command -v plutil >/dev/null 2>&1; then
		run plutil -lint "${plist}"
		assert_success
	fi
}

@test 'install: refuses root, and a hosted-image label' {
	JB_RUNNER_EUID=0 run runner-host.sh --dry-run install
	assert_failure
	assert_output --partial 'not root'
	JB_RUNNER_LABELS='self-hosted,macos-latest' run runner-host.sh --dry-run install
	assert_failure
	assert_output --partial 'refusing label macos-latest'
}

@test 'uninstall: deregisters the runners of this host, and only them' {
	printf '%s\n' jb-job-testhost-1 jb-job-otherhost-1 >"${REGISTERED}"
	JB_RUNNER_PLIST="${BATS_TEST_TMPDIR}/daemon.plist" run runner-host.sh uninstall
	assert_success
	run grep -c -E '^curl .*-X DELETE ' "${LOG}"
	assert_output 1
}

@test 'run: every VM boots with the private ranges blocked' {
	run runner-host.sh run --once
	assert_success
	# This Mac (the VM's gateway), the LAN and the tailnet.
	run grep -E '^tart run --no-graphics --net-softnet-block=10\.0\.0\.0/8,172\.16\.0\.0/12,192\.168\.0\.0/16,100\.64\.0\.0/10 jb-job-' "${LOG}"
	assert_success
	run grep -E '^tart run' "${LOG}"
	refute_output --partial 'jb-job- '
	run grep -cE '^tart run ' "${LOG}"
	assert_output 1
}

@test 'run and image: refuse without a setuid softnet' {
	chmod 0755 "${SBIN}/softnet"
	run runner-host.sh run --once
	assert_failure
	assert_output --partial 'softnet is not installed setuid'
	run runner-host.sh image
	assert_failure
	assert_output --partial 'softnet is not installed setuid'
	run grep -E '^tart (clone|run)' "${LOG}"
	assert_failure
}

@test 'softnet: refused when anyone but root could replace it' {
	chmod 4775 "${SBIN}/softnet"
	run runner-host.sh run --once
	assert_failure
	assert_output --partial "${SBIN}/softnet is writable by group or other"
	chmod 4755 "${SBIN}/softnet"
	# Its directory: a writable one lets anyone swap the binary.
	chmod 777 "${SBIN}"
	run runner-host.sh run --once
	assert_failure
	assert_output --partial "${SBIN} is writable by group or other"
	chmod 755 "${SBIN}"
	# Owned by someone not trusted (here: this uid, once it is not). Root
	# owns every file under root, and root is always trusted, so this case
	# runs where the tests are not root (the macOS leg, a workstation).
	if [[ $(id -u) -ne 0 ]]; then
		JB_RUNNER_TRUSTED_UID=0 run runner-host.sh run --once
		assert_failure
		assert_output --partial "is owned by uid $(id -u), not root"
	fi
	# A symlink: what it points at can change under it.
	mv "${SBIN}/softnet" "${SBIN}/softnet.real"
	ln -s softnet.real "${SBIN}/softnet"
	run runner-host.sh run --once
	assert_failure
	assert_output --partial 'softnet is not installed at'
	run grep -E '^tart (clone|run)' "${LOG}"
	assert_failure
}

@test 'softnet: tart runs the pinned one, not one planted earlier on PATH' {
	local planted="${BATS_TEST_TMPDIR}/home-bin"
	mkdir -p "${planted}"
	printf '#!/bin/bash\nexit 0\n' >"${planted}/softnet"
	chmod 4755 "${planted}/softnet"
	PATH="${planted}:${PATH}" run runner-host.sh run --once
	assert_success
	run grep -Fx "tart-softnet ${SBIN}/softnet" "${LOG}"
	assert_success
}

@test 'run: a symlinked token is refused by name' {
	mv "${JB_RUNNER_TOKEN_FILE}" "${BATS_TEST_TMPDIR}/token.real"
	ln -s token.real "${JB_RUNNER_TOKEN_FILE}"
	run runner-host.sh run --once
	assert_failure
	assert_output --partial 'is a symlink; point JB_RUNNER_TOKEN_FILE at the file itself'
}

@test 'lock: a pid from an earlier boot is not a live holder' {
	# This test's own shell is alive; the boot time is not this boot's.
	mkdir "${JB_RUNNER_LOCK}"
	printf '%s 1\n' "$$" >"${JB_RUNNER_LOCK}/pid"
	run runner-host.sh run --once
	assert_success
	[ ! -e "${JB_RUNNER_LOCK}" ]
}

@test 'lock: an empty lock dir is waited for, then taken over' {
	mkdir "${JB_RUNNER_LOCK}"
	run runner-host.sh run --once
	assert_success
	[ ! -e "${JB_RUNNER_LOCK}" ]
	run ls "${BATS_TEST_TMPDIR}"
	refute_output --partial 'lock.stale'
}

@test 'install: every value in the plist is XML-escaped' {
	JB_RUNNER_PLIST="${BATS_TEST_TMPDIR}/daemon.plist" \
		JB_RUNNER_INSTALL_DIR="${BATS_TEST_TMPDIR}/lib<&>exec" \
		JB_RUNNER_LOG="${BATS_TEST_TMPDIR}/a&b.log" \
		run runner-host.sh install
	assert_success
	local plist="${BATS_TEST_TMPDIR}/daemon.plist"
	run grep -F 'lib&lt;&amp;&gt;exec/runner-host.sh</string>' "${plist}"
	assert_success
	run grep -cF 'a&amp;b.log</string>' "${plist}"
	assert_output 2
	run grep -F 'a&b' "${plist}"
	assert_failure
	if command -v plutil >/dev/null 2>&1; then
		run plutil -lint "${plist}"
		assert_success
	fi
}

@test 'gh-248: -- ends options; every word after it is a command word' {
	JB_RUNNER_OS=Linux run runner-host.sh --once -- run
	assert_failure
	assert_output --partial 'macOS only'
	run runner-host.sh -- --once
	assert_failure
	assert_output --partial 'unknown argument: --once'
}

@test 'slots: two by default, each its own VM, runner name and token' {
	unset JB_RUNNER_VMS
	run runner-host.sh run --once
	assert_success
	run grep -cE '^tart clone jb-base jb-job-testhost-s1-[0-9]+$' "${LOG}"
	assert_output 1
	run grep -cE '^tart clone jb-base jb-job-testhost-s2-[0-9]+$' "${LOG}"
	assert_output 1
	# A registration token each, minted separately.
	run grep -c '^curl .*registration-token' "${LOG}"
	assert_output 2
	# Each runner registered under its own VM's name.
	run sort -u "${REGISTERED}"
	assert_line --regexp '^jb-job-testhost-s1-[0-9]+$'
	assert_line --regexp '^jb-job-testhost-s2-[0-9]+$'
	# And the PAT still never left curl's stdin.
	run grep -F 'pat-SECRET-123' <(grep -vE '^curl-(stdin|as) ' "${LOG}")
	assert_failure
	run ls "${STATE}"
	assert_output jb-base
}

@test 'slots: more than two, or none, is refused before anything runs' {
	local n
	# (Empty is unset: the default, like every JB_RUNNER_* setting.)
	for n in 3 0 two 12; do
		: >"${LOG}"
		JB_RUNNER_VMS="${n}" run runner-host.sh run --once
		assert_failure
		assert_output --partial "it must be 1 or 2"
		run cat "${LOG}"
		assert_output ''
	done
	JB_RUNNER_VMS=3 run runner-host.sh --dry-run install
	assert_failure
	assert_output --partial "it must be 1 or 2"
}

@test 'slots: one failing does not stop the other' {
	TART_EXEC_FAIL_SLOT=s1 JB_RUNNER_VMS=2 run runner-host.sh run --once
	assert_failure 3
	assert_output --regexp 'jb-job-testhost-s1-[0-9]+ finished \(exit 3\)'
	assert_output --regexp 'jb-job-testhost-s2-[0-9]+ finished \(exit 0\)'
	run ls "${STATE}"
	assert_output jb-base
}

@test 'slots: SIGTERM deletes every VM and deregisters every runner' {
	# Jobs that would wait 300 s: the loop must end them, not outlast them.
	JB_RUNNER_VMS=2 TART_EXEC_SLEEP=300.5 runner-host.sh run --once >"${BATS_TEST_TMPDIR}/out" 2>&1 &
	local pid=$! _
	for _ in $(seq 50); do
		[ "$(wc -l <"${REGISTERED}")" -ge 2 ] && break
		sleep 0.1
	done
	kill -TERM "${pid}"
	for _ in $(seq 100); do
		kill -0 "${pid}" 2>/dev/null || break
		sleep 0.1
	done
	if kill -0 "${pid}" 2>/dev/null; then
		pkill -f 'sleep 300.5' || :
		fail "run was still up 10 s after SIGTERM"
	fi
	local rc=0
	wait "${pid}" || rc=$?
	assert_equal "${rc}" 143
	run ls "${STATE}"
	assert_output jb-base
	run grep -cE '^curl .*-X DELETE .*/actions/runners/7' "${LOG}"
	assert_output 2
	[ ! -e "${JB_RUNNER_LOCK}" ]
	sleep 0.5
	run pgrep -f 'sleep 300.5'
	assert_failure
}

@test 'slots: stale VMs of every slot are deleted first' {
	touch "${STATE}/jb-job-testhost-s1-1" "${STATE}/jb-job-testhost-s2-1"
	run runner-host.sh run --once
	assert_success
	run grep -cxE 'tart delete jb-job-testhost-s[12]-1' "${LOG}"
	assert_output 2
}

@test 'lock: a takeover that finds a fresh lock puts it back' {
	# Another process takes the stale lock between this one reading it
	# and renaming it away: an mv that, on exactly that rename, first
	# replaces the pid file with a live holder's.
	local realmv
	realmv="$(command -v mv)"
	mkdir "${JB_RUNNER_LOCK}"
	printf '999999 1\n' >"${JB_RUNNER_LOCK}/pid"
	cat >"${STUBS}/mv" <<-EOF
		#!/bin/bash
		if [ "\$1" = "${JB_RUNNER_LOCK}" ] && [[ "\$2" == "${JB_RUNNER_LOCK}.stale."* ]]; then
			printf '%s 1\\n' "\$\$" >"${JB_RUNNER_LOCK}/pid"
		fi
		exec "${realmv}" "\$@"
	EOF
	chmod +x "${STUBS}/mv"
	run runner-host.sh run --once
	assert_failure
	assert_output --partial 'changed hands while being taken over'
	# The other process's lock is back in place, untouched, and nothing
	# ran under it.
	run cat "${JB_RUNNER_LOCK}/pid"
	refute_output '999999 1'
	run ls "${BATS_TEST_TMPDIR}"
	refute_output --partial 'lock.stale'
	run grep -E '^tart (clone|delete)' "${LOG}"
	assert_failure
}

@test 'orgs: one slot per org, each with its own PAT' {
	_org_b_token
	JB_RUNNER_ORG=org-a JB_RUNNER_ORGS='org-a, org-b' JB_RUNNER_VMS=2 \
		run runner-host.sh run --once
	assert_success
	# Slot 1 mints for org-a with org-a's PAT, slot 2 for org-b with its own.
	run grep -E '^curl-as \S+/orgs/org-a/actions/runners/registration-token Authorization: Bearer pat-SECRET-123$' "${LOG}"
	assert_success
	run grep -E '^curl-as \S+/orgs/org-b/actions/runners/registration-token Authorization: Bearer pat-OTHER-789$' "${LOG}"
	assert_success
	# Neither PAT ever reaches the other org.
	run grep -E '^curl-as \S+/orgs/org-a/.*pat-OTHER-789|^curl-as \S+/orgs/org-b/.*pat-SECRET-123' "${LOG}"
	assert_failure
	# Each runner registers to its slot's org.
	run grep -E '_ https://github\.com/org-a jb-job-testhost-s1-[0-9]+ ' "${LOG}"
	assert_success
	run grep -E '_ https://github\.com/org-b jb-job-testhost-s2-[0-9]+ ' "${LOG}"
	assert_success
	# And each cleans up in its own org.
	run grep -E '^curl .*-X DELETE .*/orgs/org-a/actions/runners/7$' "${LOG}"
	assert_success
	run grep -E '^curl .*-X DELETE .*/orgs/org-b/actions/runners/7$' "${LOG}"
	assert_success
	run grep -F 'pat-' <(grep -vE '^curl-(stdin|as) ' "${LOG}")
	assert_failure
}

@test 'orgs: another org never falls back to the default PAT' {
	JB_RUNNER_ORG=org-a JB_RUNNER_ORGS=org-a,org-b JB_RUNNER_VMS=2 \
		run runner-host.sh run --once
	assert_failure
	assert_output --partial "no token at ${BATS_TEST_TMPDIR}/token.org-b"
	run cat "${LOG}"
	assert_output ''
	# Its own PAT is held to the same rules as the default one.
	_org_b_token
	chmod 644 "${BATS_TEST_TMPDIR}/token.org-b"
	JB_RUNNER_ORG=org-a JB_RUNNER_ORGS=org-a,org-b JB_RUNNER_VMS=2 \
		run runner-host.sh run --once
	assert_failure
	assert_output --partial 'token.org-b is mode 644'
}

@test 'orgs: a name that is not an org, or a count that is not the slots, is refused' {
	local orgs
	for orgs in 'org-a,../x' 'org-a,' 'a b' '-org' 'org-a,org-b,org-c'; do
		: >"${LOG}"
		JB_RUNNER_ORGS="${orgs}" JB_RUNNER_VMS=2 run runner-host.sh run --once
		assert_failure
		run cat "${LOG}"
		assert_output ''
	done
	JB_RUNNER_ORGS=org-a,org-b JB_RUNNER_VMS=1 run runner-host.sh run --once
	assert_failure
	assert_output --partial 'names 2 orgs for 1 slot(s)'
	JB_RUNNER_ORGS='org-a,../x' JB_RUNNER_VMS=2 run runner-host.sh --dry-run install
	assert_failure
	assert_output --partial 'not a GitHub org name'
}

@test 'orgs: stale runners, uninstall and status cover every org' {
	_org_b_token
	export JB_RUNNER_ORG=org-a JB_RUNNER_ORGS=org-a,org-b JB_RUNNER_VMS=2
	touch "${STATE}/jb-job-testhost-s2-1"
	printf '%s\n' jb-job-testhost-s2-1 >"${REGISTERED}"
	run runner-host.sh run --once
	assert_success
	# The stale VM's runner could be in either org; both are asked, each
	# with its own PAT: once for the stale VM, once as its slot cleans up.
	run grep -cE '^curl-as \S+/orgs/org-a/actions/runners\?per_page=100 Authorization: Bearer pat-SECRET-123$' "${LOG}"
	assert_output 2
	run grep -cE '^curl-as \S+/orgs/org-b/actions/runners\?per_page=100 Authorization: Bearer pat-OTHER-789$' "${LOG}"
	assert_output 2
	: >"${LOG}"
	printf '%s\n' jb-job-testhost-1 >"${REGISTERED}"
	JB_RUNNER_PLIST="${BATS_TEST_TMPDIR}/daemon.plist" run runner-host.sh uninstall
	assert_success
	run grep -cE '^curl .*-X DELETE .*/orgs/org-[ab]/actions/runners/7$' "${LOG}"
	assert_output 2
	run grep -E '^curl .*-X DELETE .*/orgs/org-b/' "${LOG}"
	assert_success
	run runner-host.sh status
	assert_success
	assert_line 'runners registered to org-a:'
	assert_line 'runners registered to org-b:'
}

@test 'orgs: a token.<org> for the default org wins over the default file' {
	printf 'pat-OWN-A\n' >"${BATS_TEST_TMPDIR}/token.org-a"
	chmod 600 "${BATS_TEST_TMPDIR}/token.org-a"
	JB_RUNNER_ORG=org-a run runner-host.sh run --once
	assert_success
	run grep -E '^curl-as \S+/orgs/org-a/actions/runners/registration-token Authorization: Bearer pat-OWN-A$' "${LOG}"
	assert_success
}
