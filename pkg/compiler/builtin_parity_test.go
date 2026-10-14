package compiler

import (
	"strings"
	"testing"
)

func TestNativeMethodConstraints(t *testing.T) {
	prelude := `fn stringify(value: Int) -> String:
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
		`fn search[T: Equal](values: List[T], value: T) -> Bool:
    return values.contains(value: value)
`,
		`fn unique[T: Hashable](values: List[T]) -> Set[T]:
    return values.to_set()
`,
		`fn convert[T, U](values: List[T], transform: fn(value: T) -> U) -> List[U]:
    return values.map(transform: transform)
`,
	} {
		result := CompileSource("generic.ms", source, Options{})
		if !result.Success() {
			t.Fatal(result.Diagnostics)
		}
	}
	source := `fn search[T](values: List[T], value: T) -> Bool:
    return values.contains(value: value)
`
	if result := CompileSource("bounds.ms", source, Options{}); result.Success() {
		t.Fatal("equality search lost Equal bound")
	}
}
