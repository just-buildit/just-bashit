source 'src/just_bashit/function-template.sh'
load 'test_helper/common-setup'
_common_setup

EXPECTED_FULL_ON_HELP=$(
	cat <<'EOF'
Usage: full-on-template [OPTIONS] [-p PARAM] [ARGS] ...

  Function Title and Short Summary.

Options:
  -h        Show this message and exit.
  -p PARAM  Option that accepts an argument stored in $OPTARG.
  -v        Show the version and exit.

Arguments:
  MYCMD     Some command or other stored in $1
  MYVAR     Some variable or other stored in $2
EOF
)
EXPECTED_UNKNOWN=$(
	cat <<EOF
Invalid option: -u
${EXPECTED_FULL_ON_HELP}
EOF
)

@test "unknown option -u" {
	run full-on-template -u
	echo "${EXPECTED_UNKNOWN}" | assert_output -
}

@test "option -h" {
	run full-on-template -h
	echo "${EXPECTED_FULL_ON_HELP}" | assert_output -
}

@test "option -v" {
	run full-on-template -v
	assert_output - <<-EOF
		X.Y.Z
	EOF
}

@test "option -p myparam" {
	run full-on-template -p myparam
	assert_output - <<-EOF
		Option -p specified with argument: myparam
	EOF
}

@test "command" {
	run full-on-template SOMECMD
	assert_output - <<-EOF
		Executing cmd()
	EOF
}

@test "positional args" {
	run full-on-template myarg1 myarg2 myarg3
	assert_output - <<-'EOF'
		Processing argument: myarg1 from $@ in a loop
		Processing argument: myarg2 from $@ in a loop
		Processing argument: myarg3 from $@ in a loop
	EOF
}

EXPECTED_MINIMALIST_HELP=$(
	cat <<'EOF'
Usage: minimalist-template [OPTIONS] [-p PARAM] [ARGS] ...

  Summarize what cool thing this function does.

Options:
  -h     Show this message and exit.

Arguments:
  MYVAR  Some variable or other stored in $1
EOF
)

@test "minimalist option -h" {
	run minimalist-template -h
	echo "${EXPECTED_MINIMALIST_HELP}" | assert_output -
}

@test "minimalist no input" {
	run minimalist-template
	echo "${EXPECTED_MINIMALIST_HELP}" | assert_output -
}

@test "minimalist argument myvar" {
	run minimalist-template myvar
	echo "Doing something cool with myvar" | assert_output -
}
