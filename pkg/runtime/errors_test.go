package msruntime

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestPassingAnExistingErrorViewDoesNotAllocate(t *testing.T) {
	cause := Record{"ReadError", map[string]Value{"attempt": int32(1)}}
	original := ViewOf("@std/Error", cause, TypeScope{Module: "first.ms"})
	var result Value
	allocations := testing.AllocsPerRun(100, func() {
		result = ViewOf("@std/Error", original, TypeScope{Module: "second.ms"})
	})
	if allocations != 0 || result.(View).Scope.Module != "first.ms" {
		t.Fatalf("repeated Error boundary allocated or changed dispatch: %v allocations", allocations)
	}
	SetField(ContractReceiver(result), "attempt", int32(2))
	if Field(cause, "attempt") != int32(2) {
		t.Fatal("repeated Error boundary copied the original error")
	}
}

func TestErrorResultRetainsOriginalPayloadStorage(t *testing.T) {
	cause := Record{"ReadError", map[string]Value{"attempt": int32(1)}}
	for _, tag := range []string{"ok", "error"} {
		t.Run(tag, func(t *testing.T) {
			original := Alternative{"@std/Result[ReadError][ReadError]", tag, []Value{cause}}
			result := ErrorResult(original, "@std/Result[ReadError][@std/Error]").(Alternative)
			if result.Type != "@std/Result[ReadError][@std/Error]" || result.Tag != tag || &result.Fields[0] != &original.Fields[0] {
				t.Fatal("Error boundary replaced the result payload storage")
			}
			SetField(result.Fields[0], "attempt", int32(2))
			if Field(cause, "attempt") != int32(2) {
				t.Fatal("Error boundary copied the concrete value")
			}
		})
	}
}

func TestScopedErrorResultDoesNotChangeOriginalResult(t *testing.T) {
	cause := Record{"ReadError", map[string]Value{"attempt": int32(1)}}
	original := Alternative{"@std/Result[Unit][ReadError]", "error", []Value{cause}}
	result := ErrorResult(original, "@std/Result[Unit][@std/Error]", TypeScope{Module: "first.ms"}).(Alternative)
	view, ok := result.Fields[0].(View)
	if !ok || view.Scope.Module != "first.ms" {
		t.Fatal("Error boundary lost scoped dispatch evidence")
	}
	if _, wrapped := original.Fields[0].(View); wrapped {
		t.Fatal("Error boundary changed the original Result")
	}
	SetField(ContractReceiver(view), "attempt", int32(2))
	if Field(cause, "attempt") != int32(2) {
		t.Fatal("scoped Error boundary copied the concrete error")
	}
}

func TestStandardErrorMessages(t *testing.T) {
	for _, tt := range []struct {
		cause Alternative
		want  string
	}{
		{Alternative{"@std/FileSystemError", "NotFound", nil}, "filesystem: file or directory not found"},
		{Alternative{"@std/FileSystemError", "PermissionDenied", nil}, "filesystem: permission denied"},
		{Alternative{"@std/IoError", "Closed", nil}, "I/O: resource is closed"},
		{Alternative{"@std/NetworkError", "Timeout", nil}, "network: operation timed out"},
		{Alternative{"@std/TomlError", "InvalidData", []Value{int32(2), int32(3), "secret-token"}}, "TOML: invalid data at line 2, column 3"},
		{Alternative{"@std/YamlError", "UnsupportedFeature", []Value{int32(4), "secret-token"}}, "YAML: unsupported feature at line 4"},
		{Alternative{"@std/IoError", "Failed", []Value{"device diagnostic"}}, "device diagnostic"},
		{Alternative{"@std/ExecutionError", "Crashed", []Value{int32(1), "task diagnostic"}}, "task diagnostic"},
	} {
		t.Run(tt.cause.Type+"."+tt.cause.Tag, func(t *testing.T) {
			got := Invoke(RootExecution(), StandardImplementation("errors/message", tt.cause), nil)
			if got != tt.want {
				t.Fatalf("message = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestMissingFileErrorMessage(t *testing.T) {
	fs := &libraryFileSystem{directory: t.TempDir()}
	result := fs.Operation("read_file").Body(RootExecution(), []Value{"missing-secret-token", int32(100)}).(Alternative)
	libraryFailure(t, result, "NotFound")
	cause := result.Fields[0].(Alternative)
	if len(cause.Fields) != 0 {
		t.Fatal("changed nullary error constructor")
	}
	got := Invoke(RootExecution(), StandardImplementation("errors/message", cause), nil)
	if got != "filesystem: file or directory not found" {
		t.Fatalf("message = %q", got)
	}
}

// Audit source declarations so new error domains/cases cannot silently fall back
// to a raw case name or the generic unknown-error diagnostic.
func TestAllStandardErrorCasesHaveMessages(t *testing.T) {
	files, err := filepath.Glob("../stdlib/*.ms")
	if err != nil || len(files) == 0 {
		t.Fatalf("standard declarations: %v", err)
	}
	implementations := regexp.MustCompile(`impl Error for (\w+):`)
	nullary := regexp.MustCompile(`(?m)^    case (\w+)$`)
	count := 0
	for _, file := range files {
		data, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		source := string(data)
		for _, implementation := range implementations.FindAllStringSubmatch(source, -1) {
			name := implementation[1]
			count++
			declaration := regexp.MustCompile(`(?m)^export type ` + name + `:\n((?:    [^\n]*\n|\n)+)`).FindStringSubmatch(source)
			if len(declaration) != 2 {
				t.Fatalf("missing declaration for %s", name)
			}
			if standardErrorDomains["@std/"+name] == "" {
				t.Errorf("missing diagnostic domain for %s", name)
			}
			for _, variant := range nullary.FindAllStringSubmatch(declaration[1], -1) {
				tag := variant[1]
				if standardErrorReasons[tag] == "" {
					t.Errorf("missing diagnostic for %s.%s", name, tag)
				}
				message := Invoke(RootExecution(), StandardImplementation("errors/message", Alternative{"@std/" + name, tag, nil}), nil).(string)
				if strings.Contains(message, name) || strings.Contains(message, tag) {
					t.Errorf("raw case in %q", message)
				}
			}
		}
	}
	if count == 0 {
		t.Fatal("no standard errors audited")
	}
}
