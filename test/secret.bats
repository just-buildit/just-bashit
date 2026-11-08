# shellcheck disable=SC2154  # BATS_* and the helpers' vars are bats'/setup's
load 'test_helper/common-setup'
_common_setup
bats_require_minimum_version 1.5.0

# `just-runit secret` (#229) against real gpg and age, with throwaway keys:
# a GNUPGHOME holding two no-passphrase keys, two age identities and an
# ed25519 ssh key, made once per file. Every test gets its own HOME, so the
# store and the recipients file are its own.
#
# A missing gpg, age or script(1) skips with the reason on a workstation and
# FAILS under CI: bootstrap.toml installs all three on every leg, and a leg
# that lost one would otherwise pass while testing nothing.

VALUE='s3cr3t-value-229'

_need() {
	local tool
	for tool in "$@"; do
		command -v "${tool}" >/dev/null 2>&1 && continue
		if [[ -n ${CI:-} ]]; then
			fail "${tool} is not installed: bootstrap.toml must install it on every CI leg"
		fi
		skip "${tool} is not installed (jbx setup-system -s deps installs it)"
	done
}

setup_file() {
	# A short path: gpg-agent puts its socket in GNUPGHOME when there is no
	# /run/user (macOS, root containers), and a socket path is capped near
	# 104 bytes; BATS_FILE_TMPDIR on macOS is longer than that.
	JB_TEST_GNUPGHOME="$(mktemp -d "${TMPDIR:-/tmp}/jbg.XXXXXX")"
	chmod 700 "${JB_TEST_GNUPGHOME}"
	export JB_TEST_GNUPGHOME
	local keys="${BATS_FILE_TMPDIR}/keys" n
	mkdir -p "${keys}"
	if command -v gpg >/dev/null 2>&1; then
		for n in 1 2; do
			# 3>&-: the agent this starts outlives the command, and must
			# not hold bats' output descriptor open.
			GNUPGHOME="${JB_TEST_GNUPGHOME}" gpg --batch --passphrase '' \
				--quick-gen-key "jb test ${n} <jb${n}@example.invalid>" \
				default default never >/dev/null 2>&1 3>&-
		done
		GNUPGHOME="${JB_TEST_GNUPGHOME}" gpg --batch --with-colons \
			--list-keys 2>/dev/null |
			awk -F: '$1 == "pub" { p = 1 } $1 == "fpr" && p { print $10; p = 0 }' \
				>"${keys}/gpg-fprs" 3>&-
	fi
	if command -v age-keygen >/dev/null 2>&1; then
		for n in 1 2; do
			age-keygen -o "${keys}/age${n}" 2>/dev/null
			age-keygen -y "${keys}/age${n}" >"${keys}/age${n}.pub"
		done
	fi
	if command -v ssh-keygen >/dev/null 2>&1; then
		ssh-keygen -q -t ed25519 -N '' -C 'jb test' -f "${keys}/ssh" </dev/null
	fi
}

teardown_file() {
	if command -v gpgconf >/dev/null 2>&1; then
		GNUPGHOME="${JB_TEST_GNUPGHOME}" gpgconf --kill all 3>&- || true
	fi
	rm -rf "${JB_TEST_GNUPGHOME:?}"
}

setup() {
	HOME="${BATS_TEST_TMPDIR}/home"
	mkdir -p "${HOME}"
	export HOME GNUPGHOME="${JB_TEST_GNUPGHOME}"
	unset XDG_DATA_HOME XDG_CONFIG_HOME
	KEYS="${BATS_FILE_TMPDIR}/keys"
	STORE="${HOME}/.local/share/jb/secrets"
	CONF="${HOME}/.config/jb/secrets/recipients"
	mkdir -p "${CONF%/*}"
	cd "${BATS_TEST_TMPDIR}" || return 1
}

# _fpr N -- the fingerprint of throwaway gpg key N's primary key.
_fpr() { sed -n "${1}p" "${KEYS}/gpg-fprs"; }

# _conf LINE... -- the recipients file, exactly these lines.
_conf() { printf '%s\n' "$@" >"${CONF}"; }

# _conf_both -- gpg key 1 and age identity 1, for a test of both backends.
_conf_both() {
	_conf "gpg $(_fpr 1)" "age $(<"${KEYS}/age1.pub")" "identity ${KEYS}/age1"
}

