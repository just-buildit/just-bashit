# curl-calls.awk -- print every curl INVOCATION in bash source, one per line:
#
#     FILE:LINE:curl ARG...
#
# For test/curl-tls.bats. Not a grep for the word: the source is scanned as
# the shell would tokenise it -- quotes, ${...}, $(...), <(...), comments,
# heredoc bodies and line continuations -- and `curl` counts only where a
# command name stands: at the start of a command (after a newline, ; | || &&
# & ( $( <( { ! or if/then/do/else/elif/while/until), after a prefix
# assignment, or after a wrapper that runs its argument (env, _run, exec,
# builtin, command, nohup, sudo, _priv, nice, timeout). So `_have curl`,
# `command -v curl`, `packages = ["curl"]` and `_info "would run: curl ..."`
# are not calls; `if ! curl`, `x=$(curl ...)`, `env -u X curl` and `| curl`
# are.
#
# One shape that is not a command is counted on purpose: an array literal
# whose first element is `curl` and whose second is an option, the argv
# network.sh builds for `timeout "${ARGS[@]}"`. `COMMANDS=(curl wget ping)`
# is not one. A bare `curl)` is a case pattern, not a call.
#
# Each line names the line the call STARTS on. ARG words are printed with
# their quotes removed, as the shell would pass them (so the shared array
# reads ${_CURL_TLS[@]+${_CURL_TLS[@]}}); a $(...) inside a word prints as
# the literal $(...), and its own calls are printed on lines of their own.
# A file whose scan does not end balanced prints FILE:EOF:UNBALANCED.
#
# Usage: awk -f curl-calls.awk FILE...   (or with -v name=LABEL on stdin)

function reset_frame() {
	cmdpos[d] = 1
	incurl[d] = 0   # 1: in a curl call, 2: in an eval
	args[d] = ""
	cline[d] = 0
	wrap[d] = ""
	prevopt[d] = 0
	arr[d] = 0
	arrcurl[d] = 0
	mention[d] = 0
	invoked[d] = 0
}

function finding(where, what) {
	print label ":" where ":DYNAMIC " what
}

function finish(case_close) {
	if (incurl[d] == 1 && !(case_close && args[d] == "")) {
		print label ":" cline[d] ":curl" args[d]
		invoked[d] = 1
	}
	if (incurl[d] == 2 && args[d] ~ /curl/)
		finding(cline[d], "eval" args[d])
	incurl[d] = 0
	args[d] = ""
	wrap[d] = ""
	prevopt[d] = 0
}

function is_assign(w) {
	return w ~ /^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=/
}

# curl by name or by path: curl, /usr/bin/curl, ${dir}/curl.
function is_curl(w) {
	return w ~ /(^|\/)curl$/
}

