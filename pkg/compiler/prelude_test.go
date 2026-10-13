package compiler

import (
	"strings"
	"testing"
)

func TestPreludeRetainsCaseInferenceAndLookupRules(t *testing.T) {
	for name, source := range map[string]string{
		"none needs payload type":                "fn f() -> Unit:\n    let missing = none\n",
		"ok needs error type":                    "fn f() -> Unit:\n    let result = ok(value: 1)\n",
		"error needs success type":               "fn f() -> Unit:\n    let result = error(cause: \"failed\")\n",
		"ordinary errors need an implementation": "fn f() -> Error:\n    return \"failed\"\n",
		"cases remain ambiguous":                 "type Other:\n    case some(value: Int)\nfn f() -> Optional[Int]:\n    return some(value: 1)\n",
	} {
		t.Run(name, func(t *testing.T) {
			result := CompileSource("prelude.ms", source, Options{AnalyzeOnly: true})
			if result.Success() {
				t.Fatal("accepted invalid prelude use")
			}
			if name == "cases remain ambiguous" && !strings.Contains(result.Diagnostics[0].Message, "ambiguous alternative case") {
				t.Fatal(result.Diagnostics)
			}
		})
	}
}