# _mode PATH -- the permission bits, or "n/a" on NTFS, where they mean
# nothing (the windows runner reports 644 after chmod 600).
_mode() {
	case "${OSTYPE:-}" in
	msys* | cygwin*) echo n/a ;;
	*) stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1" ;;
	esac
}

# _spy -- put a gpg and an age first on PATH that record, per call, their
# argv (one line in ${SPY}/argv) and their environment (${SPY}/env.N), then
# exec the real tool.
_spy() {
	SPY="${BATS_TEST_TMPDIR}/spy"
	mkdir -p "${SPY}/bin"
	local tool real
	for tool in gpg age; do
		real="$(command -v "${tool}")"
		{
			echo '#!/usr/bin/env bash'
			printf 'spy=%q real=%q tool=%q\n' "${SPY}" "${real}" "${tool}"
			cat <<-'EOF'
				printf '%s %s\n' "${tool}" "$*" >>"${spy}/argv"
				n=$(ls "${spy}" | grep -c '^env\.' || true)
				env >"${spy}/env.$((n + 1))"
				exec "${real}" "$@"
			EOF
		} >"${SPY}/bin/${tool}"
		chmod +x "${SPY}/bin/${tool}"
	done
	PATH="${SPY}/bin:${PATH}"
}

# _tty CMD... -- run CMD with stdin and stdout on a real pseudo-terminal,
# by script(1): util-linux's on Linux and MSYS2, the BSD one on macOS.
_tty() {
	local cmd
	printf -v cmd '%q ' "$@"
	if script --version 2>/dev/null | grep -q util-linux; then
		SHELL="$(command -v bash)" script -qec "${cmd}" /dev/null
	else
		script -q /dev/null "$@"
	fi
}

# _tty_type INPUT CMD... -- as _tty, and type INPUT once CMD has printed
# its prompt (a line ending ": "), the way a person would: typed before it,
# the terminal echoes it whatever the prompt then does. Prints the
# terminal's transcript, which script(1) writes to stdout as it goes -- so
# the writer can watch it for the prompt. No fifo and no `script -F`: the
# BSD script on the macOS runner never wrote the prompt through either.
# shellcheck disable=SC2094  # reading the transcript as script writes it is the point
_tty_type() {
	local input="$1" log="${BATS_TEST_TMPDIR}/tty.log" cmd rc=0
	shift
	printf -v cmd '%q ' "$@"
	: >"${log}"
	{
		for ((i = 0; i < 200; i++)); do
			grep -q ': ' "${log}" && break
			sleep 0.1
		done
		printf '%s\n' "${input}"
	} | if script --version 2>/dev/null | grep -q util-linux; then
		SHELL="$(command -v bash)" script -qec "${cmd}" /dev/null
	else
		script -q /dev/null "$@"
	fi >"${log}" 2>&1 || rc=$?
	cat "${log}"
	return "${rc}"
}

# ---- help -------------------------------------------------------------------

@test 'just-runit help lists secret, and secret -h documents every command' {
	run just-runit help
	assert_success
	assert_output --partial 'secret   Store, get and use secrets'
	run just-runit secret -h
	assert_success
	for c in 'set NAME' 'get NAME' 'run NAME' 'list' 'rm NAME' 'migrate NAME' 'rekey'; do
		assert_output --partial "  ${c}"
	done
}

@test 'secret with an unknown command fails naming it' {
	run just-runit secret frobnicate
	assert_failure
	assert_output --partial "unknown command 'frobnicate'"
}

# ---- each command, on each backend ------------------------------------------

# _roundtrip BACKEND -- set from stdin, get, the file and its modes.
_roundtrip() {
	run just-runit secret set TOK --backend "$1" <<<"${VALUE}"
	assert_success
	assert_output "stored TOK ($1)"
	[[ -f "${STORE}/TOK.$1" ]] || fail "no ${STORE}/TOK.$1"
	run grep -c "${VALUE}" "${STORE}/TOK.$1"
	assert_output 0
	case "$(_mode "${STORE}")" in 700 | n/a) ;; *) fail "store mode $(_mode "${STORE}")" ;; esac
	case "$(_mode "${STORE}/TOK.$1")" in 600 | n/a) ;; *) fail "file mode $(_mode "${STORE}/TOK.$1")" ;; esac
	run just-runit secret get TOK
	assert_success
	assert_output "${VALUE}"
	# Exactly the bytes given, the newline <<< added included.
	cmp <(just-runit secret get TOK) <(printf '%s\n' "${VALUE}")
}

