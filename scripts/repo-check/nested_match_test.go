package main

import (
	"strconv"
	"strings"
	"testing"
)

func TestNestedMatchSourceGate(t *testing.T) {
	// manuscript:allow-nested-match fixture exercises detection across source storage formats
	const nested = "fn use(value: Optional[Int]) -> Unit:\n    match value:\n        some(_):\n            match value:\n                some(_): unit\n                none: unit\n        none: unit\n"
	goSource := "package sample\nvar source = " + strconv.Quote(nested) + "\n"
	for _, tc := range []struct {
		name, path, source string
		want               int
	}{
		{"module", "examples/main.ms", nested, 1},
		{"fragment", "guide.md", "```manuscript\n" + strings.TrimPrefix(nested, "fn use(value: Optional[Int]) -> Unit:\n") + "```\n", 1},
		{"text fence", "guide.md", "```text\n" + nested + "```\n", 1},
		{"markdown CRLF", "guide.md", strings.ReplaceAll("```manuscript\n"+nested+"```\n", "\n", "\r\n"), 1},
		{"interpreted Go string", "sample_test.go", goSource, 1},
		{"raw Go string", "sample_test.go", "package sample\nvar source = `" + nested + "`\n", 1},
		{"split literal", "sample_test.go", "package sample\nvar source = " + strconv.Quote(nested[:75]) + " + " + strconv.Quote(nested[75:]) + "\n", 1},
		{"literal allowance", "sample_test.go", strings.Replace(goSource, "var source", "// "+nestedMatchAllowance+"advisory regression\nvar source", 1), 0},
		{"allowance cannot hide next literal", "sample_test.go", strings.Replace(goSource, "var source", "// "+nestedMatchAllowance+"advisory regression\nvar source", 1) + "var other = " + strconv.Quote(nested) + "\n", 1},
		{"non-test cannot opt out", "sample.go", strings.Replace(goSource, "var source", "// "+nestedMatchAllowance+"bad excuse\nvar source", 1), 1},
		{"fixture allowance", "tests/accept.ms", strings.Replace(nested, "            match", "            # "+nestedMatchAllowance+"lowering regression\n            match", 1), 0},
		{"ordinary source cannot opt out", "examples/main.ms", strings.Replace(nested, "            match", "            # "+nestedMatchAllowance+"bad excuse\n            match", 1), 1},
		{"empty reason", "tests/accept.ms", strings.Replace(nested, "            match", "            # "+nestedMatchAllowance+"\n            match", 1), 1},
		{"words are not syntax", "examples/main.ms", "# match match\nfn use() -> String: \"match match\"\n", 0},
		{"incomplete neighbor", "examples/main.ms", "fn broken(\n" + nested, 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			issues, err := nestedMatchIssues(tc.path, tc.source)
			if err != nil || len(issues) != tc.want {
				t.Fatalf("got %v, %v; want %d issues", issues, err, tc.want)
			}
			for _, issue := range issues {
				if !strings.HasPrefix(issue, tc.path+":") || !strings.Contains(issue, "helper") {
					t.Fatal(issue)
				}
			}
		})
	}
}
