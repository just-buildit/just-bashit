#!/bin/bash
# ############################################################################
# EXECUTABLE: runner-host.sh                                                 #
# PACKAGE: just-bashit                                                       #
# ############################################################################
# Turn a Mac into a GitHub Actions runner host that runs every job in a      #
# throwaway Tart VM. One clean image, one VM per job, destroyed after. The   #
# host account is never the job's account: this Mac is also someone's      #
# macOS test environment (just-buildit.github.io#203).                       #
# ############################################################################
set -euo pipefail
IFS=$'\n\t'

_SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# Every default is an environment variable, so the LaunchDaemon, a test and a
# person at a shell all configure it the same way.
ORG="${JB_RUNNER_ORG:-just-buildit}"
TOKEN_FILE="${JB_RUNNER_TOKEN_FILE:-${HOME}/.config/jb-runner/token}"
# Pinned by digest: `latest` is rebuilt upstream, and an image that changes
# under a CI fleet is a build that changes for no reason in the diff.
BASE="${JB_RUNNER_BASE:-ghcr.io/cirruslabs/macos-tahoe-base@sha256:65c3133a633fda8753cf1f71f2d55727792d534a2125b0032466563dcc8e58fd}"
IMAGE="${JB_RUNNER_IMAGE:-jb-base}"
# actions/runner. --disableupdate means GitHub stops sending jobs to a runner
# more than 30 days behind the latest release, so re-pin and re-run `image`
# at least that often.
RUNNER_VERSION="${JB_RUNNER_VERSION:-2.338.1}"
RUNNER_SHA256="${JB_RUNNER_SHA256:-52c3fb801b931fbd454979bae5ec3443ea3da2c4a1b4c44fa546fb630d61a0a9}"
CPU="${JB_RUNNER_CPU:-4}"
MEMORY="${JB_RUNNER_MEMORY:-8192}"
BREW="${JB_RUNNER_BREW:-jq}"
LABELS="${JB_RUNNER_LABELS:-self-hosted,macOS,ARM64}"
PREFIX="${JB_RUNNER_PREFIX:-jb-job}"
API="${JB_RUNNER_API:-https://api.github.com}"
BOOT_TIMEOUT="${JB_RUNNER_BOOT_TIMEOUT:-300}"
TART="${JB_RUNNER_TART:-tart}"

DAEMON_LABEL="io.github.just-buildit.runner-host"
DAEMON_PLIST="${JB_RUNNER_PLIST:-/Library/LaunchDaemons/${DAEMON_LABEL}.plist}"
INSTALL_DIR="${JB_RUNNER_INSTALL_DIR:-${HOME}/.local/libexec/jb-runner}"
LOG_FILE="${JB_RUNNER_LOG:-${HOME}/Library/Logs/jb-runner.log}"

DRY_RUN=0
ONCE=0
CMD=""

read -r -d '' HELP <<-'EOF' || true
	Usage: runner-host.sh [OPTIONS] COMMAND

	  Host GitHub Actions jobs for an org in throwaway Tart VMs on this Mac.
	  Each job gets a fresh clone of one clean image, registers an ephemeral
	  runner inside it, runs exactly one job, and is deleted.

	  Why a VM per job: a self-hosted runner gets no container and no fresh
	  machine on its own, and `container:` jobs are Linux-only. A runner on
	  the bare host would run every job as the account someone also uses.

	Commands:
	  image      Build the clean image: clone the pinned base, install the
	             pinned actions/runner and JB_RUNNER_BREW packages into it,
	             and save it as JB_RUNNER_IMAGE. Re-run to upgrade.
	  run        The job loop, forever: mint a registration token, clone the
	             image, boot it, run one job, delete the VM. What the
	             LaunchDaemon runs. --once stops after one VM.
	  install    Copy this script to a stable path and install a LaunchDaemon
	             that runs `run` from boot, as this user. Uses sudo.
	  uninstall  Remove the LaunchDaemon and any job VMs. Uses sudo.
	  status     The daemon, the VMs, and the org's registered runners.

	Options:
	  -h / --help     Show this message and exit.
	  -n / --dry-run  Print what would happen; change nothing.
	  --once          With `run`: one VM, then exit.

	Environment (defaults in brackets):
	  JB_RUNNER_ORG         org the runners register to [just-buildit]
	  JB_RUNNER_TOKEN_FILE  fine-grained PAT, org "Self-hosted runners:
	                        Read and write" [~/.config/jb-runner/token]
	  JB_RUNNER_BASE        Tart base image, pinned by digest
	  JB_RUNNER_IMAGE       the clean image's local name [jb-base]
	  JB_RUNNER_VERSION     actions/runner version, with JB_RUNNER_SHA256
	  JB_RUNNER_CPU / JB_RUNNER_MEMORY  per VM [4 / 8192 MB]
	  JB_RUNNER_BREW        packages added to the image [jq]
	  JB_RUNNER_LABELS      runner labels [self-hosted,macOS,ARM64]

	  The PAT never enters a VM. Only a registration token does, and it is
	  passed on stdin, never on a command line the host's ps can see.

	Exit status:
	  0  done
	  1  an error
