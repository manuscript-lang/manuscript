import EmbeddedTree from "@std/os/tree.ms"

# Generated from an [embed] table of ms.toml; edit the files in the directory, not this module.
# Making the tree costs one map entry per file; a file is decoded only when it is read.
export fn files() EmbeddedTree:
    var encoded = Map[String, String]()
    var directories = Set[String]()
    directories.add("")
