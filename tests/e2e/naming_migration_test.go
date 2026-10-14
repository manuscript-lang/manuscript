package e2e_test

import (
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestBuilderPreferredNamesRetainSealedFaults(t *testing.T) {
	source := `import {MapBuilder, SetBuilder} from "@std/collections.ms"
test "map add":
    let builder = MapBuilder[String, Int]()
    let add = builder.add
    let _result = builder.freeze()
    add("a", 1)
test "map legacy":
    let builder = MapBuilder[String, Int]()
    let _result = builder.freeze()
    builder.add("a", 1)
test "set add":
    let builder = SetBuilder[Int]()
    let alias = builder
    let _result = builder.freeze()
    alias.add(1)
test "set legacy":
    let builder = SetBuilder[Int]()
    let _result = builder.freeze()
    builder.add(1)
test "continues":
    let builder = SetBuilder[Int]()
    builder.add(1)
    let _result = builder.freeze()
`
	data, err := execute(t, compiler.CompileSource("builder-names.ms", source, compiler.Options{Tests: true}))
	if err == nil {
		t.Fatalf("missing sealed faults: %s", data)
	}
	output := string(data)
	if strings.Count(output, "builder is sealed") != 4 || !strings.Contains(output, "5 tests, 4 failed") {
		t.Fatal(output)
	}
}
