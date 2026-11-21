/* syntax/diag.h: stable diagnostic codes (MS1000, MS3000.1, ...), the same as crates/ms-syntax/src/diag.rs.
 */
#ifndef MS_SYNTAX_DIAG_H
#define MS_SYNTAX_DIAG_H

#include "compiler/syntax/pos.h"

typedef struct MsCodeInfo {
  const char *code, *family, *repair;
} MsCodeInfo;

typedef struct MsSubcode {
  const char *family, *needle;
  MsCodeInfo info;
} MsSubcode;

/* The rule family for a diagnostic of `phase` ("parse", "resolution", "type", "lowering", ...). */
const char *ms_code_for(const char *phase, MsSpan message);

/* The first sub-code of `family` whose needle appears in the message's cause, or NULL. */
const MsSubcode *ms_subcode_for(const char *family, MsSpan message);

/* The entry for a code or sub-code, matched case-insensitively, or NULL. */
const MsCodeInfo *ms_explain(const char *code);

#endif
