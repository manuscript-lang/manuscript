// conform: tags=diagnostics
// conform: phase=check
diff --git a/src/a.ms b/src/a.ms
index 111..222 100644
--- a/src/a.ms
+++ b/src/a.ms
@@ -1,4 +1,5 @@
 fn one() Int {
 }
-    return 1
+    x := 1
+    return x
 
 fn two() Int {
 }
diff --git a/new.ms b/new.ms
new file mode 100644
--- /dev/null
+++ b/new.ms
@@ -0,0 +1,2 @@
+fn n() Int {
}
+    return 0
// expect-error: MS1000 3:1-3:5 expected a module declaration or import, found name 'diff'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 4:1-4:6 expected a module declaration or import, found name 'index'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 5:1-5:2 expected a module declaration or import, found '-'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 6:1-6:2 expected a module declaration or import, found '+'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 7:1-7:2 unexpected source character '@'; this character is not part of Manuscript's syntax outside text
// expect-error: MS1000 10:1-10:2 expected a module declaration or import, found '-'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 11:1-11:2 expected a module declaration or import, found '+'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 12:1-12:2 expected a module declaration or import, found '+'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 16:1-16:5 expected a module declaration or import, found name 'diff'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 17:1-17:4 expected a module declaration or import, found name 'new'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 18:1-18:2 expected a module declaration or import, found '-'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 19:1-19:2 expected a module declaration or import, found '+'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 20:1-20:2 unexpected source character '@'; this character is not part of Manuscript's syntax outside text
// expect-error: MS1000 21:1-21:2 expected a module declaration or import, found '+'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 23:1-23:2 expected a module declaration or import, found '+'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
