/* Owns the diagnostic code tables and the rules that classify a message into a code. */
#include "compiler/syntax/diag.h"

#include "base/chars.h"
#include "base/search.h"

static const MsCodeInfo CODES[] = {
    {"MS0000", "Unclassified diagnostic", "read the message; it names the cause and the fix"},
    {"MS1000", "Grammar", "follow the expected token the message names; block headers end with ':'"},
    {"MS1001", "Literals and text", "fix the literal, escape or encoding the message names"},
    {"MS1002", "Layout", "indent with four spaces (or one tab) and keep each suite aligned"},
    {"MS2001", "Names and members", "apply the `fix` edit (nearest name or import), or declare the name"},
    {"MS2002", "Modules and imports", "check the path, extension and [aliases] entry the message names"},
    {"MS2003", "Redundant prelude import", "delete the import; the prelude already provides it"},
    {"MS3000", "General typing", "read the message; it names the rule and the fix"},
    {"MS3001", "Exact types and operators",
     "convert explicitly: to_float(), \"{value}\", or an explicit comparison"},
    {"MS3002", "Duplicate argument", "pass each argument once"},
    {"MS3003", "Missing argument", "supply the parameter the message names"},
    {"MS3004", "Unknown argument", "use one of the parameter names the message lists"},
    {"MS3010", "Overlapping implementation", "keep one method per name and receiver form"},
    {"MS3011", "Signature mismatch", "match the interface operation's signature"},
    {"MS3012", "Implementation receiver", "implement interfaces for types you declare"},
    {"MS3021", "Hashing", "use a Hashable key type"},
    {"MS3030", "Captures", "capture a copy with .clone(), or finish using the value first"},
    {"MS3040", "Recursion", "keep recursive types finite and generic arguments stable"},
    {"MS3050", "Exhaustiveness", "add the missing cases or a final `_:`"},
    {"MS3060", "Mutation", "declare the binding with `var`; the `fix` edit rewrites the binding"},
    {"MS3070", "Numeric literals", "use a value inside the type's range"},
    {"MS3080", "Generic inference", "write the type arguments or annotate the binding"},
    {"MS4000", "Lowering", "report this as a compiler bug with the source"},
};

static const MsSubcode SUBCODES[] = {
    {"MS2001",
     "unknown binding",
     {"MS2001.1", "Unknown name", "apply the `fix` edit, import the name, or declare it"}},
    {"MS2001", "unknown type", {"MS2001.2", "Unknown type", "import the type or declare it"}},
    {"MS2001",
     "unknown or ambiguous member",
     {"MS2001.3", "Unknown member", "use one of the members the message lists"}},
    {"MS2001",
     "unknown case",
     {"MS2001.4", "Unknown alternative case", "name a case the alternative declares"}},
    {"MS2001", "reuses a prelude name", {"MS2001.5", "Prelude name reused", "rename the declaration"}},
    {"MS2001",
     "fixture is available only",
     {"MS2001.6", "Fixture outside tests", "declare a make_fixture factory in the test module"}},
    {"MS2002",
     "unknown standard module",
     {"MS2002.1", "Unknown standard module", "check the module name against the standard library"}},
    {"MS3000",
     "is never read",
     {"MS3000.1", "Unused local binding", "use the binding, or name it with a leading '_'"}},
    {"MS3000",
     "is moved here but used again",
     {"MS3000.2", "Use after move", "pass `.clone()` to keep the value, or stop using it after the move"}},
    {"MS3000",
     "shadows an outer binding",
     {"MS3000.4", "Shadowed binding", "rename one binding, or assign to the outer `var`"}},
    {"MS3000",
     "this statement discards",
     {"MS3000.5", "Discarded Result", "write a trailing `?` to propagate the failure, or handle it"}},
    {"MS3000", "reachable fallthrough", {"MS3000.6", "Missing return", "return a value on every path"}},
    {"MS3000", "division by zero", {"MS3000.7", "Division by zero", "divide by a nonzero value"}},
    {"MS3000",
     "does not satisfy",
     {"MS3000.8", "Bound not satisfied", "use a type that implements the interface"}},
    {"MS3000",
     "cannot be constructed",
     {"MS3000.9", "Interface constructed", "construct a type that implements the interface"}},
    {"MS3000",
     "is a resource that is never closed",
     {"MS3000.10", "Unclosed resource", "call `.close()`, or return it"}},
    {"MS3000", "cannot move ", {"MS3000.11", "Move out of a borrow", "take a copy with `.clone()`, or use the value in place"}},
    {"MS3000",
     "requires a type field",
     {"MS3000.12", "Assignment target", "assign to a type field or a variable"}},
    {"MS3001", "expected ", {"MS3001.1", "Type mismatch", "convert explicitly, or change the declared type"}},
    {"MS3010",
     "overlapping implementation",
     {"MS3010.1", "Overlapping implementation", "keep one method per name and receiver form"}},
    {"MS3011",
     "signature does not match",
     {"MS3011.1", "Signature mismatch", "match the interface operation's signature"}},
    {"MS3000",
     "missing implementation operation",
     {"MS3000.14", "Missing operation", "implement every operation the interface declares"}},
    {"MS3000",
     "extra operation",
     {"MS3000.15", "Extra operation", "remove operations the interface does not declare"}},
    {"MS3000",
     "duplicate implementation operation",
     {"MS3000.16", "Duplicate operation", "define each operation once"}},
    {"MS3012",
     "implementation receiver must be nominal",
     {"MS3012.1", "Implementation receiver", "implement interfaces for a type or alternative you declare"}},
    {"MS3000",
     "implementation target must be an interface",
     {"MS3000.17", "Implementation target", "name an interface as the bound"}},
    {"MS3050", "exhaustive", {"MS3050.1", "Non-exhaustive match", "add the missing cases or a final `_:`"}},
    {"MS3000", "parameter", {"MS3000.18", "Parameter not declared var", "write `var` before the parameter"}},
    {"MS3060",
     "is an immutable binding",
     {"MS3060.2", "Immutable binding changed", "declare the binding with `var`"}},
    {"MS3000",
     "does not change its receiver",
     {"MS3000.19", "Method does not change its receiver", "declare the method `var fn`"}},
    {"MS3080",
     "cannot infer",
     {"MS3080.1", "Cannot infer", "write the type arguments or annotate the binding"}},
    {"MS3000",
     "type arguments, found ",
     {"MS3000.20", "Generic arity", "write every required type argument"}},
};

