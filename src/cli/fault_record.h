/* cli/fault_record.h: the fault record a test process leaves in the file MS_FAULT_RECORD names (written by
 * runtime/core/record.c, version 2), as the `fault` object of a `--json` test result. Port of the reader in
 * crates/ms-cli/src/fault.rs. */
#ifndef MS_CLI_FAULT_RECORD_H
#define MS_CLI_FAULT_RECORD_H

#include "base/arena.h"
#include "base/safe.h"

/* The object (`{ ... }`, nested six spaces deep, no trailing newline) for the record in `bytes`, or an empty span when
 * they are not a record of this version or are cut short. */
MsSpan fault_record_json(MsArena *arena, MsSpan bytes);

#endif
