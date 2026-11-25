/* Owns the lint rule table of lint_rules.h: the rules of crates/ms-tooling/src/lint/mod.rs in code order. */
#include "tooling/lint_rules.h"

#include <stddef.h>

#include "base/chars.h"

const MsLintRule MS_LINT_RULES[] = {
    {"MSL001", "Trailing whitespace", MS_LINT_WARNING,
     "delete the spaces or tabs at the end of the line; `ms lint --fix` does it"},
    {"MSL002", "Missing final newline", MS_LINT_WARNING,
     "end the file with a newline; `ms lint --fix` does it"},
    {"MSL102", "Unused import", MS_LINT_WARNING,
     "remove the import or use the name; `ms lint --fix` removes it"},
    {"MSL103", "Unreachable statement", MS_LINT_WARNING,
     "delete the statement or the `return`, `break` or `continue` before it"},
    {"MSL106", "Match arm binding shadows a type or case", MS_LINT_ERROR,
     "rename the binding to a lowercase name, or write the case with its payload in a helper"},
    {"MSL107", "Nested match", MS_LINT_ERROR,
     "bind the outer payload with an early exit, use a compatible trailing `?`, or call a small helper"},
    {"MSL108", "Optional matched with only a payload arm and null", MS_LINT_WARNING,
     "use `if value := ... { ... }` with `else { ... }`, or an Optional method such as `get_or(default)` or `map`"},
    {"MSL109", "Result matched with only ok and error", MS_LINT_WARNING,
     "use a trailing `?`, `if value := ... { ... }` with `else { ... }`, or a Result method such as `get_or(default)`, `is_error` or `err`"},
    {"MSL110", "Optional.get() without a default", MS_LINT_WARNING,
     "use `if value := ... { ... }`, or write `get_or(default)`"},
    {"MSL111", "Loop that never waits or exits", MS_LINT_ERROR,
     "wait inside the loop (sleep, or wait on a promise or a pipe), or return"},
    {"MSL112", "Unconditional recursion", MS_LINT_ERROR,
     "add a base case that returns before the recursive call"},
    {"MSL114", "Resource closed at scope end with an uncalled flush", MS_LINT_ERROR,
     "call `name.flush()?` (or `sync`, `commit`) before the scope ends, or close the resource explicitly"},
    {"MSL115", "Promise dropped as soon as it is made", MS_LINT_WARNING,
     "bind the promise and call `wait()` on it, or pass it to `wait_all`; dropping a promise cancels it"},
    {"MSL116", "Undeclared effect", MS_LINT_WARNING,
     "permit it with `// ms: allow_effect <effect>` above the function or in the file header, or move the call to the caller, or take a capability parameter"},
    {"MSL117", "Integer literal interpolated into text", MS_LINT_WARNING,
     "drop the `f` so braces are plain text, or write `\\{4\\}` for literal braces in `f\"...\"` text; delete the braces to write the number"},
    {"MSL118", "Length compared with zero", MS_LINT_ERROR,
     "write `xs.is_empty()` or `not xs.is_empty()`; `ms lint --fix` does it"},
    {"MSL120", "Optional chained after a map get", MS_LINT_ERROR,
     "write `map.get_or(key, default)`; `ms lint --fix` does it"},
    {"MSL121", "Default overridden by a one-line if", MS_LINT_ERROR,
     "write `x := if c { b } else { a }`; `ms lint --fix` does it for a literal or name default"},
    {"MSL122", "Counter loop written as a while", MS_LINT_ERROR,
     "write `for i in start..end { ... }` and drop `i += 1`; `ms lint --fix` does it"},
    {"MSL123", "Index loop that only reads xs[i]", MS_LINT_WARNING,
     "write `for item in xs { ... }` and use `item`"},
    {"MSL124", "Loop that appends or adds into a fresh accumulator", MS_LINT_WARNING,
     "write `xs.map(x => ...)`, `xs.filter(x => ...)` or `xs.sum()`"},
    {"MSL125", "Loop that appends every element", MS_LINT_WARNING,
     "write `out.extend(xs)`"},
    {"MSL126", "Binding returned on the next line", MS_LINT_ERROR,
     "write `return <expression>`"},
    {"MSL127", "Map entry rebuilt from its own lookup", MS_LINT_ERROR,
     "write `m[k] -= v` (or `+=`, `*=`, `/=`, `%=`)"},
    {"MSL128", "Final return the end of the function already makes", MS_LINT_ERROR,
     "delete the final `return ok()` (`Void!`) or `return` (`Void`)"},
    {"MSL129", "Void! outcome ignored with get_or(null)", MS_LINT_ERROR,
     "write `void call()`; `ms lint --fix` does it"},
    {"MSL130", "Statement get() on a Result", MS_LINT_WARNING,
     "write `call()?` in a function that returns a Result (`main` can return `Void!`), or `void call()` to ignore the outcome"},
    {"MSL131", "Result printed as a value", MS_LINT_WARNING,
     "write `call()?` in a function that returns a Result, or `if value := call() { ... }` to read the success"},
    {"MSL132", "slice result replaced by a fallback", MS_LINT_WARNING,
     "write `xs.slice(a, b)?`, or clamp the end with `min(end, xs.length())` before slicing"},
    {"MSL133", "`//` after an operand reads like floor division", MS_LINT_WARNING,
     "`//` starts a comment, so the number after it is ignored; Int `/` already truncates, so write `a / 2`"},
    {"MSL134", "Void value bound or printed", MS_LINT_WARNING,
     "call `xs.sort()` or `xs.reverse()` as a statement, or use `sorted()` or `reversed()` for a new list"},
    {"MSL135", "`to_string()` on Bytes", MS_LINT_WARNING,
     "`bytes.to_string()` renders `Bytes(104, 105)`; write `ok_or(bytes.decode_utf8(), Error(\"not UTF-8\", kind: \"EBADMSG\"))?` for the text"},
};

const size_t MS_LINT_RULE_COUNT = sizeof MS_LINT_RULES / sizeof MS_LINT_RULES[0];

const MsLintRule *ms_lint_rule(MsSpan code) {
  for (size_t i = 0; i < MS_LINT_RULE_COUNT; i++) {
    if (ms_ascii_equal_fold(ms_span_of_text(MS_LINT_RULES[i].code), code)) {
      return &MS_LINT_RULES[i];
    }
  }
  return NULL;
}
