package stdlib_test

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/internal/nativeabi"
	"github.com/manuscript-lang/manuscript/pkg/parser"
	"github.com/manuscript-lang/manuscript/pkg/stdlib"
	"github.com/manuscript-lang/manuscript/pkg/syntax"
)

// This is the approved migration boundary, not a rule that every observational
// method should become an accessor. Signatures remain owned by the .ms sources;
// the expectations protect their public result types and operation categories.
func TestApprovedAccessorInventory(t *testing.T) {
	modules := accessorModules(t)
	expected := map[string]string{}
	for _, receiver := range []struct {
		file, name string
		results    map[string]string
	}{
		{"collections.ms", "List", map[string]string{"length": "Int", "is_empty": "Bool", "first": "Optional[T]", "last": "Optional[T]"}},
		{"collections.ms", "Map", map[string]string{"length": "Int", "is_empty": "Bool"}},
		{"collections.ms", "Set", map[string]string{"length": "Int", "is_empty": "Bool"}},
		{"bytes.ms", "Bytes", map[string]string{"length": "Int", "is_empty": "Bool"}},
		{"intrinsics.ms", "StringOperations", map[string]string{"byte_length": "Int", "is_empty": "Bool", "length": "Int", "scalar_length": "Int"}},
		{"intrinsics.ms", "FloatOperations", map[string]string{"is_nan": "Bool", "is_finite": "Bool"}},
		{"intrinsics.ms", "IntOperations", map[string]string{"milliseconds": "Duration", "seconds": "Duration", "minutes": "Duration"}},
		{"optional.ms", "Optional", map[string]string{"is_some": "Bool", "is_none": "Bool"}},
		{"result.ms", "Result", map[string]string{"is_ok": "Bool", "is_error": "Bool"}},
		{"queues.ms", "Queue", map[string]string{"length": "Int", "is_empty": "Bool", "peek": "Optional[T]"}},
		{"queues.ms", "PriorityQueue", map[string]string{"length": "Int", "is_empty": "Bool", "peek": "Optional[T]"}},
		{"time.ms", "Timestamp", map[string]string{"unix_seconds": "Int", "nanoseconds": "Int"}},
		{"time.ms", "Duration", map[string]string{"nanoseconds": "Int", "microseconds": "Int", "milliseconds": "Int", "seconds": "Float", "minutes": "Float", "hours": "Float"}},
		{"http.ms", "HttpExchange", map[string]string{"headers": "HttpHeaders", "method": "HttpMethod", "path": "String", "query": "String"}},
		{"http.ms", "ResponseBody", map[string]string{"metadata": "HttpResponseMetadata"}},
		{"http.ms", "ClientResponse", map[string]string{"metadata": "HttpResponseMetadata"}},
		{"fs.ms", "Directory", map[string]string{"path": "String"}},
		{"fs.ms", "TemporaryDirectory", map[string]string{"path": "String"}},
		{"path.ms", "PathOperations", map[string]string{"separator": "String", "delimiter": "String"}},
		{"websocket.ms", "WebSocket", map[string]string{"subprotocol": "String"}},
		{"log.ms", "Logger", map[string]string{"level": "LogLevel"}},
		{"net.ms", "IpAddress", map[string]string{"family": "IpFamily"}},
		{"net.ms", "DnsKind", map[string]string{"text": "String"}},
		{"net.ms", "IpFamily", map[string]string{"text": "String"}},
		{"http.ms", "HttpMethod", map[string]string{"text": "String"}},
		{"net.ms", "Connection", map[string]string{"local_address": "String", "peer_address": "String"}},
		{"net.ms", "Listener", map[string]string{"address": "String"}},
		{"net.ms", "DatagramSocket", map[string]string{"address": "String"}},
		{"http.ms", "HttpServer", map[string]string{"address": "String"}},
		{"sync.ms", "SynchronizedGuard", map[string]string{"value": "T"}},
	} {
		for name, result := range receiver.results {
			expected[receiver.file+"/"+receiver.name+"."+name] = result
		}
	}
	if len(expected) != 59 {
		t.Fatalf("test inventory has %d entries; want the approved 56 migrations and 3 existing Int accessors", len(expected))
	}

	seen := map[string]bool{}
	native := map[string]bool{}
	for file, module := range modules {
		for _, receiver := range module.Declarations {
			if receiver.Accessor {
				t.Errorf("module declaration %s/%s is an accessor", file, receiver.Name)
			}
			for _, member := range receiver.Methods {
				owner := receiver.Name
				if receiver.Kind == syntax.KindImpl {
					owner = "impl " + receiver.Contract.Name + " for " + receiver.Receiver.Name
				}
				key := file + "/" + owner + "." + member.Name
				if receiver.Kind != syntax.KindImpl && nativeabi.IsAccessor(accessorNativeReceiver(owner), member.Name) != member.Accessor {
					t.Errorf("%s: source accessor=%t differs from native ABI category", key, member.Accessor)
				}
				if !member.Accessor {
					continue
				}
				if seen[key] {
					t.Errorf("duplicate accessor %s", key)
				}
				seen[key] = true
				want, approved := expected[key]
				if !approved {
					t.Errorf("accessor outside approved inventory: %s", key)
					continue
				}
				if member.Kind != syntax.KindFn || member.Constant || len(member.Params) != 0 || len(member.TypeParams) != 0 {
					t.Errorf("%s must be a zero-parameter accessor without its own type parameters: %+v", key, member)
				}
				if got := accessorResult(member.Result); got != want {
					t.Errorf("%s result = %s; want %s", key, got, want)
				}
				native[accessorNativeReceiver(owner)+"."+member.Name] = true
			}
		}
	}
	for key := range expected {
		if !seen[key] {
			t.Errorf("missing approved accessor %s", key)
		}
	}
	if len(seen) != len(expected) {
		t.Errorf("found %d accessors; want exactly %d", len(seen), len(expected))
	}
	metadataCount := 0
	for receiver, members := range nativeabi.ReceiverAccessors {
		for name, enabled := range members {
			metadataCount++
			if !enabled || !native[receiver+"."+name] {
				t.Errorf("native accessor category %s.%s has no matching approved source accessor", receiver, name)
			}
		}
	}
	if metadataCount != len(expected) {
		t.Errorf("native accessor categories = %d; want %d", metadataCount, len(expected))
	}
}

