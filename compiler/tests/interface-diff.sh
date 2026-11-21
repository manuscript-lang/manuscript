#!/bin/sh
# Interfaces without operations (check_interface.c); see message-diff.sh.
exec sh compiler/tests/message-diff.sh interface "an interface declares at least one operation" compiler/tests/interfaces