EOF

_say() { printf '%s\n' "$*"; }
_log() { printf '%s runner-host: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*"; }
_die() {
	printf 'runner-host: %s\n' "$*" >&2
	exit 1
}

# Echo the command in dry-run, run it otherwise.
_run() {
	if [[ ${DRY_RUN} -eq 1 ]]; then
		local IFS=' '
		printf '  would: %s\n' "$*"
	else
		"$@"
	fi
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	-h | --help)
		_say "${HELP}"
		exit 0
		;;
	-n | --dry-run) DRY_RUN=1 ;;
	--once) ONCE=1 ;;
	image | run | install | uninstall | status)
		[[ -z ${CMD} ]] || _die "one command at a time (got ${CMD} and $1)"
		CMD="$1"
		;;
	*) _die "unknown argument: $1 (try --help)" ;;
	esac
	shift
done
[[ -n ${CMD} ]] || _die "no command given (try --help)"

# ── Preconditions ───────────────────────────────────────────────────────────

_need_macos() {
	[[ "${JB_RUNNER_OS:-$(uname -s)}" == Darwin ]] ||
		_die "macOS only: Tart runs on Apple's Virtualization.framework"
}

_need_tart() {
	command -v "${TART}" >/dev/null 2>&1 ||
		_die "tart not found (https://github.com/cirruslabs/tart/releases)"
}

# ── GitHub ──────────────────────────────────────────────────────────────────
# The PAT goes to curl as a header on stdin (-H @-), never in argv: a
# LaunchDaemon's command lines are visible to every user's ps.

_api() { # METHOD PATH
	[[ -r ${TOKEN_FILE} ]] || _die "no token at ${TOKEN_FILE}"
	local pat
	pat="$(<"${TOKEN_FILE}")"
	printf 'Authorization: Bearer %s\n' "${pat}" |
		curl -fsS -X "$1" -H @- \
			-H 'Accept: application/vnd.github+json' \
			-H 'X-GitHub-Api-Version: 2022-11-28' \
			"${API}$2"
}

# Remove a runner registration by name. An ephemeral runner removes itself
# after its job; one whose VM was killed first stays listed until GitHub
# expires it, and shows as an idle runner nobody can reach.
_deregister() { # NAME
	local id
	id="$(_api GET "/orgs/${ORG}/actions/runners?per_page=100" |
		jq -r --arg n "$1" '.runners[] | select(.name == $n) | .id')" || return 0
	[[ -z ${id} ]] || _api DELETE "/orgs/${ORG}/actions/runners/${id}" >/dev/null || true
}

_registration_token() {
	local t
	t="$(_api POST "/orgs/${ORG}/actions/runners/registration-token" | jq -r '.token // empty')" || return 1
	[[ -n ${t} ]] || return 1
	printf '%s\n' "${t}"
}

# ── VMs ─────────────────────────────────────────────────────────────────────

_vm_exists() { "${TART}" list --format json | jq -e --arg n "$1" 'any(.[]; .Name == $n)' >/dev/null; }

_vm_delete() {
	"${TART}" stop "$1" >/dev/null 2>&1 || true
	"${TART}" delete "$1" >/dev/null 2>&1 || true
}

# Boot headless and wait for the guest agent, which `tart exec` needs. The
# Cirrus Labs images ship the agent; a vanilla image does not.
_vm_boot() { # NAME
	"${TART}" run --no-graphics "$1" >/dev/null 2>&1 &
	local waited=0
	until "${TART}" exec "$1" /usr/bin/true >/dev/null 2>&1; do
		((waited < BOOT_TIMEOUT)) || return 1
		sleep 5
		waited=$((waited + 5))
	done
}

