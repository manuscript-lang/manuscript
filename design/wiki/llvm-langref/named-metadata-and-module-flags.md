[Wiki](../index.md) › [LLVM LangRef](index.md)

# Module flags and named metadata

LLVM 23.1.0 Language Reference, part of the [index](index.md). Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html>. License: Apache-2.0 with LLVM exception.

<a id="module-flags-metadata"></a>

## Module Flags Metadata

Information about the module as a whole is difficult to convey to LLVM’s subsystems. The LLVM IR isn’t sufficient to transmit this information. The `llvm.module.flags` named metadata exists in order to facilitate this. These flags are in the form of key / value pairs — much like a dictionary — making it easy for any subsystem that cares about a flag to look it up.

The `llvm.module.flags` metadata contains a list of metadata triplets. Each triplet has the following form:

- The first element is a *behavior* flag, which specifies the behavior when two (or more) modules are merged together, and it encounters two (or more) metadata with the same ID. The supported behaviors are described below.

- The second element is a metadata string that is a unique ID for the metadata. Each module may only have one flag entry for each unique ID (not including entries with the **Require** behavior).

- The third element is the value of the flag.

When two (or more) modules are merged together, the resulting `llvm.module.flags` metadata is the union of the modules’ flags. That is, for each unique metadata ID string, there will be exactly one entry in the merged modules `llvm.module.flags` metadata table, and the value for that entry will be determined by the merge behavior flag, as described below. The only exception is that entries with the *Require* behavior are always preserved.

The following behaviors are supported:

<table class="docutils align-default">
<colgroup>
<col style="width: 10%" />
<col style="width: 90%" />
</colgroup>
<thead>
<tr class="header row-odd">
<th class="head"><p>Value</p></th>
<th class="head"><p>Behavior</p></th>
</tr>
</thead>
<tbody>
<tr class="odd row-even">
<td><p>1</p></td>
<td><dl>
<dt><strong>Error</strong></dt>
<dd>
<p>Emits an error if two values disagree, otherwise the resulting value is that of the operands.</p>
</dd>
</dl></td>
</tr>
<tr class="even row-odd">
<td><p>2</p></td>
<td><dl>
<dt><strong>Warning</strong></dt>
<dd>
<p>Emits a warning if two values disagree. The result value will be the operand for the flag from the first module being linked, unless the other module uses <strong>Min</strong> or <strong>Max</strong>, in which case the result will be <strong>Min</strong> (with the min value) or <strong>Max</strong> (with the max value), respectively.</p>
</dd>
</dl></td>
</tr>
<tr class="odd row-even">
<td><p>3</p></td>
<td><dl>
<dt><strong>Require</strong></dt>
<dd>
<p>Adds a requirement that another module flag be present and have a specified value after linking is performed. The value must be a metadata pair, where the first element of the pair is the ID of the module flag to be restricted, and the second element of the pair is the value the module flag should be restricted to. This behavior can be used to restrict the allowable results (via triggering of an error) of linking IDs with the <strong>Override</strong> behavior.</p>
</dd>
</dl></td>
</tr>
<tr class="even row-odd">
<td><p>4</p></td>
<td><dl>
<dt><strong>Override</strong></dt>
<dd>
<p>Uses the specified value, regardless of the behavior or value of the other module. If both modules specify <strong>Override</strong>, but the values differ, an error will be emitted.</p>
</dd>
</dl></td>
</tr>
<tr class="odd row-even">
<td><p>5</p></td>
<td><dl>
<dt><strong>Append</strong></dt>
<dd>
<p>Appends the two values, which are required to be metadata nodes.</p>
</dd>
</dl></td>
</tr>
<tr class="even row-odd">
<td><p>6</p></td>
<td><dl>
<dt><strong>AppendUnique</strong></dt>
<dd>
<p>Appends the two values, which are required to be metadata nodes. However, duplicate entries in the second list are dropped during the append operation.</p>
</dd>
</dl></td>
</tr>
<tr class="odd row-even">
<td><p>7</p></td>
<td><dl>
<dt><strong>Max</strong></dt>
<dd>
<p>Takes the max of the two values, which are required to be integers.</p>
</dd>
</dl></td>
</tr>
<tr class="even row-odd">
<td><p>8</p></td>
<td><dl>
<dt><strong>Min</strong></dt>
<dd>
<p>Takes the min of the two values, which are required to be non-negative integers. An absent module flag is treated as having the value 0.</p>
</dd>
</dl></td>
</tr>
</tbody>
</table>

