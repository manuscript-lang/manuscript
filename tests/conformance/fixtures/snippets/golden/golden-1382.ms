// conform: tags=diagnostics
// conform: phase=check
import panic from "@std/faults.ms"
import filesystem from "@std/os/fs.ms"
export fn other() Int: return 4
test "source":
    if other() != 4: return panic("bad other")
    if data := filesystem().read_file(path: "fixture.txt", max_bytes: 1024):
        if data.length() != 7: return panic("wrong fixture size")
    else:
        return panic("library fixture cwd changed")
