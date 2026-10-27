#!/bin/sh
set -eu
out=
for arg do
    if [ "$arg" = -o ]; then next=out; continue; fi
    if [ "${next-}" = out ]; then out=$arg; next=; fi
    case "$arg" in */libms_native.a) test "$(cat "$arg")" = fresh ;; esac
done
printf '#!/bin/sh\nexit 0\n' > "$out"
chmod +x "$out"
