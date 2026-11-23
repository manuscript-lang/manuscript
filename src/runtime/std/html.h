/* runtime/std/html.h: the @std/data/html natives (src/runtime/std/html.c): escaping and character-reference
 * decoding. Parsing lives in Manuscript. */
#ifndef MS_RUNTIME_STD_HTML_H
#define MS_RUNTIME_STD_HTML_H

#include "base/string.h"

/* ms-sig: msstd_html_escape(text: *const StrVal, out: *mut StrVal) @domain=HTML @end */
void msstd_html_escape(const MsString *text, MsString *out);
/* ms-sig: msstd_html_unescape(text: *const StrVal, out: *mut StrVal) @domain=HTML @end */
void msstd_html_unescape(const MsString *text, MsString *out);
/* Decodes references as the tokenizer does, in attribute-value mode when `attribute`.
 * ms-sig: msstd_html_decode(text: *const StrVal, attribute: u8, out: *mut StrVal) @domain=HTML @end */
void msstd_html_decode(const MsString *text, uint8_t attribute, MsString *out);

#endif
