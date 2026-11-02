import MemoryTree, memory_tree from "@std/os/tree.ms"
import base64_decode from "@std/data/encoding.ms"

# Generated from an [embed] table of ms.toml; edit the files in the directory, not this module.
# Each call decodes the files into a new tree, so bind the result once.
export fn files() MemoryTree:
    var tree = memory_tree()