func TestErrorMessageRemainsMethodInEveryStandardImplementation(t *testing.T) {
	modules := accessorModules(t)
	implementations := 0
	interfaceFound := false
	sourceOwned := map[string]bool{"sse.ms": false, "toml.ms": false, "yaml.ms": false}
	for file, module := range modules {
		for _, declaration := range module.Declarations {
			isError := file == "errors.ms" && declaration.Kind == syntax.KindInterface && declaration.Name == "Error"
			isImplementation := declaration.Kind == syntax.KindImpl && declaration.Contract.Name == "Error"
			if !isError && !isImplementation {
				continue
			}
			owner := "Error"
			if isError {
				interfaceFound = true
			} else {
				owner = declaration.Receiver.Name
				implementations++
				if _, tracked := sourceOwned[file]; tracked {
					sourceOwned[file] = true
				}
			}
			message := accessorOperation(t, file, declaration, "message")
			if message.Accessor || message.Kind != syntax.KindFn || message.Constant || len(message.Params) != 0 || len(message.TypeParams) != 0 || accessorResult(message.Result) != "String" {
				t.Errorf("%s/%s.message must remain a fn() -> String method: %+v", file, owner, message)
			}
			if nativeabi.IsAccessor(owner, "message") {
				t.Errorf("%s.message is registered as a native accessor", owner)
			}
		}
	}
	if !interfaceFound || implementations == 0 {
		t.Fatalf("failed to discover Error interface and implementations: interface=%t, implementations=%d", interfaceFound, implementations)
	}
	for file, found := range sourceOwned {
		if !found {
			t.Errorf("did not inspect source-owned Error implementation in %s", file)
		}
	}
	t.Logf("checked Error.message and all %d discovered standard implementations", implementations)
}