# ── Commands ────────────────────────────────────────────────────────────────

cmd_image() {
	_need_macos
	_need_tart
	local build="${IMAGE}-build"
	local url="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-osx-arm64-${RUNNER_VERSION}.tar.gz"
	_say "Building ${IMAGE} from ${BASE}"
	_say "  actions/runner ${RUNNER_VERSION}; brew: ${BREW:-none}"
	if [[ ${DRY_RUN} -eq 1 ]]; then
		_run "${TART}" clone "${BASE}" "${build}"
		_run "${TART}" set "${build}" --cpu "${CPU}" --memory "${MEMORY}"
		_run "${TART}" exec "${build}" '<install runner and packages>'
		_run "${TART}" rename "${build}" "${IMAGE}"
		return 0
	fi
	_vm_delete "${build}"
	"${TART}" clone "${BASE}" "${build}"
	"${TART}" set "${build}" --cpu "${CPU}" --memory "${MEMORY}"
	_vm_boot "${build}" || {
		_vm_delete "${build}"
		_die "${build} did not come up within ${BOOT_TIMEOUT}s"
	}
	# Positional arguments, not interpolation into the script text, so no
	# value can change what the guest runs.
	# shellcheck disable=SC2016  # expanded in the guest, not here
	"${TART}" exec "${build}" /bin/bash -lc '
		set -euo pipefail
		rm -rf ~/actions-runner && mkdir ~/actions-runner && cd ~/actions-runner
		curl -fsSL -o runner.tgz "$1"
		printf "%s  runner.tgz\n" "$2" | shasum -a 256 -c -
		tar xzf runner.tgz && rm runner.tgz
		if [ -n "$3" ]; then
			IFS=" " read -r -a pkgs <<<"$3"
			brew install --quiet "${pkgs[@]}"
		fi
	' _ "${url}" "${RUNNER_SHA256}" "${BREW}" || {
		_vm_delete "${build}"
		_die "provisioning ${build} failed"
	}
	"${TART}" stop "${build}"
	_vm_delete "${IMAGE}"
	"${TART}" rename "${build}" "${IMAGE}"
	_say "Done: ${IMAGE} is ready."
}

# One job: a fresh VM, an ephemeral runner, deleted whatever happens.
_one_job() {
	local vm token
	vm="${PREFIX}-$(date +%s)"
	token="$(_registration_token)" || {
		_log "could not mint a registration token"
		return 1
	}
	_log "clone ${IMAGE} -> ${vm}"
	"${TART}" clone "${IMAGE}" "${vm}" || return 1
	CURRENT_VM="${vm}"
	if ! _vm_boot "${vm}"; then
		_log "${vm} did not come up within ${BOOT_TIMEOUT}s"
		_cleanup
		return 1
	fi
	_log "${vm} up; registering and waiting for a job"
	local rc=0
	# In the background and waited for: bash runs a trap only between
	# foreground commands, so a SIGTERM from launchd during a job that runs
	# for an hour would otherwise wait that hour. `wait` is interrupted.
	# shellcheck disable=SC2016  # expanded in the guest, not here
	printf '%s\n' "${token}" | "${TART}" exec -i "${vm}" /bin/bash -lc '
		set -euo pipefail
		read -r t
		cd ~/actions-runner
		./config.sh --unattended --ephemeral --disableupdate --replace \
			--url "$1" --name "$2" --labels "$3" --token "$t" >/dev/null
		exec ./run.sh
	' _ "https://github.com/${ORG}" "${vm}" "${LABELS}" &
	wait "$!" || rc=$?
	_log "${vm} finished (exit ${rc}); deleting"
	_cleanup
	return "${rc}"
}

# The VM the loop is on, so a signal can take it down with the loop.
CURRENT_VM=""
_cleanup() {
	[[ -n ${CURRENT_VM} ]] || return 0
	local vm="${CURRENT_VM}"
	CURRENT_VM=""
	_vm_delete "${vm}"
	_deregister "${vm}"
}

_on_signal() { # EXIT_CODE
	_log "signal; deleting ${CURRENT_VM:-no VM}"
	_cleanup
	exit "$1"
}