It is an error for a particular unique flag ID to have multiple behaviors, except in the case of **Require** (which adds restrictions on another metadata value) or **Override**.

An example of module flags:

    !0 = !{ i32 1, !"foo", i32 1 }
    !1 = !{ i32 4, !"bar", i32 37 }
    !2 = !{ i32 2, !"qux", i32 42 }
    !3 = !{ i32 3, !"qux",
      !{
        !"foo", i32 1
      }
    }
    !llvm.module.flags = !{ !0, !1, !2, !3 }

- Metadata `!0` has the ID `!"foo"` and the value ‘1’. The behavior if two or more `!"foo"` flags are seen is to emit an error if their values are not equal.

- Metadata `!1` has the ID `!"bar"` and the value ‘37’. The behavior if two or more `!"bar"` flags are seen is to use the value ‘37’.

- Metadata `!2` has the ID `!"qux"` and the value ‘42’. The behavior if two or more `!"qux"` flags are seen is to emit a warning if their values are not equal.

- Metadata `!3` has the ID `!"qux"` and the value:

  
  
      !{ !"foo", i32 1 }

  
  
  The behavior is to emit an error if the `llvm.module.flags` does not contain a flag with the ID `!"foo"` that has the value ‘1’ after linking is performed.

<a id="synthesized-functions-module-flags-metadata"></a>

### Synthesized Functions Module Flags Metadata

These metadata specify the default attributes synthesized functions should have. These metadata are currently respected by a few instrumentation passes, such as sanitizers.

These metadata correspond to a few function attributes with significant code generation behaviors. Function attributes with just optimization purposes should not be listed because the performance impact of these synthesized functions is small.

- “frame-pointer”: **Max**. The value can be 0, 1, or 2. A synthesized function will get the “frame-pointer” function attribute, with value being “none”, “non-leaf”, or “all”, respectively.

- “function_return_thunk_extern”: The synthesized function will get the `fn_return_thunk_extern` function attribute.

- “uwtable”: **Max**. The value can be 0, 1, or 2. If the value is 1, a synthesized function will get the `uwtable(sync)` function attribute, if the value is 2, a synthesized function will get the `uwtable(async)` function attribute.

<a id="objective-c-garbage-collection-module-flags-metadata"></a>

### Objective-C Garbage Collection Module Flags Metadata

On the Mach-O platform, Objective-C stores metadata about garbage collection in a special section called “image info”. The metadata consists of a version number and a bitmask specifying what types of garbage collection are supported (if any) by the file. If two or more modules are linked together their garbage collection metadata needs to be merged rather than appended together.

The Objective-C garbage collection module flags metadata consists of the following key-value pairs:

| Key                              | Value                                                                                                                                                                                                                          |
|----------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `Objective-C Version`            | **\[Required\]** — The Objective-C ABI version. Valid values are 1 and 2.                                                                                                                                                      |
| `Objective-C Image Info Version` | **\[Required\]** — The version of the image info section. Currently always 0.                                                                                                                                                  |
| `Objective-C Image Info Section` | **\[Required\]** — The section to place the metadata. Valid values are `"__OBJC, __image_info, regular"` for Objective-C ABI version 1, and `"__DATA,__objc_imageinfo, regular, no_dead_strip"` for Objective-C ABI version 2. |
| `Objective-C Garbage Collection` | **\[Required\]** — Specifies whether garbage collection is supported or not. Valid values are 0, for no garbage collection, and 2, for garbage collection supported.                                                           |
| `Objective-C GC Only`            | **\[Optional\]** — Specifies that only garbage collection is supported. If present, its value must be 6. This flag requires that the `Objective-C Garbage Collection` flag have the value 2.                                   |

