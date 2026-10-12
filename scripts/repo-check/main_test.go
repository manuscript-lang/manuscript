package main

import (
	"os/exec"
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

func TestVerificationTargetsExecuteTheirContracts(t *testing.T) {
	if _, err := exec.LookPath("make"); err != nil {
		t.Skip("developer workflow requires Make")
	}
	t.Chdir("../..")
	for target, expected := range map[string][]string{
		"verify":   {"vet ./...", "staticcheck ./...", "run ./scripts/repo-check\n", "test ./tests/examples", "maintenance licenses -check"},
		"coverage": {"test -covermode=atomic", "-coverprofile=", "tool cover -html"},
		"build":    {"run ./scripts/mktoolchain", "-tags bundled_toolchain"},
		"race":     {"test -race"}, "fuzz": {"-fuzz '^FuzzCompile$'"}, "e2e": {"test  ./tests/e2e"},
	} {
		t.Run(target, func(t *testing.T) {
			output, err := exec.Command("make", "--dry-run", target).CombinedOutput()
			if err != nil {
				t.Fatal(err, string(output))
			}
			for _, fragment := range expected {
				if !strings.Contains(string(output), fragment) {
					t.Fatalf("%s lost %q:\n%s", target, fragment, output)
				}
			}
		})
	}
}