cmd_run() {
	_need_macos
	_need_tart
	if [[ ${DRY_RUN} -eq 1 ]]; then
		_say "would loop: mint token for ${ORG}; clone ${IMAGE}; boot; run one job; delete"
		return 0
	fi
	_vm_exists "${IMAGE}" || _die "no image ${IMAGE}; run: runner-host.sh image"
	trap '_on_signal 143' TERM
	trap '_on_signal 130' INT
	trap '_on_signal 129' HUP
	# A crash or reboot mid-job leaves a VM behind. Nothing else names VMs
	# with this prefix, so any found at start are ours and stale.
	local stale
	for stale in $("${TART}" list --format json | jq -r --arg p "${PREFIX}-" '.[] | select(.Name | startswith($p)) | .Name'); do
		_log "deleting stale ${stale}"
		_vm_delete "${stale}"
		_deregister "${stale}"
	done
	if [[ ${ONCE} -eq 1 ]]; then
		_one_job
		return
	fi
	local backoff=30
	while :; do
		if _one_job; then
			backoff=30
		else
			_log "retrying in ${backoff}s"
			sleep "${backoff}"
			backoff=$((backoff < 600 ? backoff * 2 : 600))
		fi
	done
}

_plist() {
	cat <<-EOF
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		<dict>
			<key>Label</key><string>${DAEMON_LABEL}</string>
			<key>UserName</key><string>$(id -un)</string>
			<key>ProgramArguments</key>
			<array>
				<string>/bin/bash</string>
				<string>${INSTALL_DIR}/runner-host.sh</string>
				<string>run</string>
			</array>
			<key>EnvironmentVariables</key>
			<dict>
				<key>HOME</key><string>${HOME}</string>
				<key>PATH</key><string>${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
			</dict>
			<key>RunAtLoad</key><true/>
			<key>KeepAlive</key><true/>
			<key>ThrottleInterval</key><integer>30</integer>
			<key>StandardOutPath</key><string>${LOG_FILE}</string>
			<key>StandardErrorPath</key><string>${LOG_FILE}</string>
		</dict>
		</plist>
	EOF
}

cmd_install() {
	_need_macos
	_need_tart
	[[ -r ${TOKEN_FILE} ]] || _die "no token at ${TOKEN_FILE}"
	local tmp
	tmp="$(mktemp)"
	_plist >"${tmp}"
	_say "Installing ${DAEMON_LABEL} (runs as $(id -un))"
	_run mkdir -p "${INSTALL_DIR}" "$(dirname "${LOG_FILE}")"
	_run install -m 755 "${_SCRIPT_PATH}" "${INSTALL_DIR}/runner-host.sh"
	_run sudo launchctl bootout "system/${DAEMON_LABEL}" 2>/dev/null || true
	_run sudo install -m 644 -o root -g wheel "${tmp}" "${DAEMON_PLIST}"
	_run sudo launchctl bootstrap system "${DAEMON_PLIST}"
	rm -f "${tmp}"
	_say "Done. Log: ${LOG_FILE}"
}

cmd_uninstall() {
	_need_macos
	_run sudo launchctl bootout "system/${DAEMON_LABEL}" 2>/dev/null || true
	_run sudo rm -f "${DAEMON_PLIST}"
	if command -v "${TART}" >/dev/null 2>&1; then
		local vm
		for vm in $("${TART}" list --format json | jq -r --arg p "${PREFIX}-" '.[] | select(.Name | startswith($p)) | .Name'); do
			_run _vm_delete "${vm}"
		done
	fi
	_say "Removed ${DAEMON_LABEL}. ${IMAGE} is kept; delete it with: ${TART} delete ${IMAGE}"
}

cmd_status() {
	_say "daemon:"
	if launchctl print "system/${DAEMON_LABEL}" >/dev/null 2>&1; then
		launchctl print "system/${DAEMON_LABEL}" | grep -E '^[[:space:]]*(state|pid|last exit code) =' | sed 's/^[[:space:]]*/  /'
	else
		_say "  not loaded"
	fi
	_say "vms:"
	if command -v "${TART}" >/dev/null 2>&1; then
		"${TART}" list --format json | jq -r --arg i "${IMAGE}" --arg p "${PREFIX}-" \
			'.[] | select(.Name == $i or (.Name | startswith($p))) | "  \(.Name)  \(.State)"'
	else
		_say "  tart not installed"
	fi
	_say "runners registered to ${ORG}:"
	_api GET "/orgs/${ORG}/actions/runners" |
		jq -r '.runners[] | "  \(.name)  \(.status)\(if .busy then "  busy" else "" end)"'
}

"cmd_${CMD}"
