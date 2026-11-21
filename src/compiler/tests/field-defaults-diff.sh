#!/bin/sh
# Field defaults against their field types (check_body.c); see message-diff.sh.
MS_DIFF_CLEAN_ONLY=1 exec sh src/compiler/tests/message-diff.sh field-defaults "expected .*, found |unknown binding " src/compiler/tests/fielddefaults
