// conform: tags=lists,maps,mutation,records,tier-core
// conform: phase=run
// conform: origin=perf thread: in-place field updates and name-indexed element updates
import stdout from "@std/io/io.ms"

type Reader:
    entries List[Map[String, Int]]
    names List[String]
    depth Int

type Holder:
    reader Reader

fn put(var reader Reader, id Int, key String, value Int) Void:
    reader.entries[id].add(key.clone(), value)

fn grow(var holder Holder, name String) Void:
    holder.reader.names.append(name.clone())
    holder.reader.entries.append(Map[String, Int]())

fn put_list(var maps List[Map[String, Int]], id Int) Void:
    maps[id].add("k", 1)

fn main() Void:
    var reader = Reader(
        entries: [Map[String, Int](), Map[String, Int]()], names: ["a", "b"], depth: 0
    )
    put(reader, 1, "x", 5)
    put(reader, 1, "y", 6)

    var id = 0
    reader.entries[id].add("z", 7)

    var holder = Holder(reader: reader.clone())
    grow(holder, "c")
    holder.reader.entries[2].add("w", 8)

    var maps = [Map[String, Int](), Map[String, Int]()]
    put_list(maps, 1)

    var total = 0

    for i in 0..20000:
        reader.names.append("n")
        total += 1

    void stdout().write(
        f"{reader.entries[0].length()} {reader.entries[1].length()} {reader.names.length()} {total}\n"
    )
    void stdout().write(
        f"{holder.reader.names.length()} {holder.reader.entries.length()} {holder.reader.entries[2].length()} {reader.entries.length()}\n"
    )
    void stdout().write(f"{maps[1].length()} {maps[0].length()}\n")