Some important flag interactions:

- If a module with `Objective-C Garbage Collection` set to 0 is merged with a module with `Objective-C Garbage Collection` set to 2, then the resulting module has the `Objective-C Garbage Collection` flag set to 0.

- A module with `Objective-C Garbage Collection` set to 0 cannot be merged with a module with `Objective-C GC Only` set to 6.

<a id="c-type-width-module-flags-metadata"></a>

### C type width Module Flags Metadata

The ARM backend emits a section into each generated object file describing the options that it was compiled with (in a compiler-independent way) to prevent linking incompatible objects, and to allow automatic library selection. Some of these options are not visible at the IR level, namely wchar_t width and enum width.

To pass this information to the backend, these options are encoded in module flags metadata, using the following key-value pairs:

<table class="docutils align-default">
<colgroup>
<col style="width: 30%" />
<col style="width: 70%" />
</colgroup>
<thead>
<tr class="header row-odd">
<th class="head"><p>Key</p></th>
<th class="head"><p>Value</p></th>
</tr>
</thead>
<tbody>
<tr class="odd row-even">
<td><p>short_wchar</p></td>
<td><ul>
<li><p>0 — sizeof(wchar_t) == 4</p></li>
<li><p>1 — sizeof(wchar_t) == 2</p></li>
</ul></td>
</tr>
<tr class="even row-odd">
<td><p>short_enum</p></td>
<td><ul>
<li><p>0 — Enums are at least as large as an `int`.</p></li>
<li><p>1 — Enums are stored in the smallest integer type which can represent all of its values.</p></li>
</ul></td>
</tr>
</tbody>
</table>

For example, the following metadata section specifies that the module was compiled with a `wchar_t` width of 4 bytes, and the underlying type of an enum is the smallest type which can represent all of its values:

    !llvm.module.flags = !{!0, !1}
    !0 = !{i32 1, !"short_wchar", i32 1}
    !1 = !{i32 1, !"short_enum", i32 0}

<a id="stack-alignment-metadata"></a>

### Stack Alignment Metadata

Changes the default stack alignment from the target ABI’s implicit default stack alignment. Takes an i32 value in bytes. It is considered an error to link two modules together with different values for this metadata.

For example:

    !llvm.module.flags = !{!0}
    !0 = !{i32 1, !"override-stack-alignment", i32 8}

This will change the stack alignment to 8B.

<a id="windows-control-flow-guard-metadata"></a>

### Windows Control Flow Guard Metadata

Controls what Control Flow Guard (CFG) checks are performed, how they are performed, and what metadata is emitted. There are multiple flags that can be used to control different aspects of CFG. Using two different values for the same flag will raise a warning when linking.

To pass this information to the backend, these options are encoded in module flags metadata, using the following key-value pairs:

<table class="docutils align-default">
<colgroup>
<col style="width: 30%" />
<col style="width: 70%" />
</colgroup>
<thead>
<tr class="header row-odd">
<th class="head"><p>Key</p></th>
<th class="head"><p>Value</p></th>
</tr>
</thead>
<tbody>
<tr class="odd row-even">
<td><p>cfguard</p></td>
<td><ul>
<li><p>0 — CFG is completely disabled.</p></li>
<li><p>1 — The CFG table is emitted, but no checks are performed.</p></li>
<li><p>2 — The CFG table is emitted and checks are performed.</p></li>
</ul></td>
</tr>
<tr class="even row-odd">
<td><p>cfguard-mechanism</p></td>
<td><ul>
<li><p>0 — CFG uses the default mechanism for the architecture.</p></li>
<li><p>1 — CFG uses the “check” mechanism. This will result in a separate call to the checker function and then one to the target.</p></li>
<li><p>2 — CFG uses the “dispatch” mechanism. This calls a dispatcher function which both checks and then calls the target.</p></li>
</ul></td>
</tr>
</tbody>
</table>

