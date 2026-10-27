breakpoint set -n msrt_string_replace
run
script exec(open('../.github/diag/w.py').read())
breakpoint disable 1
continue
bt 12
disassemble -p -c 8
register read x0 x1 x2 x3 x19 x20 x21 x22 x23 x24
continue
bt 12
