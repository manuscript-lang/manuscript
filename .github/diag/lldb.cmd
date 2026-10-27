breakpoint set -n msrt_string_replace
breakpoint command add 1
memory read -fx -s8 -c2 $x0
memory read -fx -s8 -c2 $x1
memory read -fx -s8 -c2 $x2
continue
DONE
run
bt 15
register read x0 x1 x2 x3 x19 x20 x21 x22 x23 x24 x25 x26 x27 x28
