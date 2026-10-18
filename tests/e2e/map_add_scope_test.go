package e2e_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/pkg/compiler"
)

func TestMapAddKeepsLexicalHashScope(t *testing.T) {
	root := t.TempDir()
	sources := map[string]string{
		"domain.ms": `export type Key:
    code: Float
`,
		"helper.ms": `export fn insert[K: Hashable,V](m: Map[K,V], key: K, value: V) Map[K,V]:
    return m.add(key,value)
export fn insert_bound[K: Hashable,V](m: Map[K,V], key: K, value: V) Map[K,V]:
    let add=m.add
    return add(value: value, key: key)
`,
		"main.ms": `import first from "./first.ms"
import second from "./second.ms"
import panic from "@std/faults.ms"
test "map add generic and bound calls retain lexical key evidence":
    if first()!=2: return panic("first scope")
    if second()!=3: return panic("second scope")
`,
	}
	for _, name := range []string{"first", "second"} {
		comparison := "(self.code == other.code or self.code == -other.code)"
		hash := "0"
		if name == "second" {
			comparison = "self.code == other.code"
			hash = "0"
		}
		sources[name+".ms"] = `import Key from "./domain.ms"
import {insert,insert_bound} from "./helper.ms"
import panic from "@std/faults.ms"
impl Equal for Key:
    fn equals(other: Equal) Bool:
        match other:
            Key(other): return ` + comparison + `
            _: return false
impl Hashable for Key:
    fn hash() Int: ` + hash + `
export fn ` + name + `() Int:
    let m=Map[Key,Int]()
    let original=Key(1.0)
    m.add(original,1)
    insert(m,Key(-1.0),2)
    insert_bound(m,Key(1.0),3)
    let add=m.add
    add(value: 4, key: Key(2.0))
    if m.get(Key(1.0)).unwrap()!=3: return panic("replacement")
    original.code=9.0
    if m.keys()[0].unwrap().code!=9.0: return panic("original key identity")
    return m.length()
`
	}
	for name, source := range sources {
		if err := os.WriteFile(filepath.Join(root, name), []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	r := compiler.CompileFile(filepath.Join(root, "main.ms"), compiler.Options{Tests: true})
	data, err := execute(t, r)
	if err != nil || !strings.Contains(string(data), "0 failed") {
		t.Fatalf("%v\n%s", err, data)
	}
	// Merely loading both implementation modules must not select either contract
	// for a raw key use in the importing module.
	raw := sources["main.ms"] + `import Key from "./domain.ms"
fn invalid() Unit:
    let m=Map[Key,Int]()
    m.add(Key(-1.0),1)
`
	if err := os.WriteFile(filepath.Join(root, "main.ms"), []byte(raw), 0600); err != nil {
		t.Fatal(err)
	}
	r = compiler.CompileFile(filepath.Join(root, "main.ms"), compiler.Options{AnalyzeOnly: true})
	if r.Success() {
		t.Fatal("local Hashable implementation leaked")
	}
}
