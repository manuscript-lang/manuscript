#!/bin/sh
# Redundant prelude imports with their exact-source fix (check_scope.c); see message-diff.sh.
exec sh src/compiler/tests/message-diff.sh prelude 'redundant prelude import' src/compiler/tests/prelude
