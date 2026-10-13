package msruntime

import (
	"context"
	"testing"
)

func TestErrorCategoryPreservesDomainValues(t *testing.T) {
	for _, test := range []struct {
		typ, tag, want string
		fields         []Value
	}{
		{"FileSystemError", "NotFound", "NotFound", nil},
		{"SystemError", "PermissionDenied", "PermissionDenied", nil},
		{"ProcessError", "InvalidInput", "InvalidInput", nil},
		{"JsonError", "InvalidData", "InvalidData", nil},
		{"IoError", "Unavailable", "Unavailable", nil},
		{"CompressionError", "LimitExceeded", "LimitExceeded", nil},
		{"FileSystemError", "AlreadyExists", "AlreadyExists", nil},
		{"CryptoError", "Unsupported", "Unsupported", nil},
		{"IoError", "Closed", "Closed", nil},
		{"NetworkError", "Timeout", "Timeout", nil},
		{"HttpError", "Timeout", "Timeout", nil},
		{"CommandError", "TimedOut", "Timeout", nil},
		{"ExecutionError", "TimedOut", "Timeout", nil},
		{"YamlError", "InvalidData", "InvalidData", []Value{int32(3), int32(9), "detail"}},
		{"IoError", "Failed", "", []Value{"not found; operation timed out"}},
		{"NumberError", "OutOfRange", "", nil},
		{"CommandError", "OutputLimit", "", nil},
		{"StartError", "Full", "", nil},
		{"CryptoError", "AuthenticationFailed", "", nil},
		{"ExecutionError", "Cancelled", "", nil},
		{"LogError", "Io", "", []Value{Alternative{Type: "@std/IoError", Tag: "Closed"}}},
	} {
		t.Run(test.typ+"/"+test.tag, func(t *testing.T) {
			cause := Alternative{Type: "@std/" + test.typ, Tag: test.tag, Fields: test.fields}
			original := Clone(cause)
			view := ViewOf("@std/Error", cause)
			spec := libraryFunctions["errors/category"]
			result := spec.Body(RootExecution(), "@std/Optional[@std/ErrorCategory]", []Value{view}).(Alternative)
			if test.want == "" && result.Tag != "none" {
				t.Fatalf("domain-specific case inferred: %#v", result)
			}
			if test.want != "" {
				if result.Tag != "some" {
					t.Fatalf("category missing: %#v", result)
				}
				kind := result.Fields[0].(Alternative)
				if kind.Type != "@std/ErrorCategory" || kind.Tag != test.want {
					t.Fatalf("category = %#v", kind)
				}
			}
			if !Equal(cause, original) {
				t.Fatal("classification changed the original error")
			}
		})
	}
	for _, value := range []Value{
		Alternative{Type: "local/FileSystemError", Tag: "NotFound"},
		Alternative{Type: librarySourceErrorType("local/yaml.ms", "YamlError"), Tag: "InvalidData"},
		Record{Type: "local/CustomError", Fields: map[string]Value{"message": "filesystem: file or directory not found"}},
	} {
		if got := libraryErrorCategory(ViewOf("@std/Error", value)).(Alternative); got.Tag != "none" {
			t.Fatalf("custom error classified by name/message: %#v", got)
		}
	}
	for _, name := range []string{"YamlError", "TomlError"} {
		module := "@std/yaml.ms"
		if name == "TomlError" {
			module = "@std/toml.ms"
		}
		cause := Alternative{Type: librarySourceErrorType(module, name), Tag: "InvalidData", Fields: []Value{int32(3), int32(9), "detail"}}
		original := Clone(cause)
		got := libraryErrorCategory(ViewOf("@std/Error", cause)).(Alternative)
		if got.Tag != "some" || got.Fields[0].(Alternative).Tag != "InvalidData" || !Equal(cause, original) {
			t.Fatalf("source standard error changed or unclassified: %#v / %#v", cause, got)
		}
	}
}

func TestErrorCategoryCancellation(t *testing.T) {
	ctx := RootExecution()
	lifetime, cancel := context.WithCancel(ctx.Context)
	cancel()
	ctx.Context = lifetime
	failure := recovered(func() {
		libraryFunctions["errors/category"].Body(ctx, "@std/Optional[@std/ErrorCategory]", []Value{ViewOf("@std/Error", Alternative{Type: "@std/FileSystemError", Tag: "NotFound"})})
	})
	if _, ok := failure.(cancelled); !ok {
		t.Fatalf("cancelled query continued: %v", failure)
	}
}
