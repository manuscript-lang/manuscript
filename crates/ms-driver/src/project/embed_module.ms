import Bytes from "@std/bytes.ms"
import embedded_tree, EmbeddedTree, msstd_embed_bytes from "@std/os/tree.ms"
// Generated from an [embed] table of ms.toml; edit the files in the directory, not this module.
// The compiler places the bytes of each file in the program's read-only data; making the tree costs one map
// entry per file, and a read copies only the file asked for.
