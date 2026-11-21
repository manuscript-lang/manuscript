/* syntax/diag_json.c: the JSON text of diagnostics (diag_json.h). */
#include "compiler/syntax/diag_json.h"

#include "base/utf8.h"
#include "compiler/syntax/diag.h"

static void indent(MsStrBuild *out, size_t spaces) {
  for (size_t index = 0; index < spaces; index++) {
    ms_strbuild_append_byte(out, ' ');
  }
}

static void unicode_escape(MsStrBuild *out, uint32_t scalar) {
  ms_strbuild_append_text(out, "\\u");
  for (int shift = 12; shift >= 0; shift -= 4) {
    ms_strbuild_append_byte(out, (uint8_t) "0123456789abcdef"[(scalar >> shift) & 15U]);
  }
}

void ms_json_string(MsStrBuild *out, MsSpan text) {
  ms_strbuild_append_byte(out, '"');
  for (size_t at = 0; at < text.len;) {
    const MsRune rune = ms_utf8_decode(text.ptr + at, text.len - at);
    const uint32_t scalar = rune.rune;
    switch (scalar) {
    case '"':
      ms_strbuild_append_text(out, "\\\"");
      break;
    case '\\':
      ms_strbuild_append_text(out, "\\\\");
      break;
    case '\n':
      ms_strbuild_append_text(out, "\\n");
      break;
    case '\r':
      ms_strbuild_append_text(out, "\\r");
      break;
    case '\t':
      ms_strbuild_append_text(out, "\\t");
      break;
    case 0x08:
      ms_strbuild_append_text(out, "\\b");
      break;
    case 0x0c:
      ms_strbuild_append_text(out, "\\f");
      break;
    case '<':
    case '>':
    case '&':
    case 0x2028:
    case 0x2029:
      unicode_escape(out, scalar);
      break;
    default:
      if (scalar < 0x20) {
        unicode_escape(out, scalar);
      } else {
        ms_strbuild_append(out, ms_span_of(text.ptr + at, rune.width));
      }
    }
    at += rune.width;
  }
  ms_strbuild_append_byte(out, '"');
}

static void member(MsStrBuild *out, size_t depth, const char *name, uint64_t value, bool last) {
  indent(out, depth * 2);
  ms_strbuild_append_byte(out, '"');
  ms_strbuild_append_text(out, name);
  ms_strbuild_append_text(out, "\": ");
  ms_strbuild_append_u64(out, value);
  ms_strbuild_append_text(out, last ? "\n" : ",\n");
}

void ms_json_position(MsStrBuild *out, MsSpan file, MsPos pos, size_t depth) {
  ms_strbuild_append_text(out, "{\n");
  indent(out, (depth + 1) * 2);
  ms_strbuild_append_text(out, "\"file\": ");
  ms_json_string(out, file);
  ms_strbuild_append_text(out, ",\n");
  member(out, depth + 1, "line", pos.line, false);
  member(out, depth + 1, "column", pos.column, false);
  member(out, depth + 1, "offset", pos.offset, true);
  indent(out, depth * 2);
  ms_strbuild_append_byte(out, '}');
}

static void fix_object(MsStrBuild *out, MsSpan file, const MsDiag *diag) {
  ms_strbuild_append_text(out, ",\n      \"fix\": {\n        \"position\": ");
  ms_json_position(out, file, diag->fix_pos, 4);
  ms_strbuild_append_text(out, ",\n        \"end\": ");
  ms_json_position(out, file, diag->fix_end, 4);
  ms_strbuild_append_text(out, ",\n        \"replacement\": ");
  ms_json_string(out, diag->replacement);
  ms_strbuild_append_text(out, "\n      }");
}

void ms_json_diag(MsStrBuild *out, MsSpan file, const char *phase, const MsDiag *diag) {
  const char *family = ms_code_for(phase, diag->message);
  const MsSubcode *kind = ms_subcode_for(family, diag->message);
  ms_strbuild_append_text(out, "    {\n      \"code\": ");
  ms_json_string(out, ms_span_of_text(family));
  if (kind != NULL) {
    ms_strbuild_append_text(out, ",\n      \"subcode\": ");
    ms_json_string(out, ms_span_of_text(kind->info.code));
  }
  ms_strbuild_append_text(out, ",\n      \"phase\": ");
  ms_json_string(out, ms_span_of_text(phase));
  ms_strbuild_append_text(out, ",\n      \"message\": ");
  ms_json_string(out, diag->message);
  ms_strbuild_append_text(out, ",\n      \"position\": ");
  ms_json_position(out, file, diag->pos, 3);
  if (diag->has_end) {
    ms_strbuild_append_text(out, ",\n      \"end\": ");
    ms_json_position(out, file, diag->end, 3);
  }
  if (diag->has_fix) {
    fix_object(out, file, diag);
  }
  ms_strbuild_append_text(out, "\n    }");
}