static const char *const TYPE_RULES[][2] = {
    {"duplicate argument", "MS3002"},
    {"missing argument", "MS3003"},
    {"unknown argument", "MS3004"},
    {"overlapping implementation", "MS3010"},
    {"signature does not match", "MS3011"},
    {"nominal source data", "MS3012"},
    {"Hashable", "MS3021"},
    {"captured", "MS3030"},
    {"recursive", "MS3040"},
    {"exhaustive", "MS3050"},
    {"immutable", "MS3060"},
    {"literal", "MS3070"},
    {"infer", "MS3080"},
    {"generic arity", "MS3080"},
    {"expected ", "MS3001"},
    {"same independently known type", "MS3001"},
};

static bool contains(MsSpan text, const char *needle) {
  MsSpan pattern = ms_span_of_text(needle);
  return ms_find(text.ptr, text.len, pattern.ptr, pattern.len) != SIZE_MAX;
}

/* The text before the first occurrence of `separator`, or all of it. */
static MsSpan before(MsSpan text, const char *separator) {
  MsSpan pattern = ms_span_of_text(separator);
  size_t at = ms_find(text.ptr, text.len, pattern.ptr, pattern.len);
  return at == SIZE_MAX ? text : ms_span_of(text.ptr, at);
}

static bool starts_with(MsSpan text, const char *prefix) {
  return ms_span_starts_with(text, ms_span_of_text(prefix));
}

static const char *parse_code(MsSpan cause) {
  if (starts_with(cause, "string-literal match patterns")) {
    return "MS1000";
  }
  if (contains(cause, "indent") || contains(cause, "suite") || contains(cause, "tabs")) {
    return "MS1002";
  }
  bool literal = contains(cause, "UTF-8") || contains(cause, "scalar") || contains(cause, "escape") ||
                 contains(cause, "literal");
  return literal ? "MS1001" : "MS1000";
}

static const char *resolution_code(MsSpan cause) {
  if (starts_with(cause, "redundant prelude import ")) {
    return "MS2003";
  }
  bool module = contains(cause, "module") || contains(cause, "import") || contains(cause, "path") ||
                contains(cause, "alias");
  return module ? "MS2002" : "MS2001";
}

static const char *type_code(MsSpan cause) {
  for (size_t index = 0; index < MS_COUNT_OF(TYPE_RULES); index++) {
    if (contains(cause, TYPE_RULES[index][0])) {
      return TYPE_RULES[index][1];
    }
  }
  return "MS3000";
}

const char *ms_code_for(const char *phase, MsSpan message) {
  /* Messages read "<cause>; <fix>"; a trailing " (in <use site>)" is not part of the rule. */
  MsSpan cause = before(before(message, "; "), " (in ");
  MsSpan name = ms_span_of_text(phase);
  if (ms_span_is_text(name, "parse")) {
    return parse_code(cause);
  }
  if (ms_span_is_text(name, "resolution")) {
    return resolution_code(cause);
  }
  if (ms_span_is_text(name, "type")) {
    return type_code(cause);
  }
  return ms_span_is_text(name, "lowering") ? "MS4000" : "MS0000";
}

const MsSubcode *ms_subcode_for(const char *family, MsSpan message) {
  MsSpan cause = before(message, "; ");
  for (size_t index = 0; index < MS_COUNT_OF(SUBCODES); index++) {
    if (ms_span_is_text(ms_span_of_text(family), SUBCODES[index].family) &&
        contains(cause, SUBCODES[index].needle)) {
      return &SUBCODES[index];
    }
  }
  return NULL;
}

static bool equal_ignoring_case(const char *left, const char *right) {
  return ms_ascii_equal_fold(ms_span_of_text(left), ms_span_of_text(right));
}

const MsCodeInfo *ms_explain(const char *code) {
  for (size_t index = 0; index < MS_COUNT_OF(CODES); index++) {
    if (equal_ignoring_case(CODES[index].code, code)) {
      return &CODES[index];
    }
  }
  for (size_t index = 0; index < MS_COUNT_OF(SUBCODES); index++) {
    if (equal_ignoring_case(SUBCODES[index].info.code, code)) {
      return &SUBCODES[index].info;
    }
  }
  return NULL;
}
