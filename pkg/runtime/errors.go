package msruntime

import (
	"encoding/hex"
	"fmt"
)

// NativeImplementationSpec describes a source-declared native implementation.
// The checker verifies its method signature alongside native functions.
type NativeImplementationSpec struct {
	Name, Result string
	Params       []LibraryParam
	Build        func(Value) Function
}

var NativeImplementations = []NativeImplementationSpec{
	{"errors/message", "String", nil, func(receiver Value) Function {
		return NewFunction(nil, "String", func(ctx *Execution, _ []Value) Value {
			cause := receiver.(Alternative)
			if cause.Tag == "Failed" && len(cause.Fields) == 1 {
				return cause.Fields[0].(string)
			}
			if cause.Type == "@std/TextError" && cause.Tag == "Text" && len(cause.Fields) == 1 {
				return cause.Fields[0].(string)
			}
			if cause.Tag == "Crashed" && len(cause.Fields) == 2 {
				return cause.Fields[1].(string)
			}
			if cause.Type == "@std/LogError" && (cause.Tag == "Io" || cause.Tag == "FileSystem") {
				return Invoke(ctx, Bind(cause.Fields[0], "@std/Error", "message"), nil)
			}
			return standardErrorMessage(cause)
		})
	}},
}

// Keep diagnostics independent of input values: URLs, data, and host arguments
// can contain secrets. Existing explicit Failed/Crashed messages remain verbatim.
func standardErrorMessage(cause Alternative) string {
	domain := standardErrorDomains[cause.Type]
	if domain == "" {
		domain = "operation"
	}
	reason := standardErrorReasons[cause.Tag]
	if reason == "" {
		reason = "operation failed"
	}
	if cause.Type == "@std/FileSystemError" && cause.Tag == "NotFound" {
		reason = "file or directory not found"
	}
	if (cause.Type == "@std/YamlError" || cause.Type == "@std/TomlError") && cause.Tag == "InvalidData" && len(cause.Fields) == 3 {
		return fmt.Sprintf("%s: %s at line %d, column %d", domain, reason, cause.Fields[0], cause.Fields[1])
	}
	if cause.Type == "@std/YamlError" && cause.Tag == "UnsupportedFeature" && len(cause.Fields) == 2 {
		return fmt.Sprintf("%s: %s at line %d", domain, reason, cause.Fields[0])
	}
	return domain + ": " + reason
}

var standardErrorDomains = map[string]string{
	"@std/ArchiveError":     "archive",
	"@std/BigIntError":      "big integer",
	"@std/BinaryError":      "binary",
	"@std/CollectionError":  "collection",
	"@std/CompressionError": "compression",
	"@std/CryptoError":      "cryptography",
	"@std/CsvError":         "CSV",
	"@std/EncodingError":    "encoding",
	"@std/FileSystemError":  "filesystem",
	"@std/HtmlError":        "HTML",
	"@std/HttpError":        "HTTP",
	"@std/IoError":          "I/O",
	"@std/JsonError":        "JSON",
	"@std/LogError":         "logging",
	"@std/NetworkError":     "network",
	"@std/NumberError":      "number",
	"@std/PathError":        "path",
	"@std/ProcessError":     "process",
	"@std/CommandError":     "command",
	"@std/RandomError":      "random",
	"@std/RegexError":       "regular expression",
	"@std/StringError":      "string",
	"@std/SystemError":      "system",
	"@std/ExecutionError":   "task execution",
	"@std/SseError":         "SSE",
	"@std/StartError":       "scheduler",
	"@std/TextError":        "text",
	"@std/TimeError":        "time",
	"@std/TlsError":         "TLS",
	"@std/TomlError":        "TOML",
	"@std/UrlError":         "URL",
	"@std/WebSocketError":   "WebSocket",
	"@std/YamlError":        "YAML",
}

var standardErrorReasons = map[string]string{
	"InvalidInput":         "invalid input",
	"InvalidData":          "invalid data",
	"LimitExceeded":        "limit exceeded",
	"NotFound":             "not found",
	"AlreadyExists":        "already exists",
	"NotEmpty":             "directory not empty",
	"PermissionDenied":     "permission denied",
	"Unsupported":          "operation not supported",
	"UnsupportedFeature":   "unsupported feature",
	"Closed":               "resource is closed",
	"Unavailable":          "service unavailable",
	"Timeout":              "operation timed out",
	"Truncated":            "stream ended inside an event",
	"Cancelled":            "operation cancelled",
	"Full":                 "capacity exhausted",
	"OutOfRange":           "value out of range",
	"OutputLimit":          "output limit exceeded",
	"AuthenticationFailed": "authentication failed",
}

// StandardRegistration is a checked standard implementation that generated
// programs register as data rather than as one closure each.
type StandardRegistration struct {
	Receiver, Contract, Name, Scope string
	Variables                       []string
	Native                          string
}

func RegisterStandard(entries []StandardRegistration) {
	for _, entry := range entries {
		native := entry.Native
		Register(Implementation{Receiver: entry.Receiver, Contract: entry.Contract, Name: entry.Name, Scope: entry.Scope, Variables: entry.Variables, Build: func(receiver Value, _ map[string]string, _ map[string]TypeScope) Function {
			return StandardImplementation(native, receiver)
		}})
	}
}

func StandardImplementation(name string, receiver Value) Function {
	for _, spec := range NativeImplementations {
		if spec.Name == name {
			return spec.Build(receiver)
		}
	}
	Panic("unavailable standard implementation " + name)
	return Function{}
}

func init() {
	libraryAdd("errors", "category", "Optional[ErrorCategory]", []LibraryParam{{"cause", "Error"}}, func(ctx *Execution, _ string, args []Value) Value {
		CheckCancelled(ctx)
		return libraryErrorCategory(args[0])
	})
}

// Classification reads the concrete standard error without a message call or
// translation. Views retain their original receiver and implementation scope.
func libraryErrorCategory(value Value) Value {
	for {
		view, ok := value.(View)
		if !ok {
			break
		}
		value = view.Receiver
	}
	cause, ok := value.(Alternative)
	if !ok || standardErrorDomains[cause.Type] == "" && !sourceStandardErrors[cause.Type] {
		return optional("@std/ErrorCategory", nil, false)
	}
	name := cause.Tag
	switch name {
	case "InvalidInput", "InvalidData", "LimitExceeded", "NotFound", "AlreadyExists", "PermissionDenied", "Unsupported", "Closed", "Timeout", "Unavailable":
		return optional("@std/ErrorCategory", Alternative{Type: "@std/ErrorCategory", Tag: name}, true)
	}
	return optional("@std/ErrorCategory", nil, false)
}

// Source-defined standard errors have ordinary nominal module identities,
// rather than the native @std/Type identities. Do not match display names.
var sourceStandardErrors = map[string]bool{
	librarySourceErrorType("@std/yaml.ms", "YamlError"): true,
	librarySourceErrorType("@std/toml.ms", "TomlError"): true,
	librarySourceErrorType("@std/sse.ms", "SseError"):   true,
}

func librarySourceErrorType(module, name string) string {
	// This is the existing source identity format in pkg/checker/checker.go.
	// Called native tests cover both standard source errors and local lookalikes.
	return "module/" + hex.EncodeToString([]byte(module)) + "#" + name
}