@test 'gpg: set from stdin, then get gives back the same bytes' {
	_need gpg
	_conf "gpg $(_fpr 1)"
	_roundtrip gpg
}

@test 'age: set from stdin, then get gives back the same bytes' {
	_need age age-keygen
	_conf_both
	_roundtrip age
}

@test 'age: an ssh public key file is a recipient, its private key the identity' {
	_need age ssh-keygen
	_conf "age ${KEYS}/ssh.pub" "identity ${KEYS}/ssh"
	_roundtrip age
}

@test 'age: an ssh public key line is a recipient too' {
	_need age ssh-keygen
	_conf "age $(<"${KEYS}/ssh.pub")" "identity ${KEYS}/ssh"
	_roundtrip age
}

@test 'age: a leading ~/ in the config is HOME' {
	_need age
	cp "${KEYS}/age1" "${KEYS}/age1.pub" "${HOME}/"
	# shellcheck disable=SC2088  # the literal ~ is what the config holds
	_conf 'age ~/age1.pub' 'identity ~/age1'
	_roundtrip age
}

@test 'gpg: with no gpg recipients it encrypts to your own key' {
	_need gpg
	: >"${CONF}"
	_roundtrip gpg
}

@test 'set with no --backend: gpg when a gpg secret key exists' {
	_need gpg
	run just-runit secret set TOK <<<"${VALUE}"
	assert_success
	assert_output 'stored TOK (gpg)'
}

@test 'set with no --backend: age when there is no gpg secret key' {
	_need age
	GNUPGHOME="${BATS_TEST_TMPDIR}/empty-gnupg"
	# mkdir then chmod: MSYS2 refuses mkdir -m 700 outright.
	mkdir "${GNUPGHOME}"
	chmod 700 "${GNUPGHOME}"
	_conf "age $(<"${KEYS}/age1.pub")" "identity ${KEYS}/age1"
	run just-runit secret set TOK <<<"${VALUE}"
	assert_success
	assert_output 'stored TOK (age)'
}

@test 'set with no --backend: default_backend wins, and a stored secret keeps its own' {
	_need gpg age
	_conf_both
	echo 'default_backend age' >>"${CONF}"
	run just-runit secret set TOK <<<"${VALUE}"
	assert_output 'stored TOK (age)'
	run just-runit secret set OLD --backend gpg <<<"${VALUE}"
	run just-runit secret set OLD <<<"new"
	assert_output 'stored OLD (gpg)'
}

@test 'list: names and backends, sorted, and never a value' {
	_need gpg age
	_conf_both
	just-runit secret set B --backend gpg <<<"${VALUE}"
	just-runit secret set A --backend age <<<"${VALUE}"
	run just-runit secret list
	assert_success
	assert_output "$(printf 'A age\nB gpg')"
	refute_output --partial "${VALUE}"
}

@test 'list with no store prints nothing' {
	run just-runit secret list
	assert_success
	assert_output ''
}

@test 'rm deletes either backend, and refuses a name not stored' {
	_need gpg age
	_conf_both
	just-runit secret set A --backend age <<<"${VALUE}"
	just-runit secret set B --backend gpg <<<"${VALUE}"
	run just-runit secret rm A B
	assert_success
	[[ ! -e ${STORE}/A.age && ! -e ${STORE}/B.gpg ]] || fail 'not removed'
	run just-runit secret rm A
	assert_failure
	assert_output --partial "no secret 'A'"
}

@test 'run: CMD gets each secret, as NAME or as VAR, from both backends' {
	_need gpg age
	_conf_both
	just-runit secret set A --backend gpg <<<"${VALUE}-a"
	just-runit secret set B --backend age <<<"${VALUE}-b"
	# shellcheck disable=SC2016  # expanded by CMD
	run just-runit secret run A B=BEE -- bash -c 'echo "A=[${A}] BEE=[${BEE}] B=[${B:-unset}]"'
	assert_success
	assert_output "A=[${VALUE}-a] BEE=[${VALUE}-b] B=[unset]"
}

