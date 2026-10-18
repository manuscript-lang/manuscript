package parser

import "testing"

func TestStandaloneTryParsing(t *testing.T) {
	for _, body := range []string{"try operation()", "if true: try operation()", "try object.operation()"} {
		source := "fn f() Result[Unit, String]:\n    " + body + "\n    return ok(unit)\n"
		if _, err := Parse("try.ms", source); err != nil {
			t.Fatal(err)
		}
		if _, issues := ParsePartial("try.ms", source); len(issues) != 0 {
			t.Fatal(issues)
		}
	}
	for _, body := range []string{"try result", "try operation() + 1", "let _ = try operation()"} {
		if _, err := Parse("try.ms", "fn f() Unit:\n    "+body+"\n"); err == nil {
			t.Fatalf("accepted %s", body)
		}
	}
}
