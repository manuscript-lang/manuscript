package tooling

import (
	"strings"
	"testing"
)

const sampleDiff = `diff --git a/src/a.ms b/src/a.ms
index 111..222 100644
--- a/src/a.ms
+++ b/src/a.ms
@@ -1,4 +1,5 @@
 fn one() Int:
-    return 1
+    let x = 1
+    return x
 
 fn two() Int:
diff --git a/new.ms b/new.ms
new file mode 100644
--- /dev/null
+++ b/new.ms
@@ -0,0 +1,2 @@
+fn n() Int:
+    return 0
`

func TestParseDiffAndReverseApply(t *testing.T) {
	files, err := ParseDiff(sampleDiff)
	if err != nil || len(files) != 2 {
		t.Fatalf("%v %v", files, err)
	}
	if files[0].Path() != "src/a.ms" || files[1].Old != "" || files[1].New != "new.ms" {
		t.Fatalf("paths: %+v", files)
	}
	head := "fn one() Int:\n    let x = 1\n    return x\n\nfn two() Int:\n    return 2\n"
	base, err := ReverseApply(head, files[0].Hunks)
	if err != nil || base != "fn one() Int:\n    return 1\n\nfn two() Int:\n    return 2\n" {
		t.Fatalf("base = %q, %v", base, err)
	}
	if got := files[0].TouchedLines(); len(got) != 3 || got[0] != 2 || got[1] != 2 || got[2] != 3 {
		t.Fatalf("touched = %v", got)
	}
	if _, err := ReverseApply(strings.Replace(head, "let x = 1", "let x = 9", 1), files[0].Hunks); err == nil {
		t.Fatal("a diff that does not describe the tree was applied")
	}
}

func TestParseDiffRejectsRenames(t *testing.T) {
	_, err := ParseDiff("diff --git a/a.ms b/b.ms\nsimilarity index 100%\nrename from a.ms\nrename to b.ms\n")
	if err == nil || !strings.Contains(err.Error(), "--no-renames") {
		t.Fatalf("err = %v", err)
	}
}

func TestRemovedContent(t *testing.T) {
	files, err := ParseDiff("--- a/gone.ms\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-fn a() Int:\n-    return 0\n")
	if err != nil || files[0].New != "" {
		t.Fatalf("%v %v", files, err)
	}
	if got := RemovedContent(files[0].Hunks); got != "fn a() Int:\n    return 0\n" {
		t.Fatalf("content = %q", got)
	}
}