@test 'run: refuses a bad VAR, a missing --, and a missing secret' {
	run just-runit secret run A=1BAD -- true
	assert_failure
	assert_output --partial "'1BAD' is not an environment variable name"
	run just-runit secret run A true
	assert_failure
	assert_output --partial 'usage: just-runit secret run'
	run just-runit secret run A -- true
	assert_failure
	assert_output --partial "no secret 'A'"
}

@test 'migrate: gpg to age and back, the value kept and the old file gone' {
	_need gpg age
	_conf_both
	just-runit secret set TOK --backend gpg <<<"${VALUE}"
	run just-runit secret migrate TOK --to age
	assert_success
	assert_output 'migrated TOK: gpg -> age'
	[[ -f ${STORE}/TOK.age && ! -e ${STORE}/TOK.gpg ]] || fail 'not moved to age'
	assert_equal "$(just-runit secret get TOK)" "${VALUE}"
	run just-runit secret migrate TOK --to gpg
	assert_success
	[[ -f ${STORE}/TOK.gpg && ! -e ${STORE}/TOK.age ]] || fail 'not moved to gpg'
	assert_equal "$(just-runit secret get TOK)" "${VALUE}"
	run just-runit secret migrate TOK --to gpg
	assert_success
	assert_output 'TOK is already gpg'
}

@test 'age: rekey re-encrypts to the recipients the config names now' {
	_need age
	_conf "age $(<"${KEYS}/age1.pub")" "identity ${KEYS}/age1"
	just-runit secret set TOK --backend age <<<"${VALUE}"
	cp "${STORE}/TOK.age" "${BATS_TEST_TMPDIR}/before"
	# To a key none of your identities opens: refused, since the new copy
	# cannot be checked, and it would lock you out.
	_conf "age $(<"${KEYS}/age2.pub")" "identity ${KEYS}/age1"
	run just-runit secret rekey
	assert_failure
	assert_output --partial "'TOK' is unchanged"
	cmp "${STORE}/TOK.age" "${BATS_TEST_TMPDIR}/before"
	_conf "age $(<"${KEYS}/age2.pub")" "identity ${KEYS}/age1" "identity ${KEYS}/age2"
	run just-runit secret rekey
	assert_success
	assert_output 'rekeyed TOK (age)'
	# Only the new identity opens it now.
	assert_equal "$(age --decrypt -i "${KEYS}/age2" "${STORE}/TOK.age")" "${VALUE}"
	run age --decrypt -i "${KEYS}/age1" "${STORE}/TOK.age"
	assert_failure
}

@test 'gpg: rekey re-encrypts to the recipients the config names now' {
	_need gpg
	_conf "gpg $(_fpr 1)"
	just-runit secret set TOK --backend gpg <<<"${VALUE}"
	_conf "gpg $(_fpr 2)"
	run just-runit secret rekey TOK
	assert_success
	assert_output 'rekeyed TOK (gpg)'
	# The key ids the message is encrypted to: key 2's subkey, not key 1's.
	local to sub1 sub2
	to="$(gpg --batch --list-packets "${STORE}/TOK.gpg" 2>/dev/null | sed -n 's/.*keyid \([0-9A-F]*\).*/\1/p')"
	sub1="$(gpg --batch --with-colons --list-keys "$(_fpr 1)" | awk -F: '$1 == "sub" { print $5 }')"
	sub2="$(gpg --batch --with-colons --list-keys "$(_fpr 2)" | awk -F: '$1 == "sub" { print $5 }')"
	assert_equal "${to}" "${sub2}"
	[[ ${to} != "${sub1}" ]] || fail 'still encrypted to key 1'
	assert_equal "$(just-runit secret get TOK)" "${VALUE}"
}

# ---- the guarantees ---------------------------------------------------------

# Sabotage-proven (PR for #229): passing the value to gpg or age as an
# argument turns this red.
@test 'no secret value is ever in the argv of gpg or age' {
	_need gpg age
	_conf_both
	_spy
	just-runit secret set A --backend gpg <<<"${VALUE}"
	just-runit secret set B --backend age <<<"${VALUE}"
	just-runit secret get A >/dev/null
	just-runit secret get B >/dev/null
	just-runit secret run A B -- true
	just-runit secret migrate A --to age
	just-runit secret rekey
	[[ -s ${SPY}/argv ]] || fail 'the spy saw no call'
	grep -q '^gpg ' "${SPY}/argv" || fail 'the spy saw no gpg call'
	grep -q '^age ' "${SPY}/argv" || fail 'the spy saw no age call'
	run grep -F "${VALUE}" "${SPY}/argv"
	assert_failure
}

