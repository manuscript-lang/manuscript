#!/bin/sh
# Interfaces without operations (check_interface.c); see message-diff.sh.
exec sh src/compiler/tests/message-diff.sh interface "an interface declares at least one operation" src/compiler/tests/interfaces
