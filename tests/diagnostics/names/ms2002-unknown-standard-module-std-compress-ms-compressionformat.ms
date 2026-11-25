// conform: tags=diagnostics
// conform: phase=check
import CompressionFormat from "@std/compress.ms"

fn wrong() Void {
	format := CompressionFormat.GZip
}
// expect-error: MS2002 3:8-3:25 unknown standard module @std/compress.ms; CompressionFormat is exported by another standard module, so write: import CompressionFormat from "@std/io/archive.ms"
// expect-error: MS2001 6:15 unknown binding CompressionFormat; add: import CompressionFormat from "@std/io/archive.ms"
// expect-fix: 1:1-1:1 "import CompressionFormat from \"@std/io/archive.ms\"\n"