# Sabotage-proven (PR for #229): exporting each secret as soon as it is
# decrypted, so the next gpg or age inherits it, turns this red.
@test 'run: only CMD gets the secrets, never a gpg or age run' {
	_need gpg age
	_conf_both
	just-runit secret set A --backend gpg <<<"${VALUE}-a"
	just-runit secret set B --backend age <<<"${VALUE}-b"
	just-runit secret set C --backend gpg <<<"${VALUE}-c"
	_spy
	run just-runit secret run A B C -- env
	assert_success
	assert_line "A=${VALUE}-a"
	assert_line "B=${VALUE}-b"
	assert_line "C=${VALUE}-c"
	ls "${SPY}"/env.* >/dev/null || fail 'the spy saw no call'
	run grep -l -F "${VALUE}" "${SPY}"/env.*
	assert_failure
	# And not the shell that ran it.
	[[ -z ${A:-} ]] || fail 'A leaked into the caller'
}

# Sabotage-proven (PR for #229): deciding the backend by the configured
# default instead of the file's extension turns this red.
@test 'get uses the backend the extension names, not the configured default' {
	_need gpg age
	_conf_both
	just-runit secret set G --backend gpg <<<"${VALUE}"
	just-runit secret set A --backend age <<<"${VALUE}"
	echo 'default_backend gpg' >>"${CONF}"
	_spy
	run just-runit secret get A
	assert_success
	assert_output "${VALUE}"
	run grep -c '^age --decrypt' "${SPY}/argv"
	assert_output 1
	run grep -c 'decrypt' "${SPY}/argv"
	assert_output 1
	: >"${SPY}/argv"
	sed -i.bak 's/default_backend gpg/default_backend age/' "${CONF}"
	run just-runit secret get G
	assert_output "${VALUE}"
	run grep -c '^gpg .*--decrypt' "${SPY}/argv"
	assert_output 1
	run grep -c '^age ' "${SPY}/argv"
	assert_output 0
}

@test 'a NAME stored under both extensions is refused, not guessed' {
	_need gpg age
	_conf_both
	just-runit secret set A --backend gpg <<<"${VALUE}"
	cp "${STORE}/A.gpg" "${STORE}/A.age"
	run just-runit secret get A
	assert_failure
	assert_output --partial "'A' is stored twice"
}

# Sabotage-proven (PR for #229): dropping the terminal check turns this red.
# A real pseudo-terminal, by script(1) -- no environment hook.
@test 'get refuses to print to a terminal, and --show allows it' {
	_need gpg script
	_conf "gpg $(_fpr 1)"
	just-runit secret set A --backend gpg <<<"${VALUE}"
	run _tty just-runit secret get A
	assert_failure
	assert_output --partial "refusing to print secret 'A' to a terminal"
	refute_output --partial "${VALUE}"
	run _tty just-runit secret get A --show
	assert_success
	assert_output --partial "${VALUE}"
}

# Sabotage-proven (PR for #229): reading without -s, which leaves the
# terminal echoing, turns this red.
@test 'set on a terminal prompts with echo off' {
	_need age script
	_conf_both
	run _tty_type "${VALUE}" just-runit secret set A --backend age
	assert_success
	assert_output --partial 'A: '
	assert_output --partial 'stored A (age)'
	refute_output --partial "${VALUE}"
	assert_equal "$(just-runit secret get A)" "${VALUE}"
}

