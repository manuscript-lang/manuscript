/* compiler/check/names_habit.c: the hints for names borrowed from other languages (see names_hint.h). */
#include "compiler/check/names_habit.h"

typedef struct Habit {
  const char *names[10]; /* NULL-terminated */
  const char *text;      /* the hint; "{}" stands for the name */
  const char *edit;      /* the spelling to replace the name with, or NULL */
} Habit;

static const Habit HABITS[] = {
    {{"range"},
     "there is no range function: write start..end for the integers from start up to but excluding end, or "
     "range_by from \"@std/collections/collections.ms\" for a stepped list",
     NULL},
    {{"nil", "null", "None", "undefined"},
     "Manuscript has no null: absence is an Optional, written none, and a present value is just the value, "
     "which converts where an Optional is expected",
     "none"},
    {{"Some"},
     "there is no Some: a plain value converts where an Optional is expected, so pass it directly", NULL},
    {{"Ok"}, "write the lowercase ok(value) for a successful Result", "ok"},
    {{"Err", "err", "Error"},
     "write error(cause) for a failed Result, where cause has the Result's error type", "error"},
    {{"True"}, "booleans are lowercase: write true and false", "true"},
    {{"False"}, "booleans are lowercase: write true and false", "false"},
    {{"len"},
     "there is no {}() function: call the length member, e.g. xs.length() (String length is bytes; "
     "scalar_length counts scalars)",
     NULL},
    {{"str", "toString", "repr", "sprintf"},
     "to make text, interpolate: f\"{value}\", or call value.to_string()", NULL},
    {{"int", "parseInt", "atoi", "Number", "parse_int"},
     "parse text with text.parse_int(), which returns Int?; Float has truncate_to_int()", NULL},
    {{"float", "parseFloat", "parse_float"},
     "parse text with parse_float (import parse_float from \"@std/math/math.ms\"), which returns a Result; an "
     "Int converts with value.to_float()",
     NULL},
    {{"Object", "Array", "dict", "list"},
     "use the prelude List[T] and Map[K, V] types without imports; read a Map with m.keys(), m.values() or "
     "m.entries()",
     NULL},
    {{"Math", "math"},
     "the math functions (floor, sqrt, pow, ...) are in \"@std/math/math.ms\": import floor from "
     "\"@std/math/math.ms\"",
     NULL},
    {{"console", "System", "fmt", "os", "println", "printf", "puts", "echo"},
     "there is no {}: use print(value), which writes any value and a newline; for write errors or bytes "
     "import stdout from \"@std/io/io.ms\" and call stdout().write(\"text\\n\")",
     NULL},
    {{"spawn", "Promise", "Future", "Thread", "thread", "setTimeout", "setInterval"},
     "there is no free {}: start concurrent work with promise(fn: ...) from "
     "\"@std/concurrency/promise.ms\" and call wait() on the returned Promise",
     NULL},
    {{"filesystem", "network", "commands", "control", "system", "clock", "wall_clock", "entropy", "terminal",
      "files"},
     "host handle getters were removed: import the operation itself, e.g. read_file from \"@std/os/fs.ms\", "
     "connect from \"@std/net/net.ms\", run from \"@std/os/process.ms\", now from \"@std/time.ms\"",
     NULL},
};

static void append_template(MsStrBuild *out, const char *text, MsSpan name) {
  for (const char *at = text; *at != '\0'; at++) {
    if (at[0] == '{' && at[1] == '}') {
      ms_strbuild_append(out, name);
      at++;
    } else {
      ms_strbuild_append_byte(out, (uint8_t)*at);
    }
  }
}

static bool has_name(const Habit *habit, MsSpan name) {
  for (size_t index = 0; index < MS_COUNT_OF(habit->names) && habit->names[index] != NULL; index++) {
    if (ms_span_is_text(name, habit->names[index])) {
      return true;
    }
  }
  return false;
}

bool ms_name_habit(MsSpan name, MsStrBuild *hint, const char **edit) {
  for (size_t index = 0; index < MS_COUNT_OF(HABITS); index++) {
    if (has_name(&HABITS[index], name)) {
      append_template(hint, HABITS[index].text, name);
      *edit = HABITS[index].edit;
      return true;
    }
  }
  return false;
}
