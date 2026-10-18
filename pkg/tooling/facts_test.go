package tooling

import "testing"

func TestErrorTypeUsesSourceFunctionSyntax(t *testing.T) {
	for _, tc := range []struct{ signature, want string }{
		{"fn() Result[Int, String]", "String"},
		{"fn(callback: fn() Int) Result[Int, String]", "String"},
		{"fn(callback: fn() Result[Int, Error]) Result[Int, String]", "String"},
		{"fn() Result[fn(value: Int) Int, Map[String, List[Int]]]", "Map[String, List[Int]]"},
		{"fn(callback: fn() Result[Int, Error]) Int", ""},
		{"fn() fn() Result[Int, Error]", ""},
		{"Result[Int, String]", ""},
	} {
		if got := errorType(tc.signature); got != tc.want {
			t.Errorf("errorType(%q) = %q, want %q", tc.signature, got, tc.want)
		}
	}
}
