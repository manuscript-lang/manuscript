// conform: tags=diagnostics
// conform: phase=check
diff --git a/src/a.ms b/src/a.ms
index 111..222 100644
--- a/src/a.ms
+++ b/src/a.ms
@@ -1,4 +1,5 @@
 fn one() Int:
-    return 1
+    x := 1
+    return x
 
 fn two() Int:
diff --git a/new.ms b/new.ms
new file mode 100644
--- /dev/null
+++ b/new.ms
@@ -0,0 +1,2 @@
+fn n() Int:
+    return 0
