#!/bin/sh
# A public signature names no private type (check_public.c); see message-diff.sh.
exec sh compiler/tests/message-diff.sh public 'public signature exposes private type' compiler/tests/public
