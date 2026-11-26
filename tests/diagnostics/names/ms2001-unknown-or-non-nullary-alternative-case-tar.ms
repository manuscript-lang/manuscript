// conform: tags=diagnostics
// conform: phase=check
import ArchiveFormat from "@std/io/archive.ms"

fn wrong() Void {
	format := ArchiveFormat.TAR
}
// expect-error: MS2001 6:29 unknown or non-nullary alternative case TAR of ArchiveFormat; cases: Tar, Zip (cases with payloads need call syntax)