# Sabotage-proven (PR for #229): dropping the empty-stdin check turns this
# red -- an empty value stored over the old one.
@test 'set refuses an empty stdin, and keeps the secret already stored' {
	_need age
	_conf "age $(<"${KEYS}/age1.pub")" "identity ${KEYS}/age1"
	run just-runit secret set NEW --backend age </dev/null
	assert_failure
	assert_output "just-runit secret: error: empty value for 'NEW'; nothing stored"
	[[ ! -e ${STORE}/NEW.age ]] || fail 'an empty secret was stored'
	just-runit secret set OLD --backend age <<<"${VALUE}"
	cp "${STORE}/OLD.age" "${BATS_TEST_TMPDIR}/before"
	run just-runit secret set OLD </dev/null
	assert_failure
	assert_output "just-runit secret: error: empty value for 'OLD'; nothing stored"
	cmp "${STORE}/OLD.age" "${BATS_TEST_TMPDIR}/before"
	assert_equal "$(just-runit secret get OLD)" "${VALUE}"
}

@test 'set keeps a value whose first byte is a newline or a NUL' {
	_need age
	_conf "age $(<"${KEYS}/age1.pub")" "identity ${KEYS}/age1"
	printf '\nx' | just-runit secret set A --backend age
	cmp <(just-runit secret get A) <(printf '\nx')
	printf '\0y' | just-runit secret set B --backend age
	cmp <(just-runit secret get B) <(printf '\0y')
}

@test 'set never takes the value as an argument' {
	run just-runit secret set A "${VALUE}"
	assert_failure
	assert_output --partial 'the value comes from stdin, never an argument'
	[[ ! -e ${STORE} ]] || fail 'something was stored'
}

# ---- one clear error line ---------------------------------------------------

@test 'a missing tool is one error line naming what to install' {
	# The running bash by path: the farm's own bash is macOS's 3.2.
	local runit="${PROJECT_ROOT}/src/just_bashit/just-runit"
	PATH="$(_bin_without age gpg)"
	run "${BASH}" "${runit}" secret set A --backend age <<<"${VALUE}"
	assert_failure
	assert_output 'just-runit secret: error: age is not installed: install age (jbx setup-system -s deps)'
	run "${BASH}" "${runit}" secret set A --backend gpg <<<"${VALUE}"
	assert_failure
	assert_output 'just-runit secret: error: gpg is not installed: install gnupg (jbx setup-system -s deps)'
}

@test 'no age recipients, or no identity, is one error line naming the config' {
	_need age
	: >"${CONF}"
	run just-runit secret set A --backend age <<<"${VALUE}"
	assert_failure
	assert_output "just-runit secret: error: no age recipients: add 'age RECIPIENT' (age-keygen's public key, or an ssh public key) to ${CONF}"
	[[ ! -e ${STORE}/A.age ]] || fail 'stored anyway'
	_conf "age $(<"${KEYS}/age1.pub")"
	just-runit secret set A --backend age <<<"${VALUE}"
	run just-runit secret get A
	assert_failure
	assert_output --partial 'error: no age identity'
}

@test 'no gpg key and no gpg recipients is one error line' {
	_need gpg
	GNUPGHOME="${BATS_TEST_TMPDIR}/empty-gnupg"
	# mkdir then chmod: MSYS2 refuses mkdir -m 700 outright.
	mkdir "${GNUPGHOME}"
	chmod 700 "${GNUPGHOME}"
	run just-runit secret set A --backend gpg <<<"${VALUE}"
	assert_failure
	assert_output --partial 'error: no gpg recipients'
	assert_equal "${#lines[@]}" 1
}

@test 'a tool failure is one error line, with no secret in it' {
	_need age
	_conf "age $(<"${KEYS}/age1.pub")" "identity ${KEYS}/age2"
	just-runit secret set A --backend age <<<"${VALUE}"
	run just-runit secret get A
	assert_failure
	assert_output --regexp "^just-runit secret: error: age could not decrypt 'A.age': .+"
	assert_equal "${#lines[@]}" 1
	refute_output --partial "${VALUE}"
}

@test 'an unknown key in the config is refused, not skipped' {
	_need age
	_conf "age $(<"${KEYS}/age1.pub")" "agee $(<"${KEYS}/age2.pub")"
	run just-runit secret set A --backend age <<<"${VALUE}"
	assert_failure
	assert_output "just-runit secret: error: ${CONF}:2: unknown key 'agee' (gpg, age, identity, default_backend)"
	[[ ! -e ${STORE}/A.age ]] || fail 'stored to one recipient fewer'
}

@test 'a bad name, or an unknown backend, is refused' {
	run just-runit secret set ../x <<<"${VALUE}"
	assert_failure
	assert_output --partial "bad secret name '../x'"
	run just-runit secret set A --backend rot13 <<<"${VALUE}"
	assert_failure
	assert_output --partial "unknown backend 'rot13'"
}

