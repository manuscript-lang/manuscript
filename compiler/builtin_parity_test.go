package compiler

import (
	"strings"
	"testing"
)

func TestNativeMethodConstraints(t *testing.T) {
	prelude := `import List from "@std/collections.ms"
import Map from "@std/collections.ms"
fn stringify(value: Int) -> String:
    return "{value}"
fn wrong_label(item: Int) -> String:
    return "{item}"
fn callback() -> Unit:
    return unit
`
	for name, body := range map[string]string{
		"unspecialized value":          "let convert = [1].map",
		"wrong output":                 "let convert = [1].map[Int](transform: stringify)",
		"wrong callback label":         "let convert = [1].map(transform: wrong_label)",
		"wrong specialization arity":   "let convert = [1].map[String, Int](transform: stringify)",
		"nongeneric specialization":    "let reversed = [1].reverse[Int]()",
		"join nonstrings":              "let text = [1].join(separator: \",\")",
		"nonhashable conversion":       "let values = [1.5].to_set()",
		"nonhashable conversion value": "let convert = [1.5].to_set",
		"function equality":            "let values = [callback].contains(value: callback)",
		"nonshareable output":          "let values = [1].map(transform: fn(value: Int) -> fn() -> Unit:\n        return callback\n    )",
		"map merge wrong type":         "let values = Map[String, Int]().merge(other: Map[Int, String]())",
	} {
		t.Run(name, func(t *testing.T) {
			source := prelude + "test \"reject\":\n    " + body + "\n"
			result := CompileSource(name+".ms", source, Options{})
			if result.Success() {
				t.Fatal("accepted invalid native method", source)
			}
			for _, d := range result.Diagnostics {
				if d.Phase == "parse" || d.Phase == "lex" || strings.Contains(d.Message, "runtime invariant") {
					t.Fatal(d)
				}
			}
		})
	}
}

func TestNativeMethodRetainsGenericReceiverBounds(t *testing.T) {
	for _, source := range []string{
		`import List from "@std/collections.ms"
fn search[T: Shareable & Equal](values: List[T], value: T) -> Bool:
    return values.contains(value: value)
`,
		`import List from "@std/collections.ms"
import Set from "@std/collections.ms"
fn unique[T: Shareable & Hashable](values: List[T]) -> Set[T]:
    return values.to_set()
`,
		`import List from "@std/collections.ms"
fn convert[T: Shareable, U: Shareable](values: List[T], transform: fn(value: T) -> U) -> List[U]:
    return values.map(transform: transform)
`,
	} {
		result := CompileSource("generic.ms", source, Options{})
		if !result.Success() {
			t.Fatal(result.Diagnostics)
		}
	}
	source := `import List from "@std/collections.ms"
fn search[T: Shareable](values: List[T], value: T) -> Bool:
    return values.contains(value: value)
`
	if result := CompileSource("bounds.ms", source, Options{}); result.Success() {
		t.Fatal("equality search lost Equal bound")
	}
}
