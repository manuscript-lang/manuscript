// conform: tags=diagnostics
// conform: phase=check
--- a/gone.ms
+++ /dev/null
@@ -1,2 +0,0 @@
-fn a() Int {
}
-    return 0
// expect-error: MS1000 3:1-3:2 expected a module declaration or import, found '-'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 4:1-4:2 expected a module declaration or import, found '+'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 5:1-5:2 unexpected source character '@'; this character is not part of Manuscript's syntax outside text
// expect-error: MS1000 6:1-6:2 expected a module declaration or import, found '-'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
// expect-error: MS1000 8:1-8:2 expected a module declaration or import, found '-'; top level holds only import, constants (NAME := value), fn, type, enum, interface, and test (optionally prefixed by export), so put statements inside a fn
