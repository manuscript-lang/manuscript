package main

import (
	"strings"
	"testing"
)

func TestBoundaryRejectsHostRuntimeInFrontend(t *testing.T) {
	rules := policy{Dependencies: map[string][]string{"checker": {"syntax"}, "syntax": {}}}
	packages := map[string]pkg{"checker": {Imports: []string{module + "/syntax", module + "/runtime"}}, "syntax": {}}
	issues := dependencyIssues(rules, packages)
	if len(issues) != 1 || !strings.Contains(issues[0], "checker imports forbidden package runtime") {
		t.Fatal(issues)
	}
	packages["checker"] = pkg{Imports: []string{module + "/syntax"}}
	if issues := dependencyIssues(rules, packages); len(issues) != 0 {
		t.Fatal(issues)
	}
}

func TestMissingNodeCannotSilentlyReachLowering(t *testing.T) {
	t.Chdir("../..")
	missing, err := missingKinds("compiler/generate.go", "expression", []string{"lambda", "future-node"})
	if err != nil || len(missing) != 1 || missing[0] != "future-node" {
		t.Fatal(missing, err)
	}
}