func TestAccessorMigrationRetainsMethodsAndRemovesOldAliases(t *testing.T) {
	modules := accessorModules(t)
	for _, control := range []struct{ file, receiver, methods string }{
		{"queues.ms", "BlockingQueue", "length is_closed put take close"},
		{"queues.ms", "Queue", "enqueue dequeue"},
		{"queues.ms", "PriorityQueue", "enqueue dequeue"},
		{"collections.ms", "List", "append set pop clone keys entries join reversed sorted"},
		{"collections.ms", "Map", "get add clone keys values entries"},
		{"collections.ms", "Set", "add clone values entries"},
		{"collections.ms", "ListBuilder", "freeze"},
		{"collections.ms", "MapBuilder", "freeze"},
		{"collections.ms", "SetBuilder", "freeze"},
		{"bytes.ms", "Bytes", "clone values to_text"},
		{"bytes.ms", "BytesBuilder", "freeze"},
		{"string.ms", "StringBuilder", "freeze"},
		{"optional.ms", "Optional", "unwrap unwrap_or unwrap_or_else"},
		{"result.ms", "Result", "unwrap unwrap_error to_optional"},
		{"intrinsics.ms", "ValueOperations", "toString"},
		{"intrinsics.ms", "CloneOperations", "clone"},
		{"intrinsics.ms", "StringOperations", "chars scalar_values to_bytes parse_int"},
		{"intrinsics.ms", "IntOperations", "to_string to_float to_decimal"},
		{"intrinsics.ms", "FloatOperations", "to_string to_precision truncate_to_int"},
		{"sync.ms", "Synchronized", "lock"},
		{"sync.ms", "SynchronizedGuard", "set wait notify_all close"},
		{"time.ms", "Timestamp", "to_string"},
		{"time.ms", "Clock", "now"},
		{"time.ms", "WallClock", "now"},
		{"net.ms", "IpAddress", "text"},
		{"net.ms", "Cidr", "text"},
		{"net.ms", "Connection", "read write close"},
		{"http.ms", "HttpHeaders", "values names text clone"},
		{"http.ms", "HttpExchange", "read write close"},
		{"http.ms", "ResponseBody", "read close"},
		{"fs.ms", "Directory", "read close"},
		{"path.ms", "PathOperations", "parse format join"},
	} {
		receiver := accessorDeclaration(t, modules[control.file], control.receiver)
		for _, name := range strings.Fields(control.methods) {
			member := accessorOperation(t, control.file, receiver, name)
			if member.Accessor || member.Kind != syntax.KindFn || nativeabi.IsAccessor(accessorNativeReceiver(control.receiver), name) {
				t.Errorf("%s/%s.%s must remain a method", control.file, control.receiver, name)
			}
		}
	}
	for _, name := range []string{"separator", "delimiter"} {
		function := accessorDeclaration(t, modules["path.ms"], name)
		if function.Kind != syntax.KindFn || function.Accessor {
			t.Errorf("path.%s must remain a module function", name)
		}
	}
	for _, removed := range []struct{ file, receiver, methods string }{
		{"time.ms", "Duration", "to_nanoseconds to_microseconds to_milliseconds to_seconds to_minutes to_hours"},
		{"sync.ms", "SynchronizedGuard", "get"},
	} {
		receiver := accessorDeclaration(t, modules[removed.file], removed.receiver)
		for _, member := range receiver.Methods {
			for _, name := range strings.Fields(removed.methods) {
				if member.Name == name {
					t.Errorf("retired public alias remains: %s/%s.%s", removed.file, removed.receiver, name)
				}
			}
		}
	}
}

func accessorModules(t *testing.T) map[string]*syntax.Module {
	t.Helper()
	files, err := stdlib.Sources.ReadDir(".")
	if err != nil {
		t.Fatal(err)
	}
	modules := map[string]*syntax.Module{}
	for _, file := range files {
		if filepath.Ext(file.Name()) != ".ms" {
			continue
		}
		text, err := stdlib.Sources.ReadFile(file.Name())
		if err != nil {
			t.Fatal(err)
		}
		module, err := parser.Parse("@std/"+file.Name(), string(text))
		if err != nil {
			t.Fatal(err)
		}
		modules[file.Name()] = module
	}
	if len(modules) != 46 {
		t.Fatalf("parsed %d pinned standard modules; want the audited 46 (including testing.ms)", len(modules))
	}
	return modules
}

func accessorNativeReceiver(name string) string {
	switch name {
	case "StringOperations", "IntOperations", "FloatOperations":
		return strings.TrimSuffix(name, "Operations")
	default:
		return name
	}
}

func accessorResult(result *syntax.Type) string {
	if result == nil {
		return "<missing>"
	}
	name := result.Name
	if len(result.Args) != 0 {
		args := make([]string, len(result.Args))
		for index, argument := range result.Args {
			args[index] = accessorResult(argument)
		}
		name += "[" + strings.Join(args, ", ") + "]"
	}
	return name
}

func accessorDeclaration(t *testing.T, module *syntax.Module, name string) *syntax.Declaration {
	t.Helper()
	for _, declaration := range module.Declarations {
		if declaration.Kind != syntax.KindImpl && declaration.Name == name {
			return declaration
		}
	}
	t.Fatalf("missing declaration %s in %s", name, module.File)
	return nil
}

func accessorOperation(t *testing.T, file string, receiver *syntax.Declaration, name string) *syntax.Declaration {
	t.Helper()
	var found *syntax.Declaration
	for _, member := range receiver.Methods {
		if member.Name != name {
			continue
		}
		if found != nil {
			t.Fatalf("duplicate operation %s/%s.%s", file, receiver.Name, name)
		}
		found = member
	}
	if found == nil {
		t.Fatalf("missing operation %s/%s.%s", file, receiver.Name, name)
	}
	return found
}
