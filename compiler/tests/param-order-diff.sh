#!/bin/sh
# Optional parameters and fields come last (check_param_order.c); see message-diff.sh.
exec sh compiler/tests/message-diff.sh param-order "required .* follows optional" compiler/tests/paramorder