<a id="other-module-flags"></a>

### Other Module Flags

`require-logical-pointer`  
This flag indicates this module must only use logical pointer intrinsics such as [@llvm.structured.gep](intrinsics-overview-and-basic.md#i-structured-gep) or [@llvm.structured.alloca](intrinsics-overview-and-basic.md#i-structured-alloca). Using a normal [getelementptr](instructions-memory.md#i-getelementptr) or [alloca](instructions-memory.md#i-alloca) is illegal.

<a id="embedded-objects-names-metadata"></a>

## Embedded Objects Names Metadata

Offloading compilations need to embed device code into the host section table to create a fat binary. This metadata node references each global that will be embedded in the module. The primary use for this is to make referencing these globals more efficient in the IR. The metadata references nodes containing pointers to the global to be embedded followed by the section name it will be stored at:

    !llvm.embedded.objects = !{!0}
    !0 = !{ptr @object, !".section"}

<a id="automatic-linker-flags-named-metadata"></a>

## Automatic Linker Flags Named Metadata

Some targets support embedding of flags to the linker inside individual object files. Typically this is used in conjunction with language extensions which allow source files to contain linker command-line options, and have these automatically be transmitted to the linker via object files.

These flags are encoded in the IR using named metadata with the name `!llvm.linker.options`. Each operand is expected to be a metadata node which should be a list of other metadata nodes, each of which should be a list of metadata strings defining linker options.

For example, the following metadata section specifies two separate sets of linker options, presumably to link against `libz` and the `Cocoa` framework:

    !0 = !{ !"-lz" }
    !1 = !{ !"-framework", !"Cocoa" }
    !llvm.linker.options = !{ !0, !1 }

The metadata encoding as lists of lists of options, as opposed to a collapsed list of options, is chosen so that the IR encoding can use multiple option strings to specify e.g., a single library, while still having that specifier be preserved as an atomic element that can be recognized by a target-specific assembly writer or object file emitter.

Each individual option is required to be either a valid option for the target’s linker, or an option that is reserved by the target-specific assembly writer or object file emitter. No other aspect of these options is defined by the IR.

<a id="dependent-libs-named-metadata"></a>

## Dependent Libs Named Metadata

Some targets support embedding of strings into object files to indicate a set of libraries to add to the link. Typically this is used in conjunction with language extensions which allow source files to explicitly declare the libraries they depend on, and have these automatically be transmitted to the linker via object files.

The list is encoded in the IR using named metadata with the name `!llvm.dependent-libraries`. Each operand is expected to be a metadata node which should contain a single string operand.

For example, the following metadata section contains two library specifiers:

    !0 = !{!"a library specifier"}
    !1 = !{!"another library specifier"}
    !llvm.dependent-libraries = !{ !0, !1 }

Each library specifier will be handled independently by the consuming linker. The effect of the library specifiers are defined by the consuming linker.

<a id="llvm-errno-tbaa-named-metadata"></a>

## ‘`llvm.errno.tbaa`’ Named Metadata

The module-level `!llvm.errno.tbaa` metadata specifies the TBAA nodes used for accessing `errno`. These nodes are guaranteed to represent int-compatible accesses according to C/C++ strict aliasing rules. This should let LLVM alias analyses to reason about aliasing with `errno` when calling library functions that may set `errno`, allowing optimizations such as store-to-load forwarding across such routines.

For example, the following is a valid metadata specifying the TBAA information for an integer access:

    !llvm.errno.tbaa = !{!0}
    !0 = !{!1, !1, i64 0}
    !1 = !{!"int", !2, i64 0}
    !2 = !{!"omnipotent char", !3, i64 0}
    !3 = !{!"Simple C/C++ TBAA"}

Multiple TBAA operands are allowed to support merging of modules that may use different TBAA hierarchies (e.g., when mixing C and C++).
