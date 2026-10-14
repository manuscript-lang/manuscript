package compiler

import (
	"strings"
	"testing"
)

func TestHTMLUnescapeRejectsInvalidContracts(t *testing.T) {
	for _, test := range []struct{ name, source, want string }{
		{"input is text", `fn wrong() -> String: unescape(1)`, "String"},
		{"result is plain text", `fn wrong() -> Result[String, String]: unescape("&lt;")`, "String"},
		{"stored label", `fn wrong() -> String:
    let convert = unescape
    return convert(value: "&amp;")`, "value"},
	} {
		t.Run(test.name, func(t *testing.T) {
			result := CompileSource("html-unescape.ms", "import unescape from \"@std/html.ms\"\n"+test.source+"\n", Options{AnalyzeOnly: true})
			if result.Success() {
				t.Fatal("accepted invalid unescape contract")
			}
			for _, diagnostic := range result.Diagnostics {
				if strings.Contains(diagnostic.Message, test.want) {
					return
				}
			}
			t.Fatalf("expected %q, got %v", test.want, result.Diagnostics)
		})
	}
}