# ---- review findings (#230) -------------------------------------------------

# Sabotage-proven (PR #230): rekey or migrate piping a failed decryption
# into the encrypter, then replacing the file with what came out, turns
# these red -- the secret became 0 bytes, or was deleted.
@test 'rekey with a broken identity leaves the secret byte-identical' {
	_need age
	_conf "age $(<"${KEYS}/age1.pub")" "identity ${KEYS}/age1"
	just-runit secret set A --backend age <<<"${VALUE}"
	cp "${STORE}/A.age" "${BATS_TEST_TMPDIR}/before"
	_conf "age $(<"${KEYS}/age1.pub")" "identity ${HOME}/k.TYPO"
	run just-runit secret rekey A
	assert_failure
	assert_output --partial "'A' is unchanged"
	cmp "${STORE}/A.age" "${BATS_TEST_TMPDIR}/before"
	run ls -A "${STORE}"
	assert_output 'A.age'
	_conf "age $(<"${KEYS}/age1.pub")" "identity ${KEYS}/age1"
	assert_equal "$(just-runit secret get A)" "${VALUE}"
}

@test 'migrate whose decryption fails leaves the secret byte-identical' {
	_need gpg age
	_conf_both
	just-runit secret set B --backend gpg <<<"${VALUE}"
	cp "${STORE}/B.gpg" "${BATS_TEST_TMPDIR}/before"
	# The gpg home moved aside: no secret key to decrypt with.
	GNUPGHOME="${BATS_TEST_TMPDIR}/aside"
	mkdir "${GNUPGHOME}"
	chmod 700 "${GNUPGHOME}"
	run just-runit secret migrate B --to age
	assert_failure
	assert_output --partial "'B' is unchanged"
	cmp "${STORE}/B.gpg" "${BATS_TEST_TMPDIR}/before"
	[[ ! -e ${STORE}/B.age ]] || fail 'an age copy was left behind'
	run ls -A "${STORE}"
	assert_output 'B.gpg'
	GNUPGHOME="${JB_TEST_GNUPGHOME}"
	assert_equal "$(just-runit secret get B)" "${VALUE}"
}

# Sabotage-proven (PR #230): without the `set +x` on entry, each of these
# prints the value in a trace line.
@test 'tracing from SHELLOPTS or BASH_ENV never shows a value' {
	_need gpg age script
	_conf_both
	just-runit secret set A --backend gpg <<<"${VALUE}"
	just-runit secret set B --backend age <<<"${VALUE}"
	run env SHELLOPTS=xtrace just-runit secret run A B -- true
	assert_success
	refute_output --partial "${VALUE}"
	printf 'set -x\n' >"${BATS_TEST_TMPDIR}/bash_env"
	run env BASH_ENV="${BATS_TEST_TMPDIR}/bash_env" just-runit secret run A B -- true
	assert_success
	refute_output --partial "${VALUE}"
	run env SHELLOPTS=xtrace just-runit secret get A
	assert_success
	assert_output --partial "${VALUE}"
	refute_output --partial "export"
	run _tty_type "${VALUE}-typed" env SHELLOPTS=xtrace just-runit secret set C --backend age
	assert_success
	refute_output --partial "${VALUE}-typed"
	assert_equal "$(just-runit secret get C)" "${VALUE}-typed"
}

# Sabotage-proven (PR #230): taking any value that names an existing file
# as a recipients file, as before, turns this red.
@test 'a file named like a recipient, planted in the cwd, is not read' {
	_need age
	local mine
	mine="$(<"${KEYS}/age1.pub")"
	_conf "age ${mine}" "identity ${KEYS}/age1"
	cp "${KEYS}/age2.pub" "./${mine}"
	just-runit secret set A --backend age <<<"${VALUE}"
	assert_equal "$(age --decrypt -i "${KEYS}/age1" "${STORE}/A.age")" "${VALUE}"
	run age --decrypt -i "${KEYS}/age2" "${STORE}/A.age"
	assert_failure
}

