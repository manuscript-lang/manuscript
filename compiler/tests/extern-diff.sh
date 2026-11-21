#!/bin/sh
# The rules for a program's own extern fn and extern type (check_extern.c); see message-diff.sh.
exec sh compiler/tests/message-diff.sh extern 'extern (parameter|Result|error type|result|type|fn)|an extern fn cannot' compiler/tests/externs
