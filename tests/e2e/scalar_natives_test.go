package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestScalarStandardCallsMatchDynamicCalls(t *testing.T) {
	result := compiler.CompileSource("scalar-natives.ms", `import panic from "@std/faults.ms"
import {abs, abs_int, atan2, ceil, floor, max, min, pow, remainder, round, sqrt, truncate} from "@std/math.ms"

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

fn viaValue(f: fn(value: Float) -> Float, x: Float) -> Float: f(value: x)

test "typed math":
    check(ok: sqrt(value: 9.0) == 3.0, name: "sqrt")
    check(ok: viaValue(f: sqrt, x: 16.0) == 4.0, name: "sqrt value")
    check(ok: abs(value: 0.0 - 2.5) == 2.5 and abs_int(value: 0 - 7) == 7, name: "abs")
    check(ok: floor(value: 2.7) == 2.0 and ceil(value: 2.1) == 3.0 and truncate(value: 0.0 - 2.7) == 0.0 - 2.0, name: "rounding")
    check(ok: round(value: 2.5) == 3.0 and round(value: 0.0 - 2.5) == 0.0 - 2.0, name: "round half up")
    check(ok: pow(base: 2.0, exponent: 10.0) == 1024.0, name: "pow")
    check(ok: min(left: 1.0, right: 2.0) == 1.0 and max(left: 1.0, right: 2.0) == 2.0, name: "min max")
    check(ok: remainder(left: 7.0, right: 4.0) == 3.0, name: "remainder")
    check(ok: atan2(y: 0.0, x: 1.0) == 0.0, name: "atan2")
    check(ok: sqrt(value: 0.0 - 1.0).is_nan() and sqrt(value: 1.0).is_finite(), name: "classification")
    var total = 0.0
    var i = 0
    while i < 4:
        total = total + sqrt(value: 4.0) + abs(value: 0.0 - 1.0)
        i = i + 1
    check(ok: total == 12.0, name: "typed accumulation")

test "typed string members":
    let text = "  Hello World  "
    check(ok: text.trim() == "Hello World", name: "trim")
    check(ok: text.trim().upper() == "HELLO WORLD" and text.trim().lower() == "hello world", name: "case")
    check(ok: text.contains(value: "World") and not text.contains(value: "world"), name: "contains")
    check(ok: text.trim().starts_with(prefix: "Hello") and text.trim().ends_with(suffix: "World"), name: "affixes")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("scalar standard calls changed: %v\n%s", err, output)
	}
}

func TestAbsIntOverflowStillFaults(t *testing.T) {
	result := compiler.CompileSource("abs-overflow.ms", `import {abs_int} from "@std/math.ms"

test "overflow":
    let smallest = 0 - 9223372036854775807 - 1
    abs_int(value: smallest)
`, compiler.Options{Tests: true})
	output, _ := execute(t, result)
	if !strings.Contains(string(output), "Int overflow") {
		t.Fatalf("expected overflow fault\n%s", output)
	}
}

func TestScalarMembersMatchDynamicCalls(t *testing.T) {
	result := compiler.CompileSource("scalar-members.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

test "string and float members":
    let text = "héllo"
    check(ok: text.length() == 5 and not text.is_empty() and "".is_empty(), name: "length")
    check(ok: "a".compare(other: "b") == 0 - 1 and "b".compare(other: "b") == 0, name: "compare")
    check(ok: text.concat(other: "!") == "héllo!", name: "concat")
    check(ok: (0.0 / 0.0).is_nan() and not (1.0).is_nan() and (1.0).is_finite(), name: "float")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("scalar members changed: %v\n%s", err, output)
	}
}

func TestStringSplitReplaceJoinMatchDynamicCalls(t *testing.T) {
	result := compiler.CompileSource("split-replace-join.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

test "omitted and supplied caps":
    check(ok: "a,b,c".split(separator: ",").length() == 3, name: "split")
    check(ok: "a,b,c".split(separator: ",", max_parts: some(2)).length() == 2, name: "split cap")
    check(ok: "a,b,c".split(separator: ",", max_parts: none).length() == 3, name: "split none")
    check(ok: "".split(separator: ",").length() == 1, name: "split empty")
    check(ok: "abc".split(separator: "").length() == 3, name: "split scalars")
    check(ok: "a-b-c".replace(old: "-", new: "+") == "a+b-c", name: "replace first")
    check(ok: "a-b-c".replace(old: "-", new: "+", max_replacements: some(2)) == "a+b+c", name: "replace cap")
    check(ok: "a-b-c".replace_first(old: "-", new: "+") == "a+b-c", name: "replace_first")
    check(ok: "ab".replace(old: "", new: "_") == "_ab", name: "replace empty old")
    check(ok: "".replace(old: "x", new: "y") == "", name: "replace empty text")
    check(ok: ["a", "b", "c"].join(separator: "-") == "a-b-c", name: "join")
    let none_left: List[String] = []
    check(ok: none_left.join(separator: "-") == "", name: "join empty")
    var parts = ["x"]
    parts.append(value: "y")
    check(ok: parts.join(separator: "") == "xy", name: "join appended")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("string split/replace/join changed: %v\n%s", err, output)
	}
}

func TestNegativeSplitCapStillFaults(t *testing.T) {
	result := compiler.CompileSource("split-fault.ms", `test "negative":
    "a,b".split(separator: ",", max_parts: some(0 - 1))
`, compiler.Options{Tests: true})
	output, _ := execute(t, result)
	if !strings.Contains(string(output), "max_parts must be nonnegative") {
		t.Fatalf("expected split fault\n%s", output)
	}
}

func TestBoundNativeCallsOmitNoneDefaults(t *testing.T) {
	result := compiler.CompileSource("bound-omitted.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

test "omitted none defaults":
    match "ab".repeat(count: 2):
        ok(v):
            check(ok: v == "abab", name: "repeat")
        error(_):
            check(ok: false, name: "repeat error")
    match "ab".pad_start(target_length: 4, padding: "-"):
        ok(v):
            check(ok: v == "--ab", name: "pad_start")
        error(_):
            check(ok: false, name: "pad_start error")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("omitted none defaults changed: %v\n%s", err, output)
	}
}

func TestStringParseIntAndToBytesMatchDynamicCalls(t *testing.T) {
	result := compiler.CompileSource("parse-int.ms", `import panic from "@std/faults.ms"

fn check(ok: Bool, name: String) -> Unit:
    if not ok:
        return panic(message: name)

fn parsed(text: String) -> Int:
    match text.parse_int():
        some(v):
            return v
        none:
            return 0 - 1

test "parse_int":
    check(ok: parsed(text: "123") == 123, name: "plain")
    check(ok: parsed(text: "-7") == 0 - 7 and parsed(text: "+8") == 8, name: "signs")
    check(ok: parsed(text: "") == 0 - 1 and parsed(text: "-") == 0 - 1 and parsed(text: "1x") == 0 - 1, name: "invalid")
    check(ok: parsed(text: "99999999999999999999") == 0 - 1, name: "overflow")
    check(ok: "héllo".to_bytes().length() == 6, name: "to_bytes")
`, compiler.Options{Tests: true})
	output, err := execute(t, result)
	if err != nil || !strings.Contains(string(output), "PASS") {
		t.Fatalf("parse_int/to_bytes changed: %v\n%s", err, output)
	}
}
