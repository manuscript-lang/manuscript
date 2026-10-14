package main

import (
	"os/exec"
	"strings"
	"testing"
	"testing/fstest"
)

func TestRequiredWorkflowTriggers(t *testing.T) {
	for _, test := range []struct {
		name, events string
		valid        bool
	}{
		{"unfiltered", "  pull_request:\n  merge_group:\n    types: [checks_requested]\n", true},
		{"missing PR", "  merge_group:\n    types: [checks_requested]\n", false},
		{"missing queue", "  pull_request:\n", false},
		{"paths", "  pull_request:\n    paths: ['**/*.go']\n  merge_group:\n    types: [checks_requested]\n", false},
		{"ignored paths", "  pull_request:\n    paths-ignore: ['documentation/**']\n  merge_group:\n    types: [checks_requested]\n", false},
		{"queue activity", "  pull_request:\n  merge_group:\n    types: [destroyed]\n", false},
		{"malformed", "  pull_request: [\n", false},
	} {
		t.Run(test.name, func(t *testing.T) {
			err := checkWorkflowTriggers([]byte("on:\n" + test.events))
			if (err == nil) != test.valid {
				t.Fatalf("valid=%v, got %v", test.valid, err)
			}
		})
	}
}

func TestStandardSyntaxGate(t *testing.T) {
	valid := fstest.MapFS{
		"process.ms":    {Data: []byte("export fn commands() -> Commands:\n")},
		"data.ms":       {Data: []byte("type Data:\n    count: Int = 3\n    fn read() -> Int:\n")},
		"bindings.json": {Data: []byte("not Manuscript source")},
	}
	if err := checkStandardSyntax(valid, "pkg/stdlib"); err != nil {
		t.Fatal("rejected valid declarations", err)
	}
	for name, source := range map[string]string{
		"function": "export fn commands() -> Commands\n",
		"receiver": "type Data:\n    fn read() -> Int\n",
		"schema":   "type Data:\n    count Int\n",
		"default":  "type Data:\n    count: Int =\n",
		"trailing": "fn valid() -> Unit:\nvar invalid = 3\n",
	} {
		t.Run(name, func(t *testing.T) {
			files := fstest.MapFS{"broken.ms": {Data: []byte(source)}}
			err := checkStandardSyntax(files, "pkg/stdlib")
			if err == nil || !strings.Contains(err.Error(), "invalid standard-library syntax") || !strings.Contains(err.Error(), "broken.ms:") || !strings.Contains(err.Error(), "parse:") {
				t.Fatalf("missing positioned syntax error: %v", err)
			}
		})
	}
}

func TestBoundaryRejectsHostRuntimeInFrontend(t *testing.T) {
	rules := policy{Dependencies: map[string][]string{"pkg/checker": {"pkg/syntax"}, "pkg/syntax": {}}}
	packages := map[string]pkg{"pkg/checker": {Imports: []string{module + "/pkg/syntax", module + "/pkg/runtime"}}, "pkg/syntax": {}}
	issues := dependencyIssues(rules, packages)
	if len(issues) != 1 || !strings.Contains(issues[0], "pkg/checker imports forbidden package pkg/runtime") {
		t.Fatal(issues)
	}
	packages["pkg/checker"] = pkg{Imports: []string{module + "/pkg/syntax"}}
	if issues := dependencyIssues(rules, packages); len(issues) != 0 {
		t.Fatal(issues)
	}
}

func TestMissingNodeCannotSilentlyReachLowering(t *testing.T) {
	t.Chdir("../..")
	missing, err := missingKinds("pkg/lower/lower_expressions.go", "expressionValue", []string{"lambda", "future-node"})
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
		"build":    {"run ./scripts/mktoolchain", "-tags exp.winarm64"},
		"race":     {"test -race"}, "fuzz": {"test ./pkg/build -list '^FuzzCompile$'", "test ./pkg/build -run '^$' -fuzz '^FuzzCompile$'"}, "e2e": {"test  ./tests/e2e"},
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
