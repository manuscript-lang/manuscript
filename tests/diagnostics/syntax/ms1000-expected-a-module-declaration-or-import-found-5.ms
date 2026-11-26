// conform: tags=diagnostics
// conform: phase=check
--- a/main.ms
+++ b/main.ms
@@ -1,3 +1,4 @@
 fn add(a: Int, b: Int) Int {
 }
-    return a + b
+    total := a + b
+    return total
// expect-error: MS1000 3:1-3:2 expected a module declaration or import, found '-'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 4:1-4:2 expected a module declaration or import, found '+'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 5:1-5:2 unexpected source character '@'; this character is not part of Manuscript's syntax outside text
// expect-error: MS1000 8:1-8:2 expected a module declaration or import, found '-'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 9:1-9:2 expected a module declaration or import, found '+'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 10:1-10:2 expected a module declaration or import, found '+'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
