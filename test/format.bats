load 'test_helper/common-setup'
source 'src/format.sh'
_common_setup
# shellcheck disable=SC2154
echo "${HELP_REGEX}" >/dev/null

@test 'color-echo help' {
	run color-echo -h
	# shellcheck disable=SC2154
	assert_output --regexp "${HELP_REGEX}"
}
@test 'color-echo -c' {
	colors=(black red green yellow blue magenta cyan white)
	for color in "${colors[@]}"; do
		run color-echo -c "${color}" "HELLO WORLD!"
		assert_success
	done
}
@test 'color-echo -bc' {
	colors=(black red green yellow blue magenta cyan white)
	for color in "${colors[@]}"; do
		run color-echo -bc "${color}" "HELLO WORLD!"
		assert_success
	done
}
@test 'color-echo -c mixed case' {
	run color-echo -c YelLoW "HELLO WORLD!"
	assert_success
}
@test 'color-echo -c misspelling' {
	run color-echo -c YelLoWe "HELLO WORLD!"
	assert_failure
}

@test 'trim-from help' {
	run trim-from -h
	# shellcheck disable=SC2154
	assert_output --regexp "${HELP_REGEX}"
}
@test 'trim-from unknown option -t' {
	run trim-from -t
	assert_output --regexp "$(
		echo "Invalid option: -t"
		# shellcheck disable=SC2154
		echo "${HELP_REGEX}"
	)"
}
@test 'trim-from' {
	run trim-from 12.45
	assert_output 12
}
@test 'trim-from -r 12.45' {
	run trim-from -r 12.45
	assert_output 45
}
@test 'trim-from 12.4.45' {
	run trim-from 12.4.45
	assert_output 12.4
}
@test 'trim-from -g 12.4.45' {
	run trim-from -g 12.4.45
	assert_output 12
}
@test 'trim-from -kg 12.4.45' {
	run trim-from -kg 12.4.45
	assert_output 12.
}
@test 'trim-from -m MA "HEYMA!"' {
	run trim-from -m MA "HEYMA!"
	assert_output HEY
}
@test 'trim-from -rm MA "HEYMA!"' {
	run trim-from -rm MA "HEYMA!"
	assert_output '!'
}

@test 'trim-from -k keeps marker (12.45 → 12.)' {
	run trim-from -k 12.45
	assert_output '12.'
}

@test 'trim-from -rk keeps marker reverse (HEYMA! → MA!)' {
	run trim-from -rm MA -k "HEYMA!"
	assert_output 'MA!'
}

@test 'trim-from -rkg greedy reverse keep (12.4.45 → .45)' {
	run trim-from -rkg 12.4.45
	assert_output '.45'
}

@test 'color-echo with no argument prints empty line' {
	run color-echo
	assert_success
}

@test 'color-echo unknown color returns failure' {
	run color-echo -c ultraviolet "TEXT"
	assert_failure
}
