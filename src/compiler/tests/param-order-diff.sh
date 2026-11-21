#!/bin/sh
# Optional parameters and fields come last (check_param_order.c); see message-diff.sh.
exec sh src/compiler/tests/message-diff.sh param-order "required .* follows optional" src/compiler/tests/paramorder
