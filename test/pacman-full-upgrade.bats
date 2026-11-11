# shellcheck disable=SC2154  # bats/common-setup export the harness vars
load 'test_helper/common-setup'
_common_setup

# Arch supports only full upgrades: `pacman -Sy PKG` refreshes the package
# databases without upgrading what is installed, which breaks the moment a
# library bumps its soname. CI's arch leg failed that way on 2026-11-11, when
# openssl 4 would not install beside packages still linked to libcrypto.so.3.
# Every pacman sync this repository runs must therefore upgrade (-Syu). The
# scan covers every tracked file, so a new install path is held without being
# listed.

@test "no pacman sync refreshes without upgrading" {
	cd "${BATS_TEST_DIRNAME}/.."
	# A pacman -S... flag cluster holding y but not u, outside this file.
	# Judged by what grep printed, not its status: xargs exits 123 when
	# any file does not match, which is every file but the offenders.
	run bash -c "git ls-files -z | grep -zv '^test/pacman-full-upgrade.bats\$' |
		xargs -0 grep -nE 'pacman[[:space:]]+-S[a-tv-zA-Z]*y[a-tv-zA-Z]*([[:space:]]|\$)' 2>/dev/null"
	[ -z "${output}" ] || {
		echo "partial upgrades (use -Syu):"
		echo "${output}"
		false
	}
}

@test "the scan sees a partial upgrade" {
	line='_run pacman -Sy --needed --noconfirm x'
	run grep -nE 'pacman[[:space:]]+-S[a-tv-zA-Z]*y[a-tv-zA-Z]*([[:space:]]|$)' <<<"${line}"
	[ "${status}" -eq 0 ]
	line='_run pacman -Syu --needed --noconfirm x'
	run grep -nE 'pacman[[:space:]]+-S[a-tv-zA-Z]*y[a-tv-zA-Z]*([[:space:]]|$)' <<<"${line}"
	[ "${status}" -ne 0 ]
}
