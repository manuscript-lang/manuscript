// conform: tags=diagnostics
// conform: phase=check
import CompressionFormat, compress from "@std/compress.ms"

fn explicit() Void {
	data := "".to_bytes()
	compress(data, "gzip", 6)
	compress(data, "zlib", 0, max_bytes: null)
	compress(data, "deflate", 9, max_bytes: 100)
	CompressionFormat.Gzip.compress(data, 6)
	CompressionFormat.Zlib.compress(data, 0, max_bytes: null)
	CompressionFormat.Deflate.compress(data, 9, max_bytes: 100)
}
// expect-error: MS2002 3:8-3:25 unknown standard module @std/compress.ms; CompressionFormat is exported by another standard module, so write: import CompressionFormat from "@std/io/archive.ms"
// expect-error: MS2002 3:27-3:35 unknown standard module @std/compress.ms; compress is exported by another standard module, so write: import compress from "@std/io/archive.ms"
// expect-error: MS2001 7:5 unknown binding compress; add: import compress from "@std/io/archive.ms"
// expect-fix: 1:1-1:1 "import compress from \"@std/io/archive.ms\"\n"
// expect-error: MS2001 8:5 unknown binding compress; add: import compress from "@std/io/archive.ms"
// expect-fix: 1:1-1:1 "import compress from \"@std/io/archive.ms\"\n"
// expect-error: MS2001 9:5 unknown binding compress; add: import compress from "@std/io/archive.ms"
// expect-fix: 1:1-1:1 "import compress from \"@std/io/archive.ms\"\n"
// expect-error: MS2001 10:5 unknown binding CompressionFormat; add: import CompressionFormat from "@std/io/archive.ms"
// expect-fix: 1:1-1:1 "import CompressionFormat from \"@std/io/archive.ms\"\n"
// expect-error: MS2001 11:5 unknown binding CompressionFormat; add: import CompressionFormat from "@std/io/archive.ms"
// expect-fix: 1:1-1:1 "import CompressionFormat from \"@std/io/archive.ms\"\n"
// expect-error: MS2001 12:5 unknown binding CompressionFormat; add: import CompressionFormat from "@std/io/archive.ms"
// expect-fix: 1:1-1:1 "import CompressionFormat from \"@std/io/archive.ms\"\n"