@test 'a relative age recipients path, or identity, is refused' {
	_need age
	cp "${KEYS}/age1.pub" ./keys.pub
	_conf 'age keys.pub' "identity ${KEYS}/age1"
	run just-runit secret set A --backend age <<<"${VALUE}"
	assert_failure
	assert_output --partial "age recipient 'keys.pub'"
	assert_output --partial 'nor an absolute path'
	[[ ! -e ${STORE}/A.age ]] || fail 'stored anyway'
	_conf "age ${PWD}/keys.pub" "identity ${KEYS}/age1"
	just-runit secret set A --backend age <<<"${VALUE}"
	cp "${KEYS}/age1" ./id
	_conf "age ${PWD}/keys.pub" 'identity id'
	run just-runit secret get A
	assert_failure
	assert_output --partial "identity 'id'"
	refute_output --partial "${VALUE}"
}

# _on_windows -- MSYS2 or Cygwin, where the mode and owner checks are
# documented as skipped: NTFS has no Unix modes for them to read.
_on_windows() { [[ ${OSTYPE:-} == msys* || ${OSTYPE:-} == cygwin* ]]; }

# Sabotage-proven (PR #230): an early `return 0` in _secret_private turns
# this red off Windows. On Windows it asserts the documented skip.
@test 'a recipients file others can write, or that is not yours, is refused' {
	_need age
	_conf "age $(<"${KEYS}/age1.pub")" "identity ${KEYS}/age1"
	chmod 664 "${CONF}"
	run just-runit secret set A --backend age <<<"${VALUE}"
	if _on_windows; then
		assert_success
		return 0
	fi
	assert_failure
	assert_output "just-runit secret: error: ${CONF} is writable by others (mode 664): chmod 600 ${CONF}"
	[[ ! -e ${STORE}/A.age ]] || fail 'stored anyway'
	chmod 600 "${CONF}"
	# Not yours: root hands its copy to nobody; anyone else points the
	# config at a file root owns.
	if [[ $(id -u) -eq 0 ]]; then
		chown nobody "${CONF}"
	else
		cp "${CONF}" "${BATS_TEST_TMPDIR}/mine"
		rm -f "${CONF:?}"
		ln -s /etc/hosts "${CONF}"
	fi
	run just-runit secret set A --backend age <<<"${VALUE}"
	assert_failure
	assert_output --partial "${CONF} is not owned by you"
}

@test 'an age identity others can read is refused' {
	_need age
	cp "${KEYS}/age1" "${HOME}/id"
	_conf "age $(<"${KEYS}/age1.pub")" "identity ${HOME}/id"
	just-runit secret set A --backend age <<<"${VALUE}"
	chmod 644 "${HOME}/id"
	run just-runit secret get A
	if _on_windows; then
		assert_success
		return 0
	fi
	assert_failure
	assert_output "just-runit secret: error: ${HOME}/id is readable by others (mode 644): chmod 600 ${HOME}/id"
	chmod 600 "${HOME}/id"
	assert_equal "$(just-runit secret get A)" "${VALUE}"
}

# Sabotage-proven (PR #230): dropping the denylist turns this red.
@test 'run refuses a VAR that changes how CMD runs' {
	local var
	for var in PATH LD_PRELOAD DYLD_INSERT_LIBRARIES BASH_ENV ENV SHELLOPTS BASHOPTS IFS PS4 BASH_XTRACEFD; do
		run just-runit secret run "A=${var}" -- true
		assert_failure
		assert_output "just-runit secret: error: '${var}' changes how CMD runs; it cannot hold a secret: use NAME=VAR with another VAR"
	done
	run just-runit secret run PATH -- true
	assert_failure
	assert_output --partial "'PATH' changes how CMD runs"
}

# Sabotage-proven (PR #230): dropping the fingerprint check turns this red.
@test 'a gpg recipient must be a full fingerprint, not a short key id' {
	_need gpg
	local fpr
	fpr="$(_fpr 1)"
	_conf "gpg ${fpr: -8}"
	run just-runit secret set A --backend gpg <<<"${VALUE}"
	assert_failure
	assert_output --partial "gpg recipient '${fpr: -8}'"
	assert_output --partial 'is not a full fingerprint (40 hex digits)'
	[[ ! -e ${STORE}/A.gpg ]] || fail 'stored anyway'
	_conf "gpg 0x${fpr}"
	run just-runit secret set A --backend gpg <<<"${VALUE}"
	assert_success
}