# A complete word at the current frame: decide whether it is a command name.
function word(w, quoted,    v) {
	lastword = w
	if (is_curl(w)) mention[d] = 1
	if (arr[d]) {
		if (arrcurl[d]) {
			# The array's second element decides: an option makes it an argv.
			if (w ~ /^-/) {
				incurl[d] = 1
				args[d] = " " w
				cline[d] = arrline[d]
			}
			arrcurl[d] = 0
			arr[d] = 2
			return
		}
		if (incurl[d]) {
			args[d] = args[d] " " w
			return
		}
		if (arr[d] == 1 && is_curl(w)) {
			arrcurl[d] = 1
			arrline[d] = lno
		}
		arr[d] = 2
		return
	}
	if (incurl[d]) {
		args[d] = args[d] " " w
		return
	}
	if (wrap[d] == "function") {   # `function NAME`: the body follows
		wrap[d] = ""
		cmdpos[d] = 1
		return
	}
	if (wrap[d] == "command") {
		wrap[d] = "run"
		if (w ~ /^-[vV]/) {   # `command -v curl` asks, it does not run
			wrap[d] = ""
			cmdpos[d] = 0
			return
		}
	}
	if (wrap[d] == "run") {
		# A wrapper's options, their values, durations and VAR=value words
		# come before the command it runs: `nice -n 5 curl`, `sudo -E
		# curl`, `env -u X A=b curl`, `timeout 5 curl`, `xargs -I {} curl`.
		# A word after an option is taken as its value, unless it is curl.
		if (w ~ /^-/) { prevopt[d] = 1; return }
		if (is_assign(w)) { prevopt[d] = 0; return }
		if (w ~ /^[0-9.]+[smhd]?$/) { prevopt[d] = 0; return }
		if (prevopt[d] && !is_curl(w)) { prevopt[d] = 0; return }
		wrap[d] = ""
		prevopt[d] = 0
		cmdpos[d] = 1
	}
	if (!cmdpos[d]) return
	if (is_assign(w)) {
		# `CURL=curl`, `c=/usr/bin/curl`, `c="$(command -v curl)"`: a name
		# for curl that a later "$c" would run, which no scan can follow.
		v = w
		sub(/^[^=]*=/, "", v)
		if (is_curl(v) || v ~ /\?curl\?/) finding(wline, w)
		return
	}
	if (!quoted && w ~ /^(if|then|do|else|elif|while|until|time|!|\{)$/) return
	if (!quoted && w ~ /^(_run|exec|builtin|nohup|sudo|doas|_priv|nice|ionice|env|timeout|stdbuf|xargs|coproc|setsid)$/) {
		wrap[d] = "run"
		prevopt[d] = 0
		return
	}
	if (!quoted && w == "command") { wrap[d] = "command"; return }
	if (!quoted && w == "function") { wrap[d] = "function"; return }
	cmdpos[d] = 0
	if (is_curl(w)) {
		incurl[d] = 1
		args[d] = ""
		cline[d] = wline
	} else if (w == "eval") {
		incurl[d] = 2
		args[d] = ""
		cline[d] = wline
	} else if (w ~ /\$/ && (w ~ /[Cc][Uu][Rr][Ll]/)) {
		# A command named by an expansion that mentions curl: `$CURL`,
		# "${CURL:-curl}", "$(command -v curl)". Fails closed.
		finding(wline, w)
	}
}

function flush() {
	if (havetok) word(tok, tokq)
	tok = ""
	tokq = 0
	havetok = 0
}

function addc(c) {
	if (!havetok) wline = lno
	tok = tok c
	havetok = 1
}

function enter(m) { msd++; ms[msd] = m; mode = m }
function leave() { msd--; mode = ms[msd] }

function push(kind) {
	d++
	fkind[d] = kind
	# The word this frame opens inside is resumed when it closes.
	stok[d] = tok
	stokq[d] = tokq
	shave[d] = havetok
	swline[d] = wline
	tok = ""
	tokq = 0
	havetok = 0
	reset_frame()
	if (kind == "sub") enter("n")
}

# Close the innermost frame; a substitution's text joins the word it sits
# in, as $(...) -- or as $(?curl?) when curl was named in it and not run,
# so a word built from it is a name for curl (`"$(command -v curl)" URL`).
function pop(    k, named) {
	finish(0)
	k = fkind[d]
	named = mention[d] && !invoked[d]
	tok = stok[d]
	tokq = stokq[d]
	havetok = shave[d]
	wline = swline[d]
	d--
	if (k == "sub") {
		leave()
		addc(named ? "$(?curl?)" : "$(...)")
	}
	return k
}

BEGIN {
	d = 0
	reset_frame()
	msd = 0
	ms[0] = "n"   # n: normal, s: '...', q: "...", b: ${...}, h: heredoc body
	mode = "n"
	hd = ""
	hdpend = ""
	if (label == "") label = name
}

# A file must end where it began: normal mode, no open frame or heredoc. A
# scan that lost its place would otherwise miss every call after the slip
# and report the file clean, so it is reported instead, as UNBALANCED.
function eof_check() {
	if (started && (msd != 0 || d != 0 || hd != "" || hdpend != ""))
		print label ":EOF:UNBALANCED mode=" mode " frames=" d " heredoc=" hd hdpend
}

END { eof_check() }

FNR == 1 {
	eof_check()
	started = 1
	if (name == "") label = FILENAME
	d = 0
	reset_frame()
	msd = 0
	mode = "n"
	hd = ""
	hdpend = ""
	tok = ""
	havetok = 0
}

{
	lno = FNR
	line = $0
	# A heredoc body. A quoted tag (<<'EOF') expands nothing: skipped. An
	# unquoted one expands $(...) when it runs, so it is scanned as text in
	# which only ${...} and $(...) mean anything (mode h).
	if (hd != "") {
		t = line
		sub(/^\t+/, "", t)
		if (t == hd && (hdq || (mode == "h" && d == hdd))) {
			if (!hdq) leave()
			hd = ""
			tok = ""
			havetok = 0
			next
		}
		if (hdq) next
	}
	n = length(line)
	i = 1
	while (i <= n) {
		c = substr(line, i, 1)
		c2 = substr(line, i, 2)
		if (mode == "s") {
			if (c == "'") leave()
			else addc(c)
			i++
			continue
		}
		if (mode == "q" || mode == "b" || mode == "h") {
			if (c == "\\") {
				addc(substr(line, i + 1, 1))
				i += 2
				continue
			}
			if (mode == "q" && c == "\"") { leave(); i++; continue }
			if (mode == "b" && c == "\"") { enter("q"); i++; continue }
			if (mode == "b" && c == "'") { enter("s"); i++; continue }
			if (mode == "b" && c == "}") { addc(c); leave(); i++; continue }
			if (c2 == "${") { addc(c2); enter("b"); i += 2; continue }
			if (c2 == "$(") { tokq = 1; push("sub"); i += 2; continue }
			addc(c)
			i++
			continue
		}
		# Normal mode.
		if (c == "\\") {
			if (i == n) { i++; continue }   # line continuation
			addc(substr(line, i + 1, 1))
			tokq = 1
			i += 2
			continue
		}
		if (c == "'" || c == "\"") {
			if (!havetok) wline = lno
			havetok = 1
			tokq = 1
			enter(c == "'" ? "s" : "q")
			i++
			continue
		}
		if (c2 == "${") { addc(c2); enter("b"); i += 2; continue }
		if (c == "#" && !havetok) break   # a comment, to the end of the line
		if (c == " " || c == "\t") { flush(); i++; continue }
		if (c2 == "$(" || c2 == "<(" || c2 == ">(") {
			if (c2 == "$(") tokq = 1
			else flush()
			push("sub")
			i += 2
			continue
		}
		if (c == "(") {
			flush()
			if (lastword ~ /=$/ && substr(line, i - 1, 1) == "=") {
				push("arr")
				arr[d] = 1
				cmdpos[d] = 0
			} else {
				push("paren")
			}
			i++
			continue
		}
		if (c == ")") {
			flush()
			if (d > 0) {
				if (pop() != "sub") {
					tok = ""
					havetok = 0
					# After `( ... )` or a function's `()`, a command can
					# follow: the body of `f() { curl ...; }`.
					cmdpos[d] = 1
				}
				i++
				continue
			}
			finish(1)   # a case pattern: `curl)` is not a call
			cmdpos[d] = 1
			i++
			continue
		}
		if (c2 == "<<" && substr(line, i, 3) != "<<<") {
			flush()
			rest = substr(line, i + 2)
			if (match(rest, /^-?[ \t]*['"]?[A-Za-z_][A-Za-z0-9_]*['"]?/)) {
				t = substr(rest, RSTART, RLENGTH)
				hdpq = (t ~ /['"]/)
				gsub(/^-?[ \t]*|['"]/, "", t)
				hdpend = t
				i += 2 + RLENGTH
				continue
			}
			i += 2
			continue
		}
		if (c == "&" && (tok ~ />$/ || substr(line, i + 1, 1) == ">")) {
			addc(c)
			i++
			continue
		}
		if (c == ";" || c == "|" || c == "&") {
			flush()
			finish(0)
			cmdpos[d] = 1
			wrap[d] = ""
			if (c2 == ";;" || c2 == "&&" || c2 == "||" || c2 == "|&") i++
			i++
			continue
		}
		addc(c)
		i++
	}
	# End of line. A newline ends a command only in normal mode and not
	# after a continuation or inside an array literal or a ${...}.
	if (mode == "n" && substr(line, n, 1) != "\\") {
		flush()
		if (!arr[d]) {
			finish(0)
			cmdpos[d] = 1
			wrap[d] = ""
		}
		if (hdpend != "") {
			hd = hdpend
			hdq = hdpq
			hdd = d
			hdpend = ""
			if (!hdq) enter("h")
		}
	} else if (mode != "n") {
		addc("\n")
	}
}
