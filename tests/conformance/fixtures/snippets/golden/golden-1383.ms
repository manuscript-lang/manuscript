// conform: tags=diagnostics
// conform: phase=check
import parse, CsvOptions from "@std/data/csv.ms"
import base64_encode, base64_decode from "@std/data/encoding.ms"
import commands from "@std/os/process.ms"
import filesystem from "@std/os/fs.ms"
import compress, decompress, CompressionFormat from "@std/compress.ms"
import panic from "@std/faults.ms"
test "copied native defaults":
    first := CsvOptions()
    first.delimiter = ";"
    if CsvOptions().delimiter != ",": return panic("shared default options")
    if rows := parse("a,b\n"):
        if rows.length() != 1: return panic("default CSV rows")
    else:
        return panic("default CSV parse failed")
    if base64_encode("f".to_bytes()) != "Zg==": return panic("default alphabet")
    if bytes := base64_decode("Zg=="):
        if bytes.decode_utf8().get() != "f": return panic("default decoded bytes")
    else:
        return panic("default Base64 decode failed")
    run := commands().run
    if output := run(program: %q, arguments: ["--version"]):
        if output.exit_code != 0 or output.stdout.length() == 0: return panic("default command output")
    else:
        return panic("default command stdin failed")
    fs := filesystem()
    if fs.create_directory("defaults").is_error(): return panic("default directory creation")
    if fs.write_file("defaults/keep", "first").is_error(): return panic("default exclusive write")
    write := fs.write_file
    if write("defaults/keep", "second").is_ok(): return panic("omitted replacement overwrote file")
    if fs.copy_file("defaults/keep", "defaults/copied").is_error(): return panic("default file copy")
    if fs.copy_tree("defaults", "default-tree").is_error(): return panic("default tree copy")
    if fs.remove("defaults").is_ok(): return panic("omitted recursion removed tree")
    if data := fs.read_file("defaults/keep"):
        if data != "first".to_bytes(): return panic("default changed retained bytes")
    else:
        return panic("default retained file")
    if fs.remove("defaults", recursive: true).is_error(): return panic("explicit recursive removal")
    data := "compression defaults".to_bytes()
    compressed := compress(data, "gzip").get()
    if compressed != compress(data, "gzip", 6).get(): return panic("default compression level")
    encode := CompressionFormat.Gzip.compress
    if encode(data).get() != compressed: return panic("bound default compression level")
    if decompress(compressed, "gzip").get() != data: return panic("default compression round trip")
