[Wiki](../index.md) › [LLVM LangRef](index.md)

# High level structure

LLVM 23.1.0 Language Reference, part of the [index](index.md). Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html>. License: Apache-2.0 with LLVM exception.

<a id="high-level-structure"></a>

## High Level Structure

<a id="module-structure"></a>

### Module Structure

LLVM programs are composed of `Module`’s, each of which is a translation unit of the input programs. Each module consists of functions, global variables, and symbol table entries. Modules may be combined together with the LLVM linker, which merges function (and global variable) definitions, resolves forward declarations, and merges symbol table entries. Here is an example of the “hello world” module:

    ; Declare the string constant as a global constant.
    @.str = private unnamed_addr constant [13 x i8] c"hello world\0A\00"

    ; External declaration of the puts function
    declare i32 @puts(ptr captures(none)) nounwind

    ; Definition of main function
    define i32 @main() {
      ; Call puts function to write out the string to stdout.
      call i32 @puts(ptr @.str)
      ret i32 0
    }

    ; Named metadata
    !0 = !{i32 42, null, !"string"}
    !foo = !{!0}

This example is made up of a [global variable](#globalvars) named “`.str`”, an external declaration of the “`puts`” function, a [function definition](#functionstructure) for “`main`” and [named metadata](#namedmetadatastructure) “`foo`”.

In general, a module is made up of a list of global values (where both functions and global variables are global values). Global values are represented by a pointer to a memory location (in this case, a pointer to an array of char, and a pointer to a function), and have one of the following [linkage types](#linkage).

<a id="linkage-types"></a>

<a id="linkage"></a>

### Linkage Types

All Global Variables and Functions have one of the following types of linkage:

`private`  
Global values with “`private`” linkage are only directly accessible by objects in the current module. In particular, linking code into a module with a private global value may cause the private to be renamed as necessary to avoid collisions. Because the symbol is private to the module, all references can be updated. This doesn’t show up in any symbol table in the object file.

`internal`  
Similar to private, but the value shows as a local symbol (`STB_LOCAL` in the case of ELF) in the object file. This corresponds to the notion of the ‘`static`’ keyword in C.

`available_externally`  
Globals with “`available_externally`” linkage are never emitted into the object file corresponding to the LLVM module. From the linker’s perspective, an `available_externally` global is equivalent to an external declaration. They exist to allow inlining and other optimizations to take place given knowledge of the definition of the global, which is known to be somewhere outside the module. Globals with `available_externally` linkage are allowed to be discarded at will, and allow inlining and other optimizations. This linkage type is only allowed on definitions, not declarations.

`linkonce`  
Globals with “`linkonce`” linkage are merged with other globals of the same name when linkage occurs. This can be used to implement some forms of inline functions, templates, or other code which must be generated in each translation unit that uses it, but where the body may be overridden with a more definitive definition later. Unreferenced `linkonce` globals are allowed to be discarded. Note that `linkonce` linkage does not actually allow the optimizer to inline the body of this function into callers because it doesn’t know if this definition of the function is the definitive definition within the program or whether it will be overridden by a stronger definition. To enable inlining and other optimizations, use “`linkonce_odr`” linkage.

`weak`  
“`weak`” linkage has the same merging semantics as `linkonce` linkage, except that unreferenced globals with `weak` linkage may not be discarded. This is used for globals that are declared “weak” in C source code.

`common`  
“`common`” linkage is most similar to “`weak`” linkage, but they are used for tentative definitions in C, such as “`int X;`” at global scope. Symbols with “`common`” linkage are merged in the same way as `weak symbols`, and they may not be deleted if unreferenced. `common` symbols may not have an explicit section, must have a zero initializer, and may not be marked ‘[constant](#globalvars)’. Functions and aliases may not have common linkage.

<a id="linkage-appending"></a>

`appending`  
“`appending`” linkage may only be applied to global variables of pointer to array type. When two global variables with appending linkage are linked together, the two global arrays are appended together. This is the LLVM, typesafe, equivalent of having the system linker append together “sections” with identical names when `.o` files are linked.

Unfortunately this doesn’t correspond to any feature in `.o` files, so it can only be used for variables like `llvm.global_ctors` which llvm interprets specially.

`extern_weak`  
The semantics of this linkage follow the ELF object file model: the symbol is weak until linked, if not linked, the symbol becomes null instead of being an undefined reference.

`linkonce_odr`, `weak_odr`  
The `odr` suffix indicates that all globals defined with the given name are equivalent, along the lines of the C++ “one definition rule” (“ODR”). Informally, this means we can inline functions and fold loads of constants.

Formally, use the following definition: when an `odr` function is called, one of the definitions is non-deterministically chosen to run. For `odr` variables, if any byte in the value is not equal in all initializers, that byte is a [poison value](constants.md#poisonvalues). For aliases and ifuncs, apply the rule for the underlying function or variable.

These linkage types are otherwise the same as their non-`odr` versions.

`external`  
If none of the above identifiers are used, the global is externally visible, meaning that it participates in linkage and can be used to resolve external symbol references.

It is illegal for a global variable or function *declaration* to have any linkage type other than `external` or `extern_weak`.

<a id="calling-conventions"></a>

<a id="callingconv"></a>

### Calling Conventions

LLVM [functions](#functionstructure), [calls](instructions-other.md#i-call) and [invokes](instructions-terminators.md#i-invoke) can all have an optional calling convention specified for the call. The calling convention of any pair of dynamic caller/callee must match, or the behavior of the program is undefined. The following calling conventions are supported by LLVM, and more may be added in the future:

“`ccc`” - The C calling convention  
This calling convention (the default if no other calling convention is specified) matches the target C calling conventions. This calling convention supports varargs function calls and tolerates some mismatch in the declared prototype and implemented declaration of the function (as does normal C).

“`fastcc`” - The fast calling convention  
This calling convention attempts to make calls as fast as possible (e.g., by passing things in registers). This calling convention allows the target to use whatever tricks it wants to produce fast code for the target, without having to conform to an externally specified ABI (Application Binary Interface). Targets may use different implementations according to different features. In this case, a TTI interface `useFastCCForInternalCall` must return false when any caller functions and the callee belong to different implementations. [Tail calls](CodeGenerator.html#tail-call-section) can only be optimized when this, the tailcc, the GHC or the HiPE convention is used. This calling convention does not support varargs and requires the prototype of all callees to exactly match the prototype of the function definition.

“`coldcc`” - The cold calling convention  
This calling convention attempts to make code in the caller as efficient as possible under the assumption that the call is not commonly executed. As such, these calls often preserve all registers so that the call does not break any live ranges in the caller side. This calling convention does not support varargs and requires the prototype of all callees to exactly match the prototype of the function definition. Furthermore the inliner doesn’t consider such function calls for inlining.

“`ghccc`” - GHC convention  
This calling convention has been implemented specifically for use by the [Glasgow Haskell Compiler (GHC)](http://www.haskell.org/ghc). It passes everything in registers, going to extremes to achieve this by disabling callee save registers. This calling convention should not be used lightly but only for specific situations such as an alternative to the *register pinning* performance technique often used when implementing functional programming languages. At the moment only X86, AArch64, and RISCV support this convention. The following limitations exist:

- On *X86-32* only up to 4 bit type parameters are supported. No floating-point types are supported.

- On *X86-64* only up to 10 bit type parameters and 6 floating-point parameters are supported.

- On *AArch64* only up to 4 32-bit floating-point parameters, 4 64-bit floating-point parameters, and 10 bit type parameters are supported.

- *RISCV64* only supports up to 11 bit type parameters, 4 32-bit floating-point parameters, and 4 64-bit floating-point parameters.

This calling convention supports [tail call optimization](CodeGenerator.html#tail-call-section) but requires both the caller and callee to use it.

“`cc 11`” - The HiPE calling convention  
This calling convention has been implemented specifically for use by the [High-Performance Erlang (HiPE)](http://www.it.uu.se/research/group/hipe/) compiler, *the* native code compiler of the [Ericsson’s Open Source Erlang/OTP system](http://www.erlang.org/download.shtml). It uses more registers for argument passing than the ordinary C calling convention and defines no callee-saved registers. The calling convention properly supports [tail call optimization](CodeGenerator.html#tail-call-section) but requires that both the caller and the callee use it. It uses a *register pinning* mechanism, similar to GHC’s convention, for keeping frequently accessed runtime components pinned to specific hardware registers. At the moment only X86 supports this convention (both 32 and 64 bit).

“`anyregcc`” - Dynamic calling convention for code patching  
This is a special convention that supports patching an arbitrary code sequence in place of a call site. This convention forces the call arguments into registers but allows them to be dynamically allocated. This can currently only be used with calls to `llvm.experimental.patchpoint` because only this intrinsic records the location of its arguments in a side table. See [Stack maps and patch points in LLVM](StackMaps.html).

“`preserve_mostcc`” - The `PreserveMost` calling convention  
This calling convention attempts to make the code in the caller as unintrusive as possible. This convention behaves identically to the `C` calling convention on how arguments and return values are passed, but it uses a different set of caller/callee-saved registers. This alleviates the burden of saving and recovering a large register set before and after the call in the caller. If the arguments are passed in callee-saved registers, then they will be preserved by the callee across the call. This doesn’t apply for values returned in callee-saved registers.

- On X86-64 the callee preserves all general purpose registers, except for R11 and return registers, if any. R11 can be used as a scratch register. The treatment of floating-point registers (XMMs/YMMs) matches the OS’s C calling convention: on most platforms, they are not preserved and need to be saved by the caller, but on Windows, xmm6-xmm15 are preserved.

- On AArch64 the callee preserves all general purpose registers, except X0-X8 and X16-X18. Not allowed with `nest`.

- On RISC-V the callee preserves x5-x31 except x6, x7 and x28 registers.

- On LoongArch the callee preserves r4-r31 except r12-r15 and r20-r21 registers.

The idea behind this convention is to support calls to runtime functions that have a hot path and a cold path. The hot path is usually a small piece of code that doesn’t use many registers. The cold path might need to call out to another function and therefore only needs to preserve the caller-saved registers, which haven’t already been saved by the caller. The `PreserveMost` calling convention is very similar to the `cold` calling convention in terms of caller/callee-saved registers, but they are used for different types of function calls. `coldcc` is for function calls that are rarely executed, whereas `preserve_mostcc` function calls are intended to be on the hot path and definitely executed a lot. Furthermore `preserve_mostcc` doesn’t prevent the inliner from inlining the function call.

This calling convention will be used by a future version of the Objective-C runtime and should therefore still be considered experimental at this time. Although this convention was created to optimize certain runtime calls to the Objective-C runtime, it is not limited to this runtime and might be used by other runtimes in the future too. The current implementation only supports X86-64, but the intention is to support more architectures in the future.

“`preserve_allcc`” - The `PreserveAll` calling convention  
This calling convention attempts to make the code in the caller even less intrusive than the `PreserveMost` calling convention. This calling convention also behaves identically to the `C` calling convention on how arguments and return values are passed, but it uses a different set of caller/callee-saved registers. This removes the burden of saving and recovering a large register set before and after the call in the caller. If the arguments are passed in callee-saved registers, then they will be preserved by the callee across the call. This doesn’t apply for values returned in callee-saved registers.

- On X86-64 the callee preserves all general purpose registers, except for R11. R11 can be used as a scratch register. Furthermore it also preserves all floating-point registers (XMMs/YMMs).

- On AArch64 the callee preserves all general purpose registers, except X0-X8 and X16-X18. Furthermore it also preserves lower 128 bits of V8-V31 SIMD floating point registers. Not allowed with `nest`.

The idea behind this convention is to support calls to runtime functions that don’t need to call out to any other functions.

This calling convention, like the `PreserveMost` calling convention, will be used by a future version of the Objective-C runtime and should be considered experimental at this time.

“`preserve_nonecc`” - The `PreserveNone` calling convention  
This calling convention doesn’t preserve any general registers. So all general registers are caller saved registers. It also uses all general registers to pass arguments. This attribute doesn’t impact non-general purpose registers (e.g., floating point registers, on X86 XMMs/YMMs). Non-general purpose registers still follow the standard C calling convention. Currently it is for x86_64, AArch64 and LoongArch only.

“`cxx_fast_tlscc`” - The `CXX_FAST_TLS` calling convention for access functions  
Clang generates an access function to access C++-style Thread Local Storage (TLS). The access function generally has an entry block, an exit block and an initialization block that is run at the first time. The entry and exit blocks can access a few TLS IR variables, each access will be lowered to a platform-specific sequence.

This calling convention aims to minimize overhead in the caller by preserving as many registers as possible (all the registers that are preserved on the fast path, composed of the entry and exit blocks).

This calling convention behaves identically to the `C` calling convention on how arguments and return values are passed, but it uses a different set of caller/callee-saved registers.

Given that each platform has its own lowering sequence, hence its own set of preserved registers, we can’t use the existing `PreserveMost`.

- On X86-64 the callee preserves all general purpose registers, except for RDI and RAX.

“`tailcc`” - Tail callable calling convention  
This calling convention ensures that calls in tail position will always be tail call optimized. This calling convention is equivalent to fastcc, except for an additional guarantee that tail calls will be produced whenever possible. [Tail calls](CodeGenerator.html#tail-call-section) can only be optimized when this, the fastcc, the GHC or the HiPE convention is used. This calling convention does not support varargs and requires the prototype of all callees to exactly match the prototype of the function definition.

“`swiftcc`” - This calling convention is used for Swift language.  
- On X86-64 RCX and R8 are available for additional integer returns, and XMM2 and XMM3 are available for additional FP/vector returns.

- On iOS platforms, we use AAPCS-VFP calling convention.

“`swifttailcc`”  
This calling convention is like `swiftcc` in most respects, but also the callee pops the argument area of the stack so that mandatory tail calls are possible as in `tailcc`.

“`cfguard_checkcc`” - Windows Control Flow Guard (Check mechanism)  
This calling convention is used for the Control Flow Guard check function, calls to which can be inserted before indirect calls to check that the call target is a valid function address. The check function has no return value, but it will trigger an OS-level error if the address is not a valid target. The set of registers preserved by the check function, and the register containing the target address are architecture-specific.

- On X86 the target address is passed in ECX.

- On ARM the target address is passed in R0.

- On AArch64 the target address is passed in X15.

“`cc <n>`” - Numbered convention  
Any calling convention may be specified by number, allowing target-specific calling conventions to be used. Target-specific calling conventions start at 64.

More calling conventions can be added/defined on an as-needed basis, to support Pascal conventions or any other well-known target-independent convention.

<a id="visibility-styles"></a>

<a id="visibilitystyles"></a>

### Visibility Styles

All Global Variables and Functions have one of the following visibility styles:

“`default`” - Default style  
On targets that use the ELF object file format, default visibility means that the declaration is visible to other modules and, in shared libraries, means that the declared entity may be overridden. On Darwin, default visibility means that the declaration is visible to other modules. On XCOFF, default visibility means no explicit visibility bit will be set and whether the symbol is visible (i.e “exported”) to other modules depends primarily on export lists provided to the linker. Default visibility corresponds to “external linkage” in the language.

“`hidden`” - Hidden style  
Two declarations of an object with hidden visibility refer to the same object if they are in the same shared object. Usually, hidden visibility indicates that the symbol will not be placed into the dynamic symbol table, so no other module (executable or shared library) can reference it directly.

“`protected`” - Protected style  
On ELF, protected visibility indicates that the symbol will be placed in the dynamic symbol table, but that references within the defining module will bind to the local symbol. That is, the symbol cannot be overridden by another module.

A symbol with `internal` or `private` linkage must have `default` visibility.

<a id="dll-storage-classes"></a>

<a id="dllstorageclass"></a>

### DLL Storage Classes

All Global Variables, Functions and Aliases can have one of the following DLL storage classes:

`dllimport`  
“`dllimport`” causes the compiler to reference a function or variable via a global pointer to a pointer that is set up by the DLL exporting the symbol. On Microsoft Windows targets, the pointer name is formed by combining `__imp_` and the function or variable name.

`dllexport`  
On Microsoft Windows targets, “`dllexport`” causes the compiler to provide a global pointer to a pointer in a DLL, so that it can be referenced with the `dllimport` attribute. The pointer name is formed by combining `__imp_` and the function or variable name. On XCOFF targets, `dllexport` indicates that the symbol will be made visible to other modules using “exported” visibility and thus placed by the linker in the loader section symbol table. Since this storage class exists for defining a DLL interface, the compiler, assembler and linker know it is externally referenced and must refrain from deleting the symbol.

A symbol with `internal` or `private` linkage cannot have a DLL storage class.

<a id="thread-local-storage-models"></a>

<a id="tls-model"></a>

### Thread Local Storage Models

A variable may be defined as `thread_local`, which means that it will not be shared by threads (each thread will have a separate copy of the variable). Not all targets support thread-local variables. Optionally, a TLS model may be specified:

`localdynamic`  
For variables that are only used within the current shared library.

`initialexec`  
For variables in modules that will not be loaded dynamically.

`localexec`  
For variables defined in the executable and only used within it.

If no explicit model is given, the “general dynamic” model is used.

The models correspond to the ELF TLS models; see [ELF Handling For Thread-Local Storage](http://people.redhat.com/drepper/tls.pdf) for more information on under which circumstances the different models may be used. The target may choose a different TLS model if the specified model is not supported, or if a better choice of model can be made.

A model can also be specified in an alias, but then it only governs how the alias is accessed. It will not have any effect on the aliasee.

For platforms without linker support of ELF TLS model, the `-femulated-tls` flag can be used to generate GCC-compatible emulated TLS code.

<a id="runtime-preemption-specifiers"></a>

<a id="runtime-preemption-model"></a>

### Runtime Preemption Specifiers

Global variables, functions and aliases may have an optional runtime preemption specifier. If a preemption specifier isn’t given explicitly, then a symbol is assumed to be `dso_preemptable`.

`dso_preemptable`  
Indicates that the function or variable may be replaced by a symbol from outside the linkage unit at runtime.

`dso_local`  
The compiler may assume that a function or variable marked as `dso_local` will resolve to a symbol within the same linkage unit. Direct access will be generated even if the definition is not within this compilation unit.

<a id="structure-types"></a>

<a id="namedtypes"></a>

### Structure Types

LLVM IR allows you to specify both “identified” and “literal” [structure types](type-system.md#t-struct). Literal types are uniqued structurally, but identified types are never uniqued. An [opaque structural type](type-system.md#t-opaque) can also be used to forward declare a type that is not yet available.

An example of an identified structure specification is:

    %mytype = type { %mytype*, i32 }

Prior to the LLVM 3.0 release, identified types were structurally uniqued. Only literal types are uniqued in recent versions of LLVM.

<a id="non-integral-pointer-type"></a>

<a id="nointptrtype"></a>

### Non-Integral Pointer Type

Note: non-integral pointer types are a work in progress, and they should be considered experimental at this time.

For most targets, the pointer representation is a direct mapping from the bitwise representation to the address of the underlying memory location. Such pointers are considered “integral”, and any pointers where the representation is not just an integer address are called “non-integral”.

Non-integral pointers have at least one of the following three properties:

- the pointer representation contains non-address bits

- the pointer representation is unstable (may change at any time in a target-specific way)

- the pointer representation has external state

These properties (or combinations thereof) can be applied to pointers via the [datalayout string](#langref-datalayout).

The exact implications of these properties are target-specific. The following subsections describe the IR semantics and restrictions to optimization passes for each of these properties.

<a id="pointers-with-non-address-bits"></a>

#### Pointers with non-address bits

Pointers in this address space have a bitwise representation that not only has address bits, but also some other target-specific metadata. In most cases pointers with non-address bits behave exactly the same as integral pointers, the only difference is that it is not possible to create a pointer just from an address unless all the non-address bits are also recreated correctly in a target-specific way.

An example of pointers with non-address bits are the AMDGPU buffer descriptors which are 160 bits: a 128-bit fat pointer and a 32-bit offset. Similarly, CHERI capabilities contain a 32- or 64-bit address as well as the same number of metadata bits, but unlike the AMDGPU buffer descriptors they have external state in addition to non-address bits.

<a id="unstable-pointer-representation"></a>

#### Unstable pointer representation

Pointers in this address space have an *unspecified* bitwise representation (i.e., not backed by a fixed integer). The bitwise pattern of such pointers is allowed to change in a target-specific way. For example, this could be a pointer type used with copying garbage collection where the garbage collector could update the pointer at any time in the collection sweep.

`inttoptr` and `ptrtoint` instructions have the same semantics as for integral (i.e., normal) pointers in that they convert integers to and from corresponding pointer types, but there are additional implications to be aware of.

For “unstable” pointer representations, the bit-representation of the pointer may not be stable, so two identical casts of the same operand may or may not return the same value. Said differently, the conversion to or from the “unstable” pointer type depends on environmental state in an implementation defined manner.

If the frontend wishes to observe a *particular* value following a cast, the generated IR must fence with the underlying environment in an implementation defined manner. (In practice, this tends to require `noinline` routines for such operations.)

From the perspective of the optimizer, `inttoptr` and `ptrtoint` for “unstable” pointer types are analogous to ones on integral types with one key exception: the optimizer may not, in general, insert new dynamic occurrences of such casts. If a new cast is inserted, the optimizer would need to either ensure that a) all possible values are valid, or b) appropriate fencing is inserted. Since the appropriate fencing is implementation defined, the optimizer can’t do the latter. The former is challenging as many commonly expected properties, such as `ptrtoint(v)-ptrtoint(v) == 0`, don’t hold for “unstable” pointer types. Similar restrictions apply to intrinsics that might examine the pointer bits, such as [llvm.ptrmask](intrinsics-general.md#int-ptrmask).

The alignment information provided by the frontend for an “unstable” pointer (typically using attributes or metadata) must be valid for every possible representation of the pointer.

<a id="pointers-with-external-state"></a>

#### Pointers with external state

A further special case of non-integral pointers is ones that include external state (such as bounds information or a type tag) with a target-defined size. An example of such a type is a CHERI capability, where there is an additional validity bit that is part of all pointer-typed registers, but is located in memory at an implementation-defined address separate from the pointer itself. Another example would be a fat-pointer scheme where pointers remain plain integers, but the associated bounds are stored in an out-of-band table.

Unless also marked as “unstable”, the bit-wise representation of pointers with external state is stable and `ptrtoint(x)` always yields a deterministic value. This means transformation passes are still permitted to insert new `ptrtoint` instructions.

The following restrictions apply to IR level optimization passes:

The `inttoptr` instruction does not recreate the external state and therefore it is target dependent whether it can be used to create a dereferenceable pointer. In general passes should assume that the result of such an `inttoptr` is not dereferenceable. For example, on CHERI targets an `inttoptr` will yield a capability with the external state (the validity tag bit) set to zero, which will cause any dereference to trap. The `ptrtoint` instruction also only returns the “in-band” state and omits all external state.

When a `store ptr addrspace(N) %p, ptr @dst` of such a non-integral pointer is performed, the external metadata is also stored to an implementation-defined location. Similarly, a `%val = load ptr addrspace(N), ptr @dst` will fetch the external metadata and make it available for all uses of `%val`. Similarly, the `llvm.memcpy` and `llvm.memmove` intrinsics also transfer the external state. This is essential to allow frontends to efficiently emit copies of structures containing such pointers, since expanding all these copies as individual loads and stores would affect compilation speed and inhibit optimizations.

Notionally, these external bits are part of the pointer, but since `inttoptr` / `ptrtoint` only operate on the “in-band” bits of the pointer and the external bits are not explicitly exposed, they are not included in the size specified in the [datalayout string](#langref-datalayout).

When a pointer type has external state, all roundtrips via memory must be performed as loads and stores of the correct type since stores of other types may not propagate the external data. Therefore it is not legal to convert an existing load/store (or a `llvm.memcpy` / `llvm.memmove` intrinsic) of pointer types with external state to a load/store of an integer or byte type with the same bitwidth, as that may drop the external state.

<a id="global-variables"></a>

<a id="globalvars"></a>

### Global Variables

Global variables define regions of memory allocated at compilation time instead of run-time.

Global variable definitions must be initialized with a sized value.

Global variables in other translation units can also be declared, in which case they don’t have an initializer.

Global variables can optionally specify a [linkage type](#linkage).

Either global variable definitions or declarations may have an explicit section to be placed in and may have an optional explicit alignment specified. If there is a mismatch between the explicit or inferred section information for the variable declaration and its definition, the resulting behavior is undefined.

A variable may be defined as a global `constant`, which indicates that the contents of the variable will **never** be modified (enabling better optimization, allowing the global data to be placed in the read-only section of an executable, etc). Note that variables that need runtime initialization cannot be marked `constant` as there is a store to the variable.

LLVM explicitly allows *declarations* of global variables to be marked constant, even if the final definition of the global is not. This capability can be used to enable slightly better optimization of the program, but requires the language definition to guarantee that optimizations based on the ‘constantness’ are valid for the translation units that do not include the definition.

As SSA values, global variables define pointer values that are in scope for (i.e., they dominate) all basic blocks in the program. Global variables always define a pointer to their “content” type because they describe a region of memory, and all [allocated object](#allocatedobjects) in LLVM are accessed through pointers.

Global variables can be marked with `unnamed_addr` which indicates that the address is not significant, only the content. Constants marked like this can be merged with other constants if they have the same initializer, and can also be duplicated. Note that a constant with significant address *can* be merged with a `unnamed_addr` constant, the result being a constant whose address is significant.

Warning

Constant duplication currently makes it unsound to compare pointers if either may be `unnamed_addr`, because each reference to the global in the IR may return a different pointer, and optimization passes may create additional references. Optimization passes can also create pointer comparisons with the expectation that the comparison will return true if the object is the same, which theoretically can make any usage of `unnamed_addr` unsound, but in practice it is unlikely that input IR that does not explicitly compare pointers will be affected by this issue.

If the `local_unnamed_addr` attribute is given, the address is known to not be significant within the module.

A global variable may be declared to reside in a target-specific numbered address space. For targets that support them, address spaces may affect how optimizations are performed and/or what target instructions are used to access the variable. The default address space is zero. The address space qualifier must precede any other attributes.

LLVM allows an explicit section to be specified for globals. If the target supports it, it will emit globals to the section specified. Additionally, the global can be placed in a comdat if the target has the necessary support.

External declarations may have an explicit section specified. Section information is retained in LLVM IR for targets that make use of this information. Attaching section information to an external declaration is an assertion that its definition is located in the specified section. If the definition is located in a different section, the behavior is undefined.

LLVM allows an explicit code model to be specified for globals. If the target supports it, it will emit globals in the code model specified, overriding the code model used to compile the translation unit. The allowed values are “tiny”, “small”, “kernel”, “medium”, “large”. This may be extended in the future to specify global data layout that doesn’t cleanly fit into a specific code model.

By default, global initializers are optimized by assuming that global variables defined within the module are not modified from their initial values before the start of the global initializer. This is true even for variables potentially accessible from outside the module, including those with external linkage or appearing in `@llvm.used` or dllexported variables. This assumption may be suppressed by marking the variable with `externally_initialized`.

An explicit alignment may be specified for a global, which must be a power of 2. If not present, or if the alignment is set to zero, the alignment of the global is set by the target to whatever it feels convenient. If an explicit alignment is specified, the global is forced to have exactly that alignment. Targets and optimizers are not allowed to over-align the global if the global has an assigned section. In this case, the extra alignment could be observable: for example, code could assume that the globals are densely packed in their section and try to iterate over them as an array, alignment padding would break this iteration. For TLS variables, the module flag `MaxTLSAlign`, if present, limits the alignment to the given value. Optimizers are not allowed to impose a stronger alignment on these variables. The maximum alignment is `1 << 32`.

For global variable declarations, as well as definitions that may be replaced at link time (`linkonce`, `weak`, `extern_weak` and `common` linkage types), the allocation size and alignment of the definition it resolves to must be greater than or equal to that of the declaration or replaceable definition, otherwise the behavior is undefined.

Globals can also have a [DLL storage class](#dllstorageclass), an optional [runtime preemption specifier](#runtime-preemption-model), an optional [global attributes](#glattrs) and an optional list of attached [metadata](metadata.md#metadata).

Variables and aliases can have a [Thread Local Storage Model](#tls-model).

Globals cannot be or contain [Scalable vectors](type-system.md#t-vector) because their size is unknown at compile time. They are allowed in structs to facilitate intrinsics returning multiple values. Generally, structs containing scalable vectors are not considered “sized” and cannot be used in loads, stores, allocas, or GEPs. The only exception to this rule is for structs that contain scalable vectors of the same type (e.g., `{<vscale x 2 x i32>, <vscale x 2 x i32>}` contains the same type while `{<vscale x 2 x i32>, <vscale x 2 x i64>}` doesn’t). These kinds of structs (we may call them homogeneous scalable vector structs) are considered sized and can be used in loads, stores, allocas, but not GEPs.

Globals with `toc-data` attribute set are stored in TOC of XCOFF. Their alignments are not larger than that of a TOC entry. Optimizations should not increase their alignments to mitigate TOC overflow.

Syntax:

    @<GlobalVarName> = [Linkage] [PreemptionSpecifier] [Visibility]
                       [DLLStorageClass] [ThreadLocal]
                       [(unnamed_addr|local_unnamed_addr)] [AddrSpace]
                       [ExternallyInitialized]
                       <global | constant> <Type> [<InitializerConstant>]
                       [, section "name"] [, partition "name"]
                       [, comdat [($name)]] [, align <Alignment>]
                       [, code_model "model"]
                       [, no_sanitize_address] [, no_sanitize_hwaddress]
                       [, sanitize_address_dyninit] [, sanitize_memtag]
                       (, !name !N)*

For example, the following defines a global in a numbered address space with an initializer, section, and alignment:

    @G = addrspace(5) constant float 1.0, section "foo", align 4

The following example just declares a global variable

    @G = external global i32

The following example defines a global variable with the `large` code model:

    @G = internal global i32 0, code_model "large"

The following example defines a thread-local global with the `initialexec` TLS model:

    @G = thread_local(initialexec) global i32 0, align 4

<a id="functions"></a>

<a id="functionstructure"></a>

### Functions

LLVM function definitions consist of the “`define`” keyword, an optional [linkage type](#linkage), an optional [runtime preemption specifier](#runtime-preemption-model), an optional [visibility style](BitCodeFormat.html#visibility), an optional [DLL storage class](#dllstorageclass), an optional [calling convention](#callingconv), an optional `unnamed_addr` attribute, a return type, an optional [parameter attribute](#paramattrs) for the return type, a function name, a (possibly empty) argument list (each with optional [parameter attributes](#paramattrs)), optional [function attributes](#fnattrs), an optional address space, an optional section, an optional partition, an optional minimum alignment, an optional preferred alignment, an optional [comdat](#langref-comdats), an optional [garbage collector name](#gc), an optional [prefix](#prefixdata), an optional [prologue](#prologuedata), an optional [personality](#personalityfn), an optional list of attached [metadata](metadata.md#metadata), an opening curly brace, a list of basic blocks, and a closing curly brace.

Syntax:

    define [linkage] [PreemptionSpecifier] [visibility] [DLLStorageClass]
           [cconv] [ret attrs]
           <ResultType> @<FunctionName> ([argument list])
           [(unnamed_addr|local_unnamed_addr)] [AddrSpace] [fn Attrs]
           [section "name"] [partition "name"] [comdat [($name)]] [align N]
           [prefalign(N)] [gc] [prefix Constant] [prologue Constant]
           [personality Constant] (!name !N)* { ... }

The argument list is a comma-separated sequence of arguments where each argument is of the following form:

Syntax:

    <type> [parameter Attrs] [name]

LLVM function declarations consist of the “`declare`” keyword, an optional [linkage type](#linkage), an optional [visibility style](BitCodeFormat.html#visibility), an optional [DLL storage class](#dllstorageclass), an optional [calling convention](#callingconv), an optional `unnamed_addr` or `local_unnamed_addr` attribute, an optional address space, a return type, an optional [parameter attribute](#paramattrs) for the return type, a function name, a possibly empty list of arguments, an optional alignment, an optional [garbage collector name](#gc), an optional [prefix](#prefixdata), and an optional [prologue](#prologuedata).

Syntax:

    declare [linkage] [visibility] [DLLStorageClass]
            [cconv] [ret attrs]
            <ResultType> @<FunctionName> ([argument list])
            [(unnamed_addr|local_unnamed_addr)] [align N] [gc]
            [prefix Constant] [prologue Constant]

A function definition contains a list of basic blocks, forming the CFG (Control Flow Graph) for the function. Each basic block may optionally start with a label (giving the basic block a symbol table entry), contains a list of instructions and [debug records](instructions-vector-aggregate.md#debugrecords), and ends with a [terminator](instructions-terminators.md#terminators) instruction (such as a branch or function return). If an explicit label name is not provided, a block is assigned an implicit numbered label, using the next value from the same counter as used for unnamed temporaries ([see above](introduction.md#identifiers)). For example, if a function entry block does not have an explicit label, it will be assigned label “%0”, then the first unnamed temporary in that block will be “%1”, etc. If a numeric label is explicitly specified, it must match the numeric label that would be used implicitly.

The first basic block in a function is special in two ways: it is immediately executed on entrance to the function, and it is not allowed to have predecessor basic blocks (i.e., there can not be any branches to the entry block of a function). Because the block can have no predecessors, it also cannot have any [PHI nodes](instructions-other.md#i-phi).

LLVM allows an explicit section to be specified for functions. If the target supports it, it will emit functions to the section specified. Additionally, the function can be placed in a COMDAT.

An explicit minimum alignment (`align`) may be specified for a function. If not present, or if the alignment is set to zero, the alignment of the function is set according to the preferred alignment rules described below. If an explicit minimum alignment is specified, the function is forced to have at least that much alignment. All alignments must be a power of 2.

An explicit preferred alignment (`prefalign`) may also be specified for a function (definitions only, and must be a power of 2). If a function does not have a preferred alignment attribute, the preferred alignment is determined in a target-specific way. The preferred alignment, if provided, is treated as a hint; the final alignment of the function will generally be set to a value somewhere between the minimum alignment and the preferred alignment.

If the `unnamed_addr` attribute is given, the address is known to not be significant and two identical functions can be merged.

If the `local_unnamed_addr` attribute is given, the address is known to not be significant within the module.

If an explicit address space is not given, it will default to the program address space from the [datalayout string](#langref-datalayout).

<a id="aliases"></a>

<a id="langref-aliases"></a>

### Aliases

Aliases, unlike function or variables, don’t create any new data. They are just a new symbol and metadata for an existing position.

Aliases have a name and an aliasee that is either a global value or a constant expression.

Aliases may have an optional [linkage type](#linkage), an optional [runtime preemption specifier](#runtime-preemption-model), an optional [visibility style](BitCodeFormat.html#visibility), an optional [DLL storage class](#dllstorageclass) and an optional [tls model](#tls-model).

Syntax:

    @<Name> = [Linkage] [PreemptionSpecifier] [Visibility] [DLLStorageClass] [ThreadLocal] [(unnamed_addr|local_unnamed_addr)] alias <AliaseeTy>, <AliaseeTy>* @<Aliasee>
              [, partition "name"]

The linkage must be one of `private`, `internal`, `linkonce`, `weak`, `linkonce_odr`, `weak_odr`, `external`, `available_externally`. Note that some system linkers might not correctly handle dropping a weak symbol that is aliased.

Aliases that are not `unnamed_addr` are guaranteed to have the same address as the aliasee expression. `unnamed_addr` ones are only guaranteed to point to the same content.

If the `local_unnamed_addr` attribute is given, the address is known to not be significant within the module.

Since aliases are only a second name, some restrictions apply, of which some can only be checked when producing an object file:

- The expression defining the aliasee must be computable at assembly time. Since it is just a name, no relocations can be used.

- No alias in the expression can be weak as the possibility of the intermediate alias being overridden cannot be represented in an object file.

- If the alias has the `available_externally` linkage, the aliasee must be an `available_externally` global value; otherwise the aliasee can be an expression but no global value in the expression can be a declaration, since that would require a relocation, which is not possible.

- If either the alias or the aliasee may be replaced by a symbol outside the module at link time or runtime, any optimization cannot replace the alias with the aliasee, since the behavior may be different. The alias may be used as a name guaranteed to point to the content in the current module.

<a id="ifuncs"></a>

<a id="langref-ifunc"></a>

### IFuncs

IFuncs, like aliases, don’t create any new data or func. They are just a new symbol that is resolved at runtime by calling a resolver function.

On ELF platforms, IFuncs are resolved by the dynamic linker at load time. On Mach-O platforms, they are lowered in terms of `.symbol_resolver` functions, which lazily resolve the callee the first time they are called.

IFunc may have an optional [linkage type](#linkage), an optional [visibility style](BitCodeFormat.html#visibility), an option partition, and an optional list of attached [metadata](metadata.md#metadata).

Syntax:

    @<Name> = [Linkage] [PreemptionSpecifier] [Visibility] ifunc <IFuncTy>, <ResolverTy>* @<Resolver>
              [, partition "name"] (, !name !N)*

<a id="comdats"></a>

<a id="langref-comdats"></a>

### Comdats

Comdat IR provides access to object file COMDAT/section group functionality which represents interrelated sections.

Comdats have a name which represents the COMDAT key and a selection kind to provide input on how the linker deduplicates comdats with the same key in two different object files. A comdat must be included or omitted as a unit. Discarding the whole comdat is allowed but discarding a subset is not.

A global object may be a member of at most one comdat. Aliases are placed in the same COMDAT that their aliasee computes to, if any.

Syntax:

    $<Name> = comdat SelectionKind

For selection kinds other than `nodeduplicate`, only one of the duplicate comdats may be retained by the linker and the members of the remaining comdats must be discarded. The following selection kinds are supported:

`any`  
The linker may choose any COMDAT key, the choice is arbitrary.

`exactmatch`  
The linker may choose any COMDAT key but the sections must contain the same data.

`largest`  
The linker will choose the section containing the largest COMDAT key.

`nodeduplicate`  
No deduplication is performed.

`samesize`  
The linker may choose any COMDAT key but the sections must contain the same amount of data.

- XCOFF and Mach-O don’t support COMDATs.

- COFF supports all selection kinds. Non-`nodeduplicate` selection kinds need a non-local linkage COMDAT symbol.

- ELF supports `any` and `nodeduplicate`.

- WebAssembly only supports `any`.

Here is an example of a COFF COMDAT where a function will only be selected if the COMDAT key’s section is the largest:

    $foo = comdat largest
    @foo = global i32 2, comdat($foo)

    define void @bar() comdat($foo) {
      ret void
    }

In a COFF object file, this will create a COMDAT section with selection kind `IMAGE_COMDAT_SELECT_LARGEST` containing the contents of the `@foo` symbol and another COMDAT section with selection kind `IMAGE_COMDAT_SELECT_ASSOCIATIVE` which is associated with the first COMDAT section and contains the contents of the `@bar` symbol.

As a syntactic sugar the `$name` can be omitted if the name is the same as the global name:

    $foo = comdat any
    @foo = global i32 2, comdat
    @bar = global i32 3, comdat($foo)

There are some restrictions on the properties of the global object. It, or an alias to it, must have the same name as the COMDAT group when targeting COFF. The contents and size of this object may be used during link-time to determine which COMDAT groups get selected depending on the selection kind. Because the name of the object must match the name of the COMDAT group, the linkage of the global object must not be local; local symbols can get renamed if a collision occurs in the symbol table.

The combined use of COMDATS and section attributes may yield surprising results. For example:

    $foo = comdat any
    $bar = comdat any
    @g1 = global i32 42, section "sec", comdat($foo)
    @g2 = global i32 42, section "sec", comdat($bar)

From the object file perspective, this requires the creation of two sections with the same name. This is necessary because both globals belong to different COMDAT groups and COMDATs, at the object file level, are represented by sections.

Note that certain IR constructs like global variables and functions may create COMDATs in the object file in addition to any which are specified using COMDAT IR. This arises when the code generator is configured to emit globals in individual sections (e.g., when `-data-sections` or `-function-sections` is supplied to `llc`).

<a id="named-metadata"></a>

<a id="namedmetadatastructure"></a>

### Named Metadata

Named metadata is a collection of metadata. [Metadata nodes](metadata.md#metadata) (but not metadata strings) are the only valid operands for a named metadata.

1.  Named metadata are represented as a string of characters with the metadata prefix. The rules for metadata names are the same as for identifiers, but quoted names are not allowed. `"\xx"` type escapes are still valid, which allows any character to be part of a name.

Syntax:

    ; Some unnamed metadata nodes, which are referenced by the named metadata.
    !0 = !{!"zero"}
    !1 = !{!"one"}
    !2 = !{!"two"}
    ; A named metadata.
    !name = !{!0, !1, !2}

<a id="parameter-attributes"></a>

<a id="paramattrs"></a>

### Parameter Attributes

The return type and each parameter of a function type may have a set of *parameter attributes* associated with them. Parameter attributes are used to communicate additional information about the result or parameters of a function. Parameter attributes are considered to be part of the function, not of the function type, so functions with different parameter attributes can have the same function type. Parameter attributes can be placed both on function declarations/definitions, and at call-sites.

Parameter attributes are either simple keywords or strings that follow the specified type. Multiple parameter attributes, when required, are separated by spaces. For example:

    ; On function declarations/definitions:
    declare i32 @printf(ptr noalias captures(none), ...)
    declare i32 @atoi(i8 zeroext)
    declare signext i8 @returns_signed_char()
    define void @baz(i32 "amdgpu-flat-work-group-size"="1,256" %x)

    ; On call-sites:
    call i32 @atoi(i8 zeroext %x)
    call signext i8 @returns_signed_char()

Note that any attributes for the function result (`nonnull`, `signext`) come before the result type.

Parameter attributes can be broadly separated into two kinds: ABI attributes that affect how values are passed to/from functions, like `zeroext`, `inreg`, `byval`, or `sret`. And optimization attributes, which provide additional optimization guarantees, like `noalias`, `nonnull` and `dereferenceable`.

ABI attributes must be specified *both* at the function declaration/definition and call-site, otherwise the behavior may be undefined. ABI attributes cannot be safely dropped. Optimization attributes do not have to match between call-site and function: The intersection of their implied semantics applies. Optimization attributes can also be freely dropped.

If an integer argument to a function is not marked signext/zeroext/noext, the kind of extension used is target-specific. Some targets depend for correctness on the kind of extension to be explicitly specified.

Currently, only the following parameter attributes are defined:

`zeroext`  
This indicates to the code generator that the parameter or return value should be zero-extended to the extent required by the target’s ABI by the caller (for a parameter) or the callee (for a return value).

`signext`  
This indicates to the code generator that the parameter or return value should be sign-extended to the extent required by the target’s ABI (which is usually 32-bits) by the caller (for a parameter) or the callee (for a return value).

`noext`  
This indicates to the code generator that the parameter or return value has the high bits undefined, as for a struct in a register, and therefore does not need to be sign or zero extended. This is the same as default behavior and is only actually used (by some targets) to validate that one of the attributes is always present.

`inreg`  
This indicates that this parameter or return value should be treated in a special target-dependent fashion while emitting code for a function call or return (usually, by putting it in a register as opposed to memory, though some targets use it to distinguish between two different kinds of registers). Use of this attribute is target-specific.

`byval(<ty>)`  
This indicates that the pointer parameter should really be passed by value to the function. The attribute implies that a hidden copy of the pointee is made between the caller and the callee, so the callee is unable to modify the value in the caller. This attribute is only valid on LLVM pointer arguments. It is generally used to pass structs and arrays by value, but is also valid on pointers to scalars. The copy is considered to belong to the caller not the callee (for example, `readonly` functions should not write to `byval` parameters). This is not a valid attribute for return values.

The byval type argument is only used for its allocation size and alignment (if there is no explicit align attribute). That is, the hidden copy is interpreted as a call to memcpy with the allocation size of the specified type, instead of loading from the pointee and storing back into the copy in the type. In particular, the padding between field types of a struct type is still copied.

The byval attribute also supports specifying an alignment with the `align` attribute. It indicates the alignment of the stack slot to form and the known alignment of the pointer specified to the call site. If the alignment is not specified, then the code generator makes a target-specific assumption.

<a id="attr-byref"></a>

`byref(<ty>)`  
The `byref` argument attribute allows specifying the pointee memory type of an argument. This is similar to `byval`, but does not imply a copy is made anywhere, or that the argument is passed on the stack. This implies the pointer is dereferenceable up to the storage size of the type.

It is not generally permissible to introduce a write to a `byref` pointer. The pointer may have any address space and may be read only.

This is not a valid attribute for return values.

The alignment for a `byref` parameter can be explicitly specified by combining it with the `align` attribute, similar to `byval`. If the alignment is not specified, then the code generator makes a target-specific assumption.

This is intended for representing ABI constraints, and is not intended to be inferred for optimization use.

<a id="attr-preallocated"></a>

`preallocated(<ty>)`  
This indicates that the pointer parameter should really be passed by value to the function, and that the pointer parameter’s pointee has already been initialized before the call instruction. This attribute is only valid on LLVM pointer arguments. The argument must be the value returned by the appropriate [llvm.call.preallocated.arg](intrinsics-overview-and-basic.md#int-call-preallocated-arg) on non `musttail` calls, or the corresponding caller parameter in `musttail` calls, although it is ignored during codegen.

A non `musttail` function call with a `preallocated` attribute in any parameter must have a `"preallocated"` operand bundle. A `musttail` function call cannot have a `"preallocated"` operand bundle.

The preallocated attribute requires a type argument.

The preallocated attribute also supports specifying an alignment with the `align` attribute. It indicates the alignment of the stack slot to form and the known alignment of the pointer specified to the call site. If the alignment is not specified, then the code generator makes a target-specific assumption.

<a id="attr-inalloca"></a>

`inalloca(<ty>)`  
The `inalloca` argument attribute allows the caller to take the address of outgoing stack arguments. An `inalloca` argument must be a pointer to stack memory produced by an `alloca` instruction. The alloca, or argument allocation, must also be tagged with the inalloca keyword. Only the last argument may have the `inalloca` attribute, and that argument is guaranteed to be passed in memory.

An argument allocation may be used by a call at most once because the call may deallocate it. The `inalloca` attribute cannot be used in conjunction with other attributes that affect argument storage, like `inreg`, `nest`, `sret`, or `byval`. The `inalloca` attribute also disables LLVM’s implicit lowering of large aggregate return values, which means that frontend authors must lower them with `sret` pointers.

When the call site is reached, the argument allocation must have been the most recent stack allocation that is still live, or the behavior is undefined. It is possible to allocate additional stack space after an argument allocation and before its call site, but it must be cleared off with [llvm.stackrestore](intrinsics-overview-and-basic.md#int-stackrestore).

The `inalloca` attribute requires a type argument.

See [Design and Usage of the InAlloca Attribute](InAlloca.html) for more information on how to use this attribute.

`sret(<ty>)`  
This indicates that the pointer parameter specifies the address of a structure that is the return value of the function in the source program. This pointer must be guaranteed by the caller to be valid: loads and stores to the structure may be assumed by the callee not to trap and to be properly aligned.

The sret type argument specifies the in-memory type.

A function that accepts an `sret` argument must return `void`. A return value may not be `sret`.

<a id="attr-elementtype"></a>

`elementtype(<ty>)`  
The `elementtype` argument attribute can be used to specify a pointer element type in a way that is compatible with [opaque pointers](OpaquePointers.html).

The `elementtype` attribute by itself does not carry any specific semantics. However, certain intrinsics may require this attribute to be present and assign it particular semantics. This will be documented on individual intrinsics.

The attribute may only be applied to pointer typed arguments or return values of intrinsic calls. It cannot be applied to non-intrinsic calls, and cannot be applied to parameters on function declarations. For non-opaque pointers, the type passed to `elementtype` must match the pointer element type.

<a id="attr-align"></a>

`align <n>` or `align(<n>)`  
This indicates that the pointer value or vector of pointers has the specified alignment. If applied to a vector of pointers, *all* pointers (elements) have the specified alignment. If the pointer value does not have the specified alignment, [poison value](constants.md#poisonvalues) is returned or passed instead. The `align` attribute should be combined with the `noundef` attribute to ensure a pointer is aligned, or otherwise the behavior is undefined. Note that `align 1` has no effect on non-byval, non-preallocated arguments.

Note that this attribute has additional semantics when combined with the `byval` or `preallocated` attribute, which are documented there.

<a id="noalias"></a>

`noalias`  
This indicates that memory locations accessed via pointer values [based](#pointeraliasing) on the argument or return value are not also accessed, during the execution of the function, via pointer values not *based* on the argument or return value. This guarantee only holds for memory locations that are *modified*, by any means, during the execution of the function. If there are other accesses not based on the argument or return value, the behavior is undefined. The attribute on a return value also has additional semantics, as described below. Both the caller and the callee share the responsibility of ensuring that these requirements are met. For further details, please see the discussion of the NoAlias response in [alias analysis](AliasAnalysis.html#must-may-or-no).

Note that this definition of `noalias` is intentionally similar to the definition of `restrict` in C99 for function arguments.

For function return values, C99’s `restrict` is not meaningful, while LLVM’s `noalias` is. Furthermore, the semantics of the `noalias` attribute on return values are stronger than the semantics of the attribute when used on function arguments. On function return values, the `noalias` attribute indicates that the function acts like a system memory allocation function, returning a pointer to allocated storage disjoint from the storage for any other object accessible to the caller.

<a id="captures-attr"></a>

`captures(...)`  
This attribute restricts the ways in which the callee may capture the pointer. This is not a valid attribute for return values. This attribute applies only to the particular copy of the pointer passed in this argument.

The arguments of `captures` are a list of captured pointer components, which may be `none`, or a combination of:

- `address`: The integral address of the pointer.

- `address_is_null` (subset of `address`): Whether the address is null.

- `provenance`: The ability to access the pointer for both read and write after the function returns.

- `read_provenance` (subset of `provenance`): The ability to access the pointer only for reads after the function returns.

Additionally, it is possible to specify that some components are only captured in certain locations. Currently only the return value (`ret`) and other (default) locations are supported.

The [pointer capture section](#pointercapture) discusses these semantics in more detail.

Some examples of how to use the attribute:

- `captures(none)`: Pointer not captured.

- `captures(address, provenance)`: Equivalent to omitting the attribute.

- `captures(address)`: Address may be captured, but not provenance.

- `captures(address_is_null)`: Only captures whether the address is null.

- `captures(address, read_provenance)`: Both address and provenance captured, but only for read-only access.

- `captures(ret: address, provenance)`: Pointer captured through return value only.

- `captures(address_is_null, ret: address, provenance)`: The whole pointer is captured through the return value, and additionally whether the pointer is null is captured in some other way.

`nofree`  
This indicates that a pointer based on this argument cannot be freed during the execution of the function.

More formally, a `nofree` argument provides the callee with a new pointer with the same address and a derived provenance, where the derived provenance has the same permissions as the original, except that the underlying object cannot be freed until the function returns (or unwinds), otherwise the behavior is undefined. This includes frees of the pointer on other threads if the free *happens-before* the function return.

Notably, it is still possible to free the underlying object through a pointer that is not based on the argument.

This is not a valid attribute for return values.

<a id="nest"></a>

`nest`  
This indicates that the pointer parameter can be excised using the [trampoline intrinsics](intrinsics-general.md#int-trampoline). This is not a valid attribute for return values and can only be applied to one parameter.

`returned`  
This indicates that the function always returns the argument as its return value. This is a hint to the optimizer and code generator used when generating the caller, allowing value propagation, tail call optimization, and omission of register saves and restores in some cases; it is not checked or enforced when generating the callee. The parameter and the function return type must be valid operands for the [bitcast instruction](instructions-conversion.md#i-bitcast). This is not a valid attribute for return values and can only be applied to one parameter.

<a id="attr-nonnull"></a>

`nonnull`  
This indicates that the parameter or return pointer is not null. This attribute may only be applied to pointer-typed parameters. This is not checked or enforced by LLVM; if the parameter or return pointer is null, [poison value](constants.md#poisonvalues) is returned or passed instead. The `nonnull` attribute only refers to the address bits of the pointers. If all the address bits are zero, the result will be a poison value, even if the pointer has non-zero non-address bits or non-zero external state. The `nonnull` attribute should be combined with the `noundef` attribute to ensure a pointer is not null or otherwise the behavior is undefined.

<a id="attr-dereferenceable"></a>

`dereferenceable(<n>)`  
This indicates that the parameter or return pointer is dereferenceable. This attribute may only be applied to pointer-typed parameters. A pointer that is dereferenceable can be loaded from speculatively without a risk of trapping. The number of bytes known to be dereferenceable must be provided in parentheses. The `nonnull` attribute does not imply dereferenceability (consider a pointer to one element past the end of an array), however `dereferenceable(<n>)` does imply `nonnull` in `addrspace(0)` (which is the default address space), except if the `null_pointer_is_valid` function attribute is present. `n` should be a positive number. The pointer should be well defined, otherwise it is undefined behavior. This means `dereferenceable(<n>)` implies `noundef`.

The `dereferenceable` attribute only implies dereferenceability at the point of the attribute (i.e. on function entry for arguments or at the point of the call for return values). The underlying object may still get freed after that point. Other attributes such as `nofree` can be used to exclude frees.

<a id="attr-dereferenceable-or-null"></a>

`dereferenceable_or_null(<n>)`  
This indicates that the parameter or return value isn’t both non-null and non-dereferenceable (up to `<n>` bytes) at the same time. All non-null pointers tagged with `dereferenceable_or_null(<n>)` are `dereferenceable(<n>)`. For address space 0 `dereferenceable_or_null(<n>)` implies that a pointer is exactly one of `dereferenceable(<n>)` or `null`, and in other address spaces `dereferenceable_or_null(<n>)` implies that a pointer is at least one of `dereferenceable(<n>)` or `null` (i.e., it may be both `null` and `dereferenceable(<n>)`). This attribute may only be applied to pointer-typed parameters.

`swiftself`  
This indicates that the parameter is the self/context parameter. This is not a valid attribute for return values and can only be applied to one parameter.

<a id="swiftasync"></a>

`swiftasync`  
This indicates that the parameter is the asynchronous context parameter and triggers the creation of a target-specific extended frame record to store this pointer. This is not a valid attribute for return values and can only be applied to one parameter.

`swifterror`  
This attribute is motivated to model and optimize Swift error handling. It can be applied to a parameter with pointer-to-pointer type or a pointer-sized alloca. At the call site, the actual argument that corresponds to a `swifterror` parameter has to come from a `swifterror` alloca or the `swifterror` parameter of the caller. A `swifterror` value (either the parameter or the alloca) can only be loaded and stored from, or used as a `swifterror` argument. This is not a valid attribute for return values and can only be applied to one parameter.

These constraints allow the calling convention to optimize access to `swifterror` variables by associating them with a specific register at call boundaries rather than placing them in memory. Since this does change the calling convention, a function which uses the `swifterror` attribute on a parameter is not ABI-compatible with one which does not.

These constraints also allow LLVM to assume that a `swifterror` argument does not alias any other memory visible within a function and that a `swifterror` alloca passed as an argument does not escape.

`immarg`  
This indicates the parameter is required to be an immediate value. This must be a trivial immediate integer or floating-point constant. Undef or constant expressions are not valid. This is only valid on intrinsic declarations and cannot be applied to a call site or arbitrary function.

<a id="attr-noundef"></a>

`noundef`  
This attribute applies to parameters and return values. If the value representation contains any undefined or poison bits, the behavior is undefined. Note that this does not refer to padding introduced by the type’s storage representation.

If memory sanitizer is enabled, `noundef` becomes an ABI attribute and must match between the call-site and the function definition.

<a id="nofpclass"></a>

`nofpclass(<test mask>)`  
This attribute applies to parameters and return values with floating-point and vector of floating-point types, as well as [supported aggregates](#fastmath-return-types) of such types (matching the supported types for [fast-math flags](#fastmath)). The test mask has the same format as the second argument to the [llvm.is.fpclass](intrinsics-floating-point.md#llvm-is-fpclass), and indicates which classes of floating-point values are not permitted for the value. For example, a bitmask of 3 indicates the parameter may not be a NaN.

If the value is a floating-point class indicated by the `nofpclass` test mask, a [poison value](constants.md#poisonvalues) is passed or returned instead.

<a id="id2012"></a>

The following invariants hold

    @llvm.is.fpclass(nofpclass(test_mask) %x, test_mask) => false
    @llvm.is.fpclass(nofpclass(test_mask) %x, ~test_mask) => true
    nofpclass(all) => poison

In textual IR, various string names are supported for readability and can be combined. For example `nofpclass(nan pinf nzero)` evaluates to a mask of 547.

This does not depend on the floating-point environment. For example, a function parameter marked `nofpclass(zero)` indicates no zero inputs. If this is applied to an argument in a function marked with [denormal_fpenv](#denormal-fpenv) indicating zero treatment of input denormals, it does not imply the value cannot be a denormal value which would compare equal to 0.

Recognized test mask names:

| Name  | floating-point class | Bitmask value |
|-------|----------------------|---------------|
| nan   | Any NaN              | 3             |
| inf   | +/- infinity         | 516           |
| norm  | +/- normal           | 264           |
| sub   | +/- subnormal        | 144           |
| zero  | +/- 0                | 96            |
| all   | All values           | 1023          |
| snan  | Signaling NaN        | 1             |
| qnan  | Quiet NaN            | 2             |
| ninf  | Negative infinity    | 4             |
| nnorm | Negative normal      | 8             |
| nsub  | Negative subnormal   | 16            |
| nzero | Negative zero        | 32            |
| pzero | Positive zero        | 64            |
| psub  | Positive subnormal   | 128           |
| pnorm | Positive normal      | 256           |
| pinf  | Positive infinity    | 512           |

`alignstack(<n>)`  
This indicates the alignment that should be considered by the backend when assigning this parameter or return value to a stack slot during calling convention lowering. The enforcement of the specified alignment is target-dependent, as target-specific calling convention rules may override this value. This attribute serves the purpose of carrying language-specific alignment information that is not mapped to base types in the backend (for example, over-alignment specification through language attributes).

`allocalign`  
The function parameter marked with this attribute is the alignment in bytes of the newly allocated block returned by this function. The returned value must either have the specified alignment or be the null pointer. The return value MAY be more aligned than the requested alignment, but not less aligned. Invalid (e.g., non-power-of-2) alignments are permitted for the allocalign parameter, so long as the returned pointer is null. This attribute may only be applied to integer parameters.

`allocptr`  
The function parameter marked with this attribute is the pointer that will be manipulated by the allocator. For a realloc-like function the pointer will be invalidated upon success (but the same address may be returned), for a free-like function the pointer will always be invalidated.

`readnone`  
This attribute indicates that the function does not dereference that pointer argument, even though it may read or write the memory that the pointer points to if accessed through other pointers.

If a function reads from or writes to a readnone pointer argument, the behavior is undefined.

`readonly`  
This attribute indicates that the function does not write through this pointer argument, even though it may write to the memory that the pointer points to.

If a function writes to a readonly pointer argument, the behavior is undefined.

`writeonly`  
This attribute indicates that the function may write to, but does not read through this pointer argument (even though it may read from the memory that the pointer points to).

This attribute is understood in the same way as the `memory(write)` attribute. That is, the pointer may still be read as long as the read is not observable outside the function. See the `memory` documentation for precise semantics.

`writable`  
This attribute is only meaningful in conjunction with `dereferenceable(N)` or another attribute that implies the first `N` bytes of the pointer argument are dereferenceable.

In that case, the attribute indicates that the first `N` bytes will be (non-atomically) loaded and stored back on entry to the function.

This implies that it’s possible to introduce spurious stores on entry to the function without introducing traps or data races. This does not necessarily hold throughout the whole function, as the pointer may escape to a different thread during the execution of the function. See also the [atomic optimization guide](Atomics.html#optimization-outside-atomic)

The “other attributes” that imply dereferenceability are `dereferenceable_or_null` (if the pointer is non-null) and the `sret`, `byval`, `byref`, `inalloca`, `preallocated` family of attributes. Note that not all of these combinations are useful, e.g. `byval` arguments are known to be writable even without this attribute.

The `writable` attribute cannot be combined with `readnone`, `readonly` or a `memory` attribute that does not contain `argmem: write`.

`initializes((Lo1, Hi1), ...)`  
This attribute indicates that the function initializes the ranges of the pointer parameter’s memory `[%p+LoN, %p+HiN)`. Colloquially, this means that all bytes in the specified range are written before the function returns, and not read prior to the initializing write. If the function unwinds, the write may not happen.

Formally, this is specified in terms of an “initialized” shadow state for all bytes in the range, which is set to “not initialized” at function entry. If a memory access is performed through a pointer based on the argument, and an accessed byte has not been marked as “initialized” yet, then:

- If the byte is stored with a non-volatile, non-atomic write, mark it as “initialized”.

- If the byte is stored with a volatile or atomic write, the behavior is undefined.

- If the byte is loaded, return a poison value.

Additionally, if the function returns normally, write an undef value to all bytes that are part of the range and have not been marked as “initialized”.

This attribute only holds for the memory accessed via this pointer parameter. Other arbitrary accesses to the same memory via other pointers are allowed.

The `writable` or `dereferenceable` attribute do not imply the `initializes` attribute. The `initializes` attribute does not imply `writeonly` since `initializes` allows reading from the pointer after writing.

This attribute is a list of constant ranges in ascending order with no overlapping or consecutive list elements. `LoN/HiN` are 64-bit integers, and negative values are allowed in case the argument points partway into an allocation. An empty list is not allowed.

On a `byval` argument, `initializes` refers to the given parts of the callee copy being overwritten. A `byval` callee can never initialize the original caller memory passed to the `byval` argument.

`dead_on_unwind`  
At a high level, this attribute indicates that the pointer argument is dead if the call unwinds, in the sense that the caller will not depend on the contents of the memory. Stores that would only be visible on the unwind path can be elided.

More precisely, the behavior is as-if any memory written through the pointer during the execution of the function is overwritten with a poison value on unwind. This includes memory written by the implicit write implied by the `writable` attribute. The caller is allowed to access the affected memory, but all loads that are not preceded by a store will return poison.

This attribute cannot be applied to return values.

`dead_on_return` or `dead_on_return(<n>)`  
This attribute indicates that the memory pointed to by the argument is dead upon function return, both upon normal return and if the calls unwinds, meaning that the caller will not depend on its contents. Stores that would be observable either on the return path or on the unwind path may be elided. A number of bytes known to be dead may optionally be provided in parentheses. If a number of bytes is not specified, all memory reachable through the pointer is marked as dead on return.

Specifically, the behavior is as-if any memory written through the pointer during the execution of the function is overwritten with a poison value upon function return. The caller may access the memory, but any load not preceded by a store will return poison. If a byte count is specified, only writes within the specified range are overwritten with poison on function return.

This attribute does not imply aliasing properties. For pointer arguments that do not alias other memory locations, `noalias` attribute may be used in conjunction. Conversely, this attribute always implies `dead_on_unwind`. When a byte count is specified, `dead_on_unwind` is implied only for that range.

This attribute cannot be applied to return values.

`range(<ty> <a>, <b>)`  
This attribute expresses the possible range of the parameter or return value. If the value is not in the specified range, it is converted to poison. The arguments passed to `range` have the following properties:

- The type must match the scalar type of the parameter or return value.

- The pair `a,b` represents the range `[a,b)`.

- Both `a` and `b` are constants.

- The range is allowed to wrap.

- The empty range is represented using `0,0`.

- Otherwise, `a` and `b` are not allowed to be equal.

This attribute may only be applied to parameters or return values with integer or vector of integer types.

For vector-typed parameters, the range is applied element-wise.

<a id="garbage-collector-strategy-names"></a>

<a id="gc"></a>

### Garbage Collector Strategy Names

Each function may specify a garbage collector strategy name, which is simply a string:

    define void @f() gc "name" { ... }

The supported values of *name* include those [built in to LLVM](GarbageCollection.html#builtin-gc-strategies) and any provided by loaded plugins. Specifying a GC strategy will cause the compiler to alter its output in order to support the named garbage collection algorithm. Note that LLVM itself does not contain a garbage collector, this functionality is restricted to generating machine code which can interoperate with a collector provided externally.

<a id="prefix-data"></a>

<a id="prefixdata"></a>

### Prefix Data

Prefix data is data associated with a function which the code generator will emit immediately before the function’s entrypoint. The purpose of this feature is to allow frontends to associate language-specific runtime metadata with specific functions and make it available through the function pointer while still allowing the function pointer to be called.

To access the data for a given function, a program may bitcast the function pointer to a pointer to the constant’s type and dereference index -1. This implies that the IR symbol points just past the end of the prefix data. For instance, take the example of a function annotated with a single `i32`,

    define void @f() prefix i32 123 { ... }

The prefix data can be referenced as,

    %a = getelementptr inbounds i32, ptr @f, i32 -1
    %b = load i32, ptr %a

Prefix data is laid out as if it were an initializer for a global variable of the prefix data’s type. The function will be placed such that the beginning of the prefix data is aligned. This means that if the size of the prefix data is not a multiple of the alignment size, the function’s entrypoint will not be aligned. If alignment of the function’s entrypoint is desired, padding must be added to the prefix data.

A function may have prefix data but no body. This has similar semantics to the `available_externally` linkage in that the data may be used by the optimizers but will not be emitted in the object file.

<a id="prologue-data"></a>

<a id="prologuedata"></a>

### Prologue Data

The `prologue` attribute allows arbitrary code (encoded as bytes) to be inserted prior to the function body. This can be used for enabling function hot-patching and instrumentation.

To maintain the semantics of ordinary function calls, the prologue data must have a particular format. Specifically, it must begin with a sequence of bytes which decode to a sequence of machine instructions, valid for the module’s target, which transfer control to the point immediately succeeding the prologue data, without performing any other visible action. This allows the inliner and other passes to reason about the semantics of the function definition without needing to reason about the prologue data. Obviously this makes the format of the prologue data highly target dependent.

A trivial example of valid prologue data for the x86 architecture is `i8 144`, which encodes the `nop` instruction:

    define void @f() prologue i8 144 { ... }

Generally prologue data can be formed by encoding a relative branch instruction which skips the metadata, as in this example of valid prologue data for the x86_64 architecture, where the first two bytes encode `jmp .+10`:

    %0 = type <{ i8, i8, ptr }>

    define void @f() prologue %0 <{ i8 235, i8 8, ptr @md}> { ... }

A function may have prologue data but no body. This has similar semantics to the `available_externally` linkage in that the data may be used by the optimizers but will not be emitted in the object file.

<a id="personality-function"></a>

<a id="personalityfn"></a>

### Personality Function

The `personality` attribute permits functions to specify what function to use for exception handling.

<a id="attribute-groups"></a>

<a id="attrgrp"></a>

### Attribute Groups

Attribute groups are groups of attributes that are referenced by objects within the IR. They are important for keeping `.ll` files readable, because a lot of functions will use the same set of attributes. In the degenerate case of a `.ll` file that corresponds to a single `.c` file, the single attribute group will capture the important command line flags used to build that file.

An attribute group is a module-level object. To use an attribute group, an object references the attribute group’s ID (e.g., `#37`). An object may refer to more than one attribute group. In that situation, the attributes from the different groups are merged.

Here is an example of attribute groups for a function that should always be inlined, has a stack alignment of 4, and which shouldn’t use SSE instructions:

    ; Target-independent attributes:
    attributes #0 = { alwaysinline alignstack=4 }

    ; Target-dependent attributes:
    attributes #1 = { "no-sse" }

    ; Function @f has attributes: alwaysinline, alignstack=4, and "no-sse".
    define void @f() #0 #1 { ... }

<a id="function-attributes"></a>

<a id="fnattrs"></a>

### Function Attributes

Function attributes are set to communicate additional information about a function. Function attributes are considered to be part of the function, not of the function type, so functions with different function attributes can have the same function type.

Function attributes are simple keywords or strings that follow the specified type. Multiple attributes, when required, are separated by spaces. For example:

    define void @f() noinline { ... }
    define void @f() alwaysinline { ... }
    define void @f() alwaysinline optsize { ... }
    define void @f() optsize { ... }
    define void @f() "no-sse" { ... }

`alignstack(<n>)`  
This attribute indicates that, when emitting the prologue and epilogue, the backend should forcibly align the stack pointer. Specify the desired alignment, which must be a power of two, in parentheses.

`"alloc-family"="FAMILY"`  
This indicates which “family” an allocator function is part of. To avoid collisions, the family name should match the mangled name of the primary allocator function, that is “malloc” for malloc/calloc/realloc/free, “\_Znwm” for `::operator::new` and `::operator::delete`, and “\_ZnwmSt11align_val_t” for aligned `::operator::new` and `::operator::delete`. Matching malloc/realloc/free calls within a family can be optimized, but mismatched ones will be left alone.

`allockind("KIND")`  
Describes the behavior of an allocation function. The KIND string contains comma-separated entries from the following options:

- “alloc”: the function returns a new block of memory or null.

- “realloc”: the function returns a new block of memory or null. If the result is non-null the memory contents from the start of the block up to the smaller of the original allocation size and the new allocation size will match that of the `allocptr` argument and the `allocptr` argument is invalidated, even if the function returns the same address.

- “free”: the function frees the block of memory specified by `allocptr`. Functions marked as “free” `allockind` must return void.

- “uninitialized”: Any newly-allocated memory (either a new block from a “alloc” function or the enlarged capacity from a “realloc” function) will be uninitialized.

- “zeroed”: Any newly-allocated memory (either a new block from a “alloc” function or the enlarged capacity from a “realloc” function) will be zeroed.

- “aligned”: the function returns memory aligned according to the `allocalign` parameter.

The first three options are mutually exclusive, and the remaining options describe more details of how the function behaves. The remaining options are invalid for “free”-type functions.

Calls to functions annotated with `allockind` are subject to allocation elision: Calls to allocator functions can be removed, and the allocation served from a “virtual” allocator instead. Notably, this is allowed even if the allocator calls have side-effects. In other words, for each allocation there is a non-deterministic choice between calling the allocator as usual, or using a virtual, side-effect-free allocator instead.

If multiple allocation functions operate on the same allocation, allocation elision is only allowed for pairs of “alloc” and “free” with the same `"alloc-family"` attribute. For this purpose, a “realloc” call may be decomposed into “alloc” and “free” operations, as long as at least one of them will be elided.

`"alloc-variant-zeroed"="FUNCTION"`  
This attribute indicates that another function is equivalent to an allocator function, but returns zeroed memory. The function must have “zeroed” allocation behavior, the same `alloc-family`, and take exactly the same arguments.

`allocsize(<EltSizeParam>[, <NumEltsParam>])`  
This attribute indicates that the annotated function will always return at least a given number of bytes (or null). Its arguments are zero-indexed parameter numbers; if one argument is provided, then it’s assumed that at least `CallSite.Args[EltSizeParam]` bytes will be available at the returned pointer. If two are provided, then it’s assumed that `CallSite.Args[EltSizeParam] * CallSite.Args[NumEltsParam]` bytes are available. The referenced parameters must be integer types. No assumptions are made about the contents of the returned block of memory.

`alwaysinline`  
This attribute indicates that the inliner should attempt to inline this function into callers whenever possible, ignoring any active inlining size threshold for this caller.

`builtin`  
This indicates that the callee function at a call site should be recognized as a built-in function, even though the function’s declaration uses the `nobuiltin` attribute. This is only valid at call sites for direct calls to functions that are declared with the `nobuiltin` attribute.

<a id="attr-cold"></a>

`cold`  
This attribute indicates that this function is rarely called. When computing edge weights, basic blocks post-dominated by a cold function call are also considered to be cold and, thus, given a low weight.

<a id="attr-convergent"></a>

`convergent`  
This attribute indicates that this function is convergent. When it appears on a call/invoke, the convergent attribute indicates that we should treat the call as though we’re calling a convergent function. This is particularly useful on indirect calls; without this we may treat such calls as though the target is non-convergent.

See [Convergent Operation Semantics](ConvergentOperations.html) for further details.

It is an error to call [llvm.experimental.convergence.entry](ConvergentOperations.html#llvm-experimental-convergence-entry) from a function that does not have this attribute.

`disable_sanitizer_instrumentation`  
When instrumenting code with sanitizers, it can be important to skip certain functions to ensure no instrumentation is applied to them.

This attribute is not always similar to absent `sanitize_<name>` attributes: depending on the specific sanitizer, code can be inserted into functions regardless of the `sanitize_<name>` attribute to prevent false positive reports.

`disable_sanitizer_instrumentation` disables all kinds of instrumentation, taking precedence over the `sanitize_<name>` attributes and other compiler flags.

`"dontcall-error"`  
This attribute denotes that an error diagnostic should be emitted when a call of a function with this attribute is not eliminated via optimization. Front ends can provide optional `srcloc` metadata nodes on call sites of such callees to attach information about where in the source language such a call came from. A string value can be provided as a note.

`"dontcall-warn"`  
This attribute denotes that a warning diagnostic should be emitted when a call of a function with this attribute is not eliminated via optimization. Front ends can provide optional `srcloc` metadata nodes on call sites of such callees to attach information about where in the source language such a call came from. A string value can be provided as a note.

`fn_ret_thunk_extern`  
This attribute tells the code generator that returns from functions should be replaced with jumps to externally-defined architecture-specific symbols. For X86, this symbol’s identifier is `__x86_return_thunk`.

`"frame-pointer"`  
This attribute tells the code generator whether the function should keep the frame pointer. The code generator may emit the frame pointer even if this attribute says the frame pointer can be eliminated. The allowed string values are:

- `"none"` (default) - the frame pointer can be eliminated, and its register can be used for other purposes.

- `"reserved"` - the frame pointer register must either be updated to point to a valid frame record for the current function, or not be modified.

- `"non-leaf"` - the frame pointer should be kept if the function calls other functions.

- `"all"` - the frame pointer should be kept.

`hot`  
This attribute indicates that this function is a hot spot of the program execution. The function will be optimized more aggressively and will be placed into a special subsection of the text section to improve locality.

When profile feedback is enabled, this attribute takes precedence over the profile information. By marking a function `hot`, users can work around the cases where the training input does not have good coverage on all the hot functions.

`inlinehint`  
This attribute indicates that the source code contained a hint that inlining this function is desirable (such as the “inline” keyword in C/C++). It is just a hint; it imposes no requirements on the inliner.

`jumptable`  
This attribute indicates that the function should be added to a jump-instruction table at code-generation time, and that all address-taken references to this function should be replaced with a reference to the appropriate jump-instruction-table function pointer. Note that this creates a new pointer for the original function, which means that code that depends on function-pointer identity can break. So, any function annotated with `jumptable` must also be `unnamed_addr`.

`memory(...)`  
This attribute specifies the possible memory effects of the call-site or function. It allows specifying the possible access kinds (`none`, `read`, `write`, or `readwrite`) for the possible memory location kinds (`argmem`, `inaccessiblemem`, `errnomem`, `target_mem0`, `target_mem1`, as well as a default). It is best understood by example:

- `memory(none)`: Does not access any memory.

- `memory(read)`: May read (but not write) any memory.

- `memory(write)`: May write (but not read) any memory.

- `memory(readwrite)`: May read or write any memory.

- `memory(argmem: read)`: May only read argument memory.

- `memory(argmem: read, inaccessiblemem: write)`: May only read argument memory and only write inaccessible memory.

- `memory(argmem: read, errnomem: write)`: May only read argument memory and only write errno.

- `memory(read, argmem: readwrite)`: May read any memory (default mode) and additionally write argument memory.

- `memory(readwrite, argmem: none)`: May access any memory apart from argument memory.

The supported access kinds are:

- `readwrite`: Any kind of access to the location is allowed.

- `read`: The location is only read. Writing to the location is immediate undefined behavior. This includes the case where the location is read from and then the same value is written back.

- `write`: Only writes to the location are observable outside the function call. However, the function may still internally read the location after writing it, as this is not observable. Reading the location prior to writing it results in a poison value.

- `none`: No reads or writes to the location are observed outside the function. It is always valid to read and write allocas, and to read global constants, even if `memory(none)` is used, as these effects are not externally observable.

The supported memory location kinds are:

- `argmem`: This refers to accesses that are based on pointer arguments to the function.

- `inaccessiblemem`: This refers to accesses to memory which is not accessible by the current module (before return from the function – an allocator function may return newly accessible memory while only accessing inaccessible memory itself). Inaccessible memory is often used to model control dependencies of intrinsics.

- `errnomem`: This refers to accesses to the `errno` variable.

- `target_mem#` : These refer to target specific state that cannot be accessed by any other means. \# is a number between 0 and 1 inclusive. Note: The following target_mem locations are implemented in AArch64. target_mem0 represents SME ZT0 state, target_mem1 represents SME ZA state.

- The default access kind (specified without a location prefix) applies to all locations that haven’t been specified explicitly, including those that don’t currently have a dedicated location kind (e.g., accesses to globals or captured pointers).

If the `memory` attribute is not specified, then `memory(readwrite)` is implied (all memory effects are possible).

The memory effects of a call can be computed as `CallSiteEffects & (FunctionEffects | OperandBundleEffects)`. Thus, the call-site annotation takes precedence over the potential effects described by either the function annotation or the operand bundles.

`minsize`  
This attribute suggests that optimization passes and code generator passes make choices that keep the code size of this function as small as possible and perform optimizations that may sacrifice runtime performance in order to minimize the size of the generated code. This attribute is incompatible with the `optdebug` and `optnone` attributes.

`naked`  
This attribute disables prologue / epilogue emission for the function. This can have very system-specific consequences. The arguments of a `naked` function can not be referenced through IR values.

`"no-inline-line-tables"`  
When this attribute is set to true, the inliner discards source locations when inlining code and instead uses the source location of the call site. Breakpoints set on code that was inlined into the current function will not fire during the execution of the inlined call sites. If the debugger stops inside an inlined call site, it will appear to be stopped at the outermost inlined call site.

`no-jump-tables`  
When this attribute is set to true, the jump tables and lookup tables that can be generated from a switch case lowering are disabled.

`nobuiltin`  
This indicates that the callee function at a call site is not recognized as a built-in function. LLVM will retain the original call and not replace it with equivalent code based on the semantics of the built-in function, unless the call site uses the `builtin` attribute. This is valid at call sites and on function declarations and definitions.

`nocallback`  
This attribute indicates that the function is only allowed to jump back into the caller’s module by a return or an exception, and is not allowed to jump back by invoking a callback function, a direct, possibly transitive, external function call, use of `longjmp`, or other means. It is a compiler hint that is used at the module level to improve dataflow analysis, dropped during linking, and has no effect on functions defined in the current module.

`nodivergencesource`  
A call to this function is not a source of divergence. In uniformity analysis, a *source of divergence* is an instruction that generates divergence even if its inputs are uniform. A call with no further information would normally be considered a source of divergence; setting this attribute on a function means that a call to it is not a source of divergence.

`noduplicate`  
This attribute indicates that calls to the function cannot be duplicated. A call to a `noduplicate` function may be moved within its parent function, but may not be duplicated within its parent function.

A function containing a `noduplicate` call may still be an inlining candidate, provided that the call is not duplicated by inlining. That implies that the function has internal linkage and only has one call site, so the original call is dead after inlining.

`nofree`  
This function attribute indicates that the function does not free any memory allocation which existed before the call, either through direct calls to a memory-deallocation function like `free`, or through synchronization. Freeing through synchronization here means that a deallocation *happens-before* the function exit but does not *happens-before* the function entry.

As a result, pointers that are known to be dereferenceable prior to a call to a function with the `nofree` attribute are still known to be dereferenceable after the call.

A `nofree` function is explicitly allowed to free memory which it allocated or arrange for another thread to free such memory on its behalf. As a result, perhaps surprisingly, a `nofree` function can return a pointer to a previously deallocated [allocated object](#allocatedobjects).

`noimplicitfloat`  
Disallows implicit floating-point code. This inhibits optimizations that use floating-point code and floating-point registers for operations that are not nominally floating-point. LLVM instructions that perform floating-point operations or require access to floating-point registers may still cause floating-point code to be generated.

Also inhibits optimizations that create SIMD/vector code and registers from scalar code such as vectorization or memcpy/memset optimization. This includes integer vectors. Vector instructions present in IR may still cause vector code to be generated.

`noinline`  
This attribute indicates that the inliner should never inline this function in any situation. This attribute may not be used together with the `alwaysinline` attribute.

`noipa`  
Disables any interprocedural analysis that inspects the definition of this function. This attribute is equivalent to moving this function definition to a separate, optimizer-opaque, module. Any attributes on the function are still respected (as they would be if they remained on a function declaration in this module). This attribute does *not* control inlining or outlining. Add the `noinline` and `nooutline` attributes as well in cases where inlining and outlining should additionally be disabled.

`nomerge`  
This attribute indicates that calls to this function should never be merged during optimization. For example, it will prevent tail merging otherwise identical code sequences that raise an exception or terminate the program. Tail merging normally reduces the precision of source location information, making stack traces less useful for debugging. This attribute gives the user control over the tradeoff between code size and debug information precision.

`nonlazybind`  
This attribute suppresses lazy symbol binding for the function. This may make calls to the function faster, at the cost of extra program startup time if the function is not called during program startup.

`noprofile`  
This function attribute prevents instrumentation-based profiling, used for coverage or profile based optimization, from being added to a function. It also blocks inlining if the caller and callee have different values of this attribute.

`skipprofile`  
This function attribute prevents instrumentation-based profiling, used for coverage or profile based optimization, from being added to a function. This attribute does not restrict inlining, so instrumented instructions could end up in this function.

`noredzone`  
This attribute indicates that the code generator should not use a red zone, even if the target-specific ABI normally permits it.

`indirect-tls-seg-refs`  
This attribute indicates that the code generator should not use direct TLS access through segment registers, even if the target-specific ABI normally permits it.

`noreturn`  
This function attribute indicates that the function never returns normally, hence through a return instruction. This produces undefined behavior at runtime if the function ever does dynamically return. Annotated functions may still raise an exception, i.a., `nounwind` is not implied.

`norecurse`  
This function attribute indicates that the function is not recursive and does not participate in recursion. This means that the function never occurs inside a cycle in the dynamic call graph. For example:

    fn -> other_fn -> fn       ; fn is not norecurse
    other_fn -> fn -> other_fn ; fn is not norecurse
    fn -> other_fn -> other_fn ; fn is norecurse

<a id="langref-willreturn"></a>

`willreturn`  
This function attribute indicates that a call of this function will either exhibit undefined behavior or comes back and continues execution at a point in the existing call stack that includes the current invocation. Annotated functions may still raise an exception, i.a., `nounwind` is not implied. If an invocation of an annotated function does not return control back to a point in the call stack, the behavior is undefined.

`nosync`  
This function attribute indicates that the function does not introduce any *synchronizes-with* edges in the sense of the memory model.

In particular, synchronization is considered possible in the presence of `atomic` accesses that enforce an order, thus not “unordered” and “monotonic”, as well as `convergent` function calls.

Note that `convergent` operations can involve communication that is considered to be not through memory and does not necessarily imply an ordering between threads for the purposes of the memory model. Therefore, an operation can be both `convergent` and `nosync`.

If a `nosync` function does ever synchronize with another thread, the behavior is undefined.

`nounwind`  
This function attribute indicates that the function never raises an exception. If the function does raise an exception, its runtime behavior is undefined. However, functions marked nounwind may still trap or generate asynchronous exceptions. Exception handling schemes that are recognized by LLVM to handle asynchronous exceptions, such as SEH, will still provide their implementation defined semantics.

`nosanitize_bounds`  
This attribute indicates that bounds checking sanitizer instrumentation is disabled for this function.

`nosanitize_coverage`  
This attribute indicates that SanitizerCoverage instrumentation is disabled for this function.

`null_pointer_is_valid`  
If `null_pointer_is_valid` is set, then the `null` address in address-space 0 is considered to be a valid address for memory loads and stores. Any analysis or optimization should not treat dereferencing a pointer to `null` as undefined behavior in this function. Note: Comparing the address of a global variable to `null` may still evaluate to false because of a limitation in querying this attribute inside constant expressions.

`optdebug`  
This attribute suggests that optimization passes and code generator passes should make choices that try to preserve debug info without significantly degrading runtime performance. This attribute is incompatible with the `minsize`, `optsize`, and `optnone` attributes.

`optforfuzzing`  
This attribute indicates that this function should be optimized for maximum fuzzing signal.

`optnone`  
This function attribute indicates that most optimization passes will skip this function, with the exception of interprocedural optimization passes. Code generation defaults to the “fast” instruction selector. This attribute cannot be used together with the `alwaysinline` attribute; this attribute is also incompatible with the `minsize`, `optsize`, and `optdebug` attributes.

This attribute requires the `noinline` attribute to be specified on the function as well, so the function is never inlined into any caller. Only functions with the `alwaysinline` attribute are valid candidates for inlining into the body of this function.

`optsize`  
This attribute suggests that optimization passes and code generator passes make choices that keep the code size of this function low, and otherwise do optimizations specifically to reduce code size as long as they do not significantly impact runtime performance. This attribute is incompatible with the `optdebug` and `optnone` attributes.

`"patchable-function"`  
This attribute tells the code generator that the code generated for this function needs to follow certain conventions that make it possible for a runtime function to patch over it later. The exact effect of this attribute depends on its string value, for which there currently is one legal possibility:

- `"prologue-short-redirect"` - This style of patchable function is intended to support patching a function prologue to redirect control away from the function in a thread-safe manner. It guarantees that the first instruction of the function will be large enough to accommodate a short jump instruction, and will be sufficiently aligned to allow being fully changed via an atomic compare-and-swap instruction. While the first requirement can be satisfied by inserting large enough NOP, LLVM can and will try to re-purpose an existing instruction (i.e., one that would have to be emitted anyway) as the patchable instruction larger than a short jump.

  `"prologue-short-redirect"` is currently only supported on x86-64.

This attribute by itself does not imply restrictions on inter-procedural optimizations. All of the semantic effects the patching may have to be separately conveyed via the linkage type.

`"patchable-function-prefix"`  
This attribute specifies the number of target-specific NOP instructions emitted before the function entry label.

`"patchable-function-entry"`  
This attribute specifies the number of target-specific NOP instructions emitted after the function entry label. These NOPs are emitted before the function prologue.

`"patchable-function-entry-section"`  
This attribute specifies the section used to record the start of the patchable function entry area when such a section is emitted. If omitted, the default section name is `__patchable_function_entries`.

`"probe-stack"`  
This attribute indicates that the function will trigger a guard region in the end of the stack. It ensures that accesses to the stack must be no further apart than the size of the guard region to a previous access of the stack. It takes one required string value, the name of the stack probing function that will be called.

If a function that has a `"probe-stack"` attribute is inlined into a function with another `"probe-stack"` attribute, the resulting function has the `"probe-stack"` attribute of the caller. If a function that has a `"probe-stack"` attribute is inlined into a function that has no `"probe-stack"` attribute at all, the resulting function has the `"probe-stack"` attribute of the callee.

`"stack-probe-size"`  
This attribute controls the behavior of stack probes: either the `"probe-stack"` attribute, or ABI-required stack probes, if any. It defines the size of the guard region. It ensures that if the function may use more stack space than the size of the guard region, a stack probing sequence will be emitted. It takes one required integer value, which is 4096 by default.

If a function that has a `"stack-probe-size"` attribute is inlined into a function with another `"stack-probe-size"` attribute, the resulting function has the `"stack-probe-size"` attribute that has the lower numeric value. If a function that has a `"stack-probe-size"` attribute is inlined into a function that has no `"stack-probe-size"` attribute at all, the resulting function has the `"stack-probe-size"` attribute of the callee.

`"no-stack-arg-probe"`  
This attribute disables ABI-required stack probes, if any.

`returns_twice`  
This attribute indicates that this function can return twice. The C `setjmp` is an example of such a function. The compiler disables some optimizations (like tail calls) in the caller of these functions.

`safestack`  
This attribute indicates that [SafeStack](https://clang.llvm.org/docs/SafeStack.html) protection is enabled for this function.

If a function that has a `safestack` attribute is inlined into a function that doesn’t have a `safestack` attribute or which has an `ssp`, `sspstrong` or `sspreq` attribute, then the resulting function will have a `safestack` attribute.

`sanitize_address`  
This attribute indicates that AddressSanitizer checks (dynamic address safety analysis) are enabled for this function.

`sanitize_memory`  
This attribute indicates that MemorySanitizer checks (dynamic detection of accesses to uninitialized memory) are enabled for this function.

`sanitize_thread`  
This attribute indicates that ThreadSanitizer checks (dynamic thread safety analysis) are enabled for this function.

`sanitize_hwaddress`  
This attribute indicates that HWAddressSanitizer checks (dynamic address safety analysis based on tagged pointers) are enabled for this function.

`sanitize_memtag`  
This attribute indicates that MemTagSanitizer checks (dynamic address safety analysis based on Armv8 MTE) are enabled for this function.

`sanitize_realtime`  
This attribute indicates that RealtimeSanitizer checks (realtime safety analysis - no allocations, syscalls or exceptions) are enabled for this function.

`sanitize_realtime_blocking`  
This attribute indicates that RealtimeSanitizer should error immediately if the attributed function is called during invocation of a function attributed with `sanitize_realtime`. This attribute is incompatible with the `sanitize_realtime` attribute.

`sanitize_alloc_token`  
This attribute indicates that implicit allocation token instrumentation is enabled for this function.

`speculative_load_hardening`  
This attribute indicates that [Speculative Load Hardening](https://llvm.org/docs/SpeculativeLoadHardening.html) should be enabled for the function body.

Speculative Load Hardening is a best-effort mitigation against information leak attacks that make use of control flow miss-speculation - specifically miss-speculation of whether a branch is taken or not. Typically vulnerabilities enabling such attacks are classified as “Spectre variant \#1”. Notably, this does not attempt to mitigate against miss-speculation of branch target, classified as “Spectre variant \#2” vulnerabilities.

When inlining, the attribute is sticky. Inlining a function that carries this attribute will cause the caller to gain the attribute. This is intended to provide a maximally conservative model where the code in a function annotated with this attribute will always (even after inlining) end up hardened.

`speculatable`  
This function attribute indicates that the function does not have any effects besides calculating its result and does not have undefined behavior. Note that `speculatable` is not enough to conclude that along any particular execution path the number of calls to this function will not be externally observable. This attribute is only valid on functions and declarations, not on individual call sites. If a function is incorrectly marked as speculatable and really does exhibit undefined behavior, the undefined behavior may be observed even if the call site is dead code.

`ssp`  
This attribute indicates that the function should emit a stack smashing protector. It is in the form of a “canary” — a random value placed on the stack before the local variables that’s checked upon return from the function to see if it has been overwritten. A heuristic is used to determine if a function needs stack protectors or not. The heuristic used will enable protectors for functions with:

- Character arrays larger than `ssp-buffer-size` (default 8).

- Aggregates containing character arrays larger than `ssp-buffer-size`.

- Calls to alloca() with variable sizes or constant sizes greater than `ssp-buffer-size`.

Variables that are identified as requiring a protector will be arranged on the stack such that they are adjacent to the stack protector guard.

If a function with an `ssp` attribute is inlined into a calling function, the attribute is not carried over to the calling function.

`sspstrong`  
This attribute indicates that the function should emit a stack smashing protector. This attribute causes a strong heuristic to be used when determining if a function needs stack protectors. The strong heuristic will enable protectors for functions with:

- Arrays of any size and type

- Aggregates containing an array of any size and type.

- Calls to alloca().

- Local variables that have had their address taken.

Variables that are identified as requiring a protector will be arranged on the stack such that they are adjacent to the stack protector guard. The specific layout rules are:

1.  Large arrays and structures containing large arrays (`>= ssp-buffer-size`) are closest to the stack protector.

2.  Small arrays and structures containing small arrays (`< ssp-buffer-size`) are 2nd closest to the protector.

3.  Variables that have had their address taken are 3rd closest to the protector.

This overrides the `ssp` function attribute.

If a function with an `sspstrong` attribute is inlined into a calling function which has an `ssp` attribute, the calling function’s attribute will be upgraded to `sspstrong`.

`sspreq`  
This attribute indicates that the function should *always* emit a stack smashing protector. This overrides the `ssp` and `sspstrong` function attributes.

Variables that are identified as requiring a protector will be arranged on the stack such that they are adjacent to the stack protector guard. The specific layout rules are:

1.  Large arrays and structures containing large arrays (`>= ssp-buffer-size`) are closest to the stack protector.

2.  Small arrays and structures containing small arrays (`< ssp-buffer-size`) are 2nd closest to the protector.

3.  Variables that have had their address taken are 3rd closest to the protector.

If a function with an `sspreq` attribute is inlined into a calling function which has an `ssp` or `sspstrong` attribute, the calling function’s attribute will be upgraded to `sspreq`.

<a id="strictfp"></a>

`strictfp`  
This attribute indicates that the function was called from a scope that requires strict floating-point semantics. LLVM will not attempt any optimizations that require assumptions about the floating-point rounding mode or that might alter the state of floating-point status flags that might otherwise be set or cleared by calling this function. LLVM will not introduce any new floating-point instructions that may trap.

<a id="denormal-fpenv"></a>

`denormal_fpenv`  
This indicates the denormal (subnormal) handling that may be assumed for the default floating-point environment. The base form is a `|` separated pair. The elements may be one of `ieee`, `preservesign`, `positivezero`, or `dynamic`. The first entry indicates the flushing mode for the result of floating point operations. The second indicates the handling of denormal inputs to floating point instructions. For compatibility with older bitcode, if the second value is omitted, both input and output modes will assume the same mode.

If this is attribute is not specified, the default is `ieee|ieee`.

If the output mode is `preservesign`, or `positivezero`, denormal outputs may be flushed to zero by standard floating-point operations. It is not mandated that flushing to zero occurs, but if a denormal output is flushed to zero, it must respect the sign mode. Not all targets support all modes.

If the mode is `dynamic`, the behavior is derived from the dynamic state of the floating-point environment. Transformations which depend on the behavior of denormal values should not be performed.

While this indicates the expected floating point mode the function will be executed with, this does not make any attempt to ensure the mode is consistent. User or platform code is expected to set the floating point mode appropriately before function entry.

This may optionally specify a second pair, prefixed with `float:`. This provides an override for the behavior of 32-bit float type (or vectors of 32-bit floats).

If the input mode is `preservesign`, or `positivezero`, a floating-point operation must treat any input denormal value as zero. In some situations, if an instruction does not respect this mode, the input may need to be converted to 0 as if by `@llvm.canonicalize` during lowering for correctness.

This may optionally specify a second pair, prefixed with `float:`. This provides an override for the behavior of 32-bit float type. (or vectors of 32-bit floats). If this is present, this overrides the base handling of the default mode. Not all targets support separately setting the denormal mode per type, and no attempt is made to diagnose unsupported uses. Currently this attribute is respected by the AMDGPU and NVPTX backends.

**Examples:**

- `denormal_fpenv(preservesign)`

- `denormal_fpenv(float: preservesign)`

- `denormal_fpenv(dynamic, float: preservesign|ieee)`

- `denormal_fpenv(ieee|ieee, float: preservesign|preservesign)`

- `denormal_fpenv(ieee|dynamic, float: preservesign|ieee)`

`"thunk"`  
This attribute indicates that the function will delegate to some other function with a tail call. The prototype of a thunk should not be used for optimization purposes. The caller is expected to cast the thunk prototype to match the thunk target prototype.

`uwtable[(sync|async)]`  
This attribute indicates that the ABI being targeted requires that an unwind table entry be produced for this function even if we can show that no exceptions pass by it. This is normally the case for the ELF x86-64 abi, but it can be disabled for some compilation units. The optional parameter describes what kind of unwind tables to generate: `sync` for normal unwind tables, `async` for asynchronous (instruction precise) unwind tables. Without the parameter, the attribute `uwtable` is equivalent to `uwtable(async)`.

`nocf_check`  
This attribute indicates that no control-flow check will be performed on the attributed entity. It disables -fcf-protection=\<\> for a specific entity to fine grain the HW control flow protection mechanism. The flag is target independent and currently appertains to a function or function pointer.

`shadowcallstack`  
This attribute indicates that the ShadowCallStack checks are enabled for the function. The instrumentation checks that the return address for the function has not changed between the function prologue and epilogue. It is currently x86_64-specific.

<a id="langref-mustprogress"></a>

`mustprogress`  
This attribute indicates that the function is required to return, unwind, or interact with the environment in an observable way e.g., via a volatile memory access, I/O, or other synchronization. The `mustprogress` attribute is intended to model the requirements of the first section of \[intro.progress\] of the C++ Standard. As a consequence, a loop in a function with the `mustprogress` attribute can be assumed to terminate if it does not interact with the environment in an observable way, and terminating loops without side-effects can be removed. If a `mustprogress` function does not satisfy this contract, the behavior is undefined. If a `mustprogress` function calls a function not marked `mustprogress`, and that function never returns, the program is well-defined even if there isn’t any other observable progress. Note that `willreturn` implies `mustprogress`.

`"warn-stack-size"="<threshold>"`  
This attribute sets a threshold to emit diagnostics once the frame size is known should the frame size exceed the specified value. It takes one required integer value, which should be a non-negative integer, and less than `UINT_MAX`. It’s unspecified which threshold will be used when duplicate definitions are linked together with differing values.

`vscale_range(<min>[, <max>])`  
This function attribute indicates `vscale` is a power-of-two within a specified range. `min` must be a power-of-two that is greater than 0. When specified, `max` must be a power-of-two greater-than-or-equal to `min` or 0 to signify an unbounded maximum. The syntax `vscale_range(<val>)` can be used to set both `min` and `max` to the same value. Functions that don’t include this attribute make no assumptions about the range of `vscale`.

`nooutline`  
This attribute indicates that outlining passes should not modify the function.

`nocreateundeforpoison`  
This attribute indicates that the result of the function (prior to application of return attributes/metadata) will not be undef or poison if all arguments are not undef and not poison. Otherwise, it is undefined behavior.

`"modular-format"="<type>,<string_idx>,<first_arg_idx>,<modular_impl_fn>,<impl_name>,<aspects...>"`  
This attribute indicates that the implementation is modular on a particular format string argument. If the compiler can determine that not all aspects of the implementation are needed, it can report which aspects were needed and redirect the call to a modular implementation function instead.

The compiler reports that an implementation aspect is needed by issuing a relocation for the symbol `<impl_name>_<aspect>`. This arranges for code and data needed to support the aspect of the implementation to be brought into the link to satisfy weak references in the modular implemenation function.

The first three arguments have the same semantics as the arguments to the C `format` attribute.

The following aspects are currently supported:

- `fixed`: The call has a C ISO 18037 fixed-point argument.

- `float`: The call has a floating point argument

<a id="call-site-attributes"></a>

### Call Site Attributes

In addition to function attributes the following call site only attributes are supported:

`vector-function-abi-variant`  
This attribute can be attached to a [call](instructions-other.md#i-call) to list the vector functions associated to the function. Notice that the attribute cannot be attached to a [invoke](instructions-terminators.md#i-invoke) or a [callbr](instructions-terminators.md#i-callbr) instruction. The attribute consists of a comma separated list of mangled names. The order of the list does not imply preference (it is logically a set). The compiler is free to pick any listed vector function of its choosing.

The syntax for the mangled names is as follows:

    _ZGV<isa><mask><vlen><parameters>_<scalar_name>[(<vector_redirection>)]

When present, the attribute informs the compiler that the function `<scalar_name>` has a corresponding vector variant that can be used to perform the concurrent invocation of `<scalar_name>` on vectors. The shape of the vector function is described by the tokens between the prefix `_ZGV` and the `<scalar_name>` token. The standard name of the vector function is `_ZGV<isa><mask><vlen><parameters>_<scalar_name>`. When present, the optional token `(<vector_redirection>)` informs the compiler that a custom name is provided in addition to the standard one (custom names can be provided for example via the use of `declare   variant` in OpenMP 5.0). The declaration of the variant must be present in the IR Module. The signature of the vector variant is determined by the rules of the Vector Function ABI (VFABI) specifications of the target. For Arm and X86, the VFABI can be found at https://github.com/ARM-software/abi-aa and https://software.intel.com/content/www/us/en/develop/download/vector-simd-function-abi.html, respectively.

For X86 and Arm targets, the values of the tokens in the standard name are those that are defined in the VFABI. LLVM has an internal `<isa>` token that can be used to create scalar-to-vector mappings for functions that are not directly associated to any of the target ISAs (for example, some of the mappings stored in the TargetLibraryInfo). Valid values for the `<isa>` token are:

    <isa>:= b | c | d | e  -> X86 SSE, AVX, AVX2, AVX512
          | n | s          -> Armv8 Advanced SIMD, SVE
          | __LLVM__       -> Internal LLVM Vector ISA

For all targets currently supported (x86, Arm and Internal LLVM), the remaining tokens can have the following values:

    <mask>:= M | N         -> mask | no mask

    <vlen>:= number        -> number of lanes
           | x             -> VLA (Vector Length Agnostic)

    <parameters>:= v              -> vector
                 | l | l <number> -> linear
                 | R | R <number> -> linear with ref modifier
                 | L | L <number> -> linear with val modifier
                 | U | U <number> -> linear with uval modifier
                 | ls <pos>       -> runtime linear
                 | Rs <pos>       -> runtime linear with ref modifier
                 | Ls <pos>       -> runtime linear with val modifier
                 | Us <pos>       -> runtime linear with uval modifier
                 | u              -> uniform

    <scalar_name>:= name of the scalar function

    <vector_redirection>:= optional, custom name of the vector function

`preallocated(<ty>)`  
This attribute is required on calls to `llvm.call.preallocated.arg` and cannot be used on any other call. See [llvm.call.preallocated.arg](intrinsics-overview-and-basic.md#int-call-preallocated-arg) for more details.

<a id="global-attributes"></a>

<a id="glattrs"></a>

### Global Attributes

Attributes may be set to communicate additional information about a global variable. Unlike [function attributes](#fnattrs), attributes on a global variable are grouped into a single [attribute group](#attrgrp).

`no_sanitize_address`  
This attribute indicates that the global variable should not have AddressSanitizer instrumentation applied to it, because it was annotated with `__attribute__((no_sanitize("address")))`, `__attribute__((disable_sanitizer_instrumentation))`, or included in the `-fsanitize-ignorelist` file.

`no_sanitize_hwaddress`  
This attribute indicates that the global variable should not have HWAddressSanitizer instrumentation applied to it, because it was annotated with `__attribute__((no_sanitize("hwaddress")))`, `__attribute__((disable_sanitizer_instrumentation))`, or included in the `-fsanitize-ignorelist` file.

`sanitize_memtag`  
This attribute indicates that the global variable should have AArch64 memory tags (MTE) instrumentation applied to it. This attribute causes the suppression of certain optimizations, like GlobalMerge, as well as ensuring extra directives are emitted in the assembly and extra bits of metadata are placed in the object file so that the linker can ensure the accesses are protected by MTE. This attribute is added by clang when `-fsanitize=memtag-globals` is provided, as long as the global is not marked with `__attribute__((no_sanitize("memtag")))`, `__attribute__((disable_sanitizer_instrumentation))`, or included in the `-fsanitize-ignorelist` file. The AArch64 Globals Tagging pass may remove this attribute when it’s not possible to tag the global (e.g., it’s a TLS variable).

`sanitize_address_dyninit`  
This attribute indicates that the global variable, when instrumented with AddressSanitizer, should be checked for ODR violations. This attribute is applied to global variables that are dynamically initialized according to C++ rules.

<a id="operand-bundles"></a>

<a id="opbundles"></a>

### Operand Bundles

Operand bundles are tagged sets of SSA values or metadata strings that can be associated with certain LLVM instructions (currently only `call` s and `invoke` s). In a way they are like metadata, but dropping them is incorrect and will change program semantics.

Syntax:

    operand bundle set ::= '[' operand bundle (, operand bundle )* ']'
    operand bundle ::= tag '(' [ bundle operand ] (, bundle operand )* ')'
    bundle operand ::= SSA value | metadata string
    tag ::= string constant

Operand bundles are **not** part of a function’s signature, and a given function may be called from multiple places with different kinds of operand bundles. This reflects the fact that the operand bundles are conceptually a part of the `call` (or `invoke`), not the callee being dispatched to.

Operand bundles are a generic mechanism intended to support runtime-introspection-like functionality for managed languages. While the exact semantics of an operand bundle depend on the bundle tag, there are certain limitations to how much the presence of an operand bundle can influence the semantics of a program. These restrictions are described as the semantics of an “unknown” operand bundle. As long as the behavior of an operand bundle is describable within these restrictions, LLVM does not need to have special knowledge of the operand bundle to not miscompile programs containing it.

- The bundle operands for an unknown operand bundle escape in unknown ways before control is transferred to the callee or invokee.

- Calls and invokes with operand bundles have unknown read / write effect on the heap on entry and exit (even if the call target specifies a `memory` attribute), unless they’re overridden with callsite specific attributes.

- An operand bundle at a call site cannot change the implementation of the called function. Inter-procedural optimizations work as usual as long as they take into account the first two properties.

More specific types of operand bundles are described below.

<a id="deoptimization-operand-bundles"></a>

<a id="deopt-opbundles"></a>

#### Deoptimization Operand Bundles

Deoptimization operand bundles are characterized by the `"deopt"` operand bundle tag. These operand bundles represent an alternate “safe” continuation for the call site they’re attached to, and can be used by a suitable runtime to deoptimize the compiled frame at the specified call site. There can be at most one `"deopt"` operand bundle attached to a call site. Exact details of deoptimization are out of scope for the language reference, but it usually involves rewriting a compiled frame into a set of interpreted frames.

From the compiler’s perspective, deoptimization operand bundles make the call sites they’re attached to at least `readonly`. They read through all of their pointer typed operands (even if they’re not otherwise escaped) and the entire visible heap. Deoptimization operand bundles do not capture their operands except during deoptimization, in which case control will not be returned to the compiled frame.

The inliner knows how to inline through calls that have deoptimization operand bundles. Just like inlining through a normal call site involves composing the normal and exceptional continuations, inlining through a call site with a deoptimization operand bundle needs to appropriately compose the “safe” deoptimization continuation. The inliner does this by prepending the parent’s deoptimization continuation to every deoptimization continuation in the inlined body. E.g. inlining `@f` into `@g` in the following example

    define void @f() {
      call void @x()  ;; no deopt state
      call void @y() [ "deopt"(i32 10) ]
      call void @y() [ "deopt"(i32 10), "unknown"(ptr null) ]
      ret void
    }

    define void @g() {
      call void @f() [ "deopt"(i32 20) ]
      ret void
    }

will result in

    define void @g() {
      call void @x()  ;; still no deopt state
      call void @y() [ "deopt"(i32 20, i32 10) ]
      call void @y() [ "deopt"(i32 20, i32 10), "unknown"(ptr null) ]
      ret void
    }

It is the frontend’s responsibility to structure or encode the deoptimization state in a way that syntactically prepending the caller’s deoptimization state to the callee’s deoptimization state is semantically equivalent to composing the caller’s deoptimization continuation after the callee’s deoptimization continuation.

<a id="funclet-operand-bundles"></a>

<a id="ob-funclet"></a>

#### Funclet Operand Bundles

Funclet operand bundles are characterized by the `"funclet"` operand bundle tag. These operand bundles indicate that a call site is within a particular funclet. There can be at most one `"funclet"` operand bundle attached to a call site and it must have exactly one bundle operand.

If any funclet EH pads have been “entered” but not “exited” (per the [description in the EH doc](ExceptionHandling.html#wineh-constraints)), it is undefined behavior to execute a `call` or `invoke` which:

- does not have a `"funclet"` bundle and is not a `call` to a nounwind intrinsic, or

- has a `"funclet"` bundle whose operand is not the most-recently-entered not-yet-exited funclet EH pad.

Similarly, if no funclet EH pads have been entered-but-not-yet-exited, executing a `call` or `invoke` with a `"funclet"` bundle is undefined behavior.

<a id="gc-transition-operand-bundles"></a>

#### GC Transition Operand Bundles

GC transition operand bundles are characterized by the `"gc-transition"` operand bundle tag. These operand bundles mark a call as a transition between a function with one GC strategy to a function with a different GC strategy. If coordinating the transition between GC strategies requires additional code generation at the call site, these bundles may contain any values that are needed by the generated code. For more details, see [GC Transitions](Statepoints.html#gc-transition-args).

The bundle contains an arbitrary list of Values which need to be passed to GC transition code. They will be lowered and passed as operands to the appropriate `GC_TRANSITION` nodes in the selection DAG. It is assumed that these arguments must be available before and after (but not necessarily during) the execution of the callee.

<a id="assume-operand-bundles"></a>

<a id="assume-opbundles"></a>

#### Assume Operand Bundles

Operand bundles on an [llvm.assume](intrinsics-general.md#int-assume) allow representing assumptions that hold at the location of the assume. Operand bundles enable assumptions that are either hard or impossible to represent as a boolean argument of an [llvm.assume](intrinsics-general.md#int-assume).

Assumes with operand bundles must have `i1 true` as the condition operand.

Just like for the argument of [llvm.assume](intrinsics-general.md#int-assume), if any of the provided guarantees are violated at runtime the behavior is undefined.

While attributes expect constant arguments, assume operand bundles may be provided a dynamic value, for example:

    call void @llvm.assume(i1 true) ["align"(ptr %val, i32 %align)]

The following attributes are currently accepted:

`"align"(ptr %p, i64 %align)`, `"align"(ptr %p, i64 %align, i64 %offset)`  
Equivalent to [align(%align)](#attr-align) on `%p`, or `%p - %offset` if the `%offset` argument exists, except that `%align` may be a non-power-of-two alignment (including a zero alignment). If `%align` is not a power of two, the pointer value must be all-zero. Otherwise the behavior is undefined.

`"cold"()`  
Equivalent to [cold](#attr-cold).

`"dereferenceable"(ptr %p, i64 %size)`  
Equivalent to [dereferenceable(%size)](#attr-dereferenceable) on `%p`, except that `%size` may also be zero, in which case the bundle doesn’t imply `nonnull`.

`"dereferenceable_or_null"(ptr %p, i64 %size)`  
Equivalent to [dereferenceable_or_null(%size)](#attr-dereferenceable-or-null) on `%p`, except that `%size` may also be zero.

`"ignore"(...)`  
Doesn’t imply anything and is ignored. This is used to drop an assume where the `llvm.assume` call cannot be replaced or dropped.

`"nonnull"(ptr %p)`  
Equivalent to [nonnull](#attr-nonnull) on `%p`.

`"noundef"(any_type %v)`  
Equivalent to [noundef](#attr-noundef) on `%v`.

`"separate_storage"(ptr %p1, ptr %p2)`  
This indicates that no pointer [based](#pointeraliasing) on one of its arguments can alias any pointer based on the other.

For example:

    call void @llvm.assume(i1 true) ["align"(ptr %val, i32 8)]

allows the optimizer to assume that at location of call to [llvm.assume](intrinsics-general.md#int-assume) `%val` has an alignment of at least 8.

    call void @llvm.assume(i1 true) ["cold"(), "nonnull"(ptr %val)]

allows the optimizer to assume that the [llvm.assume](intrinsics-general.md#int-assume) call location is cold and that `%val` may not be null.

Even if the assumed property can be encoded as a boolean value, like `nonnull`, using operand bundles to express the property can still have benefits:

- Attributes that can be expressed via operand bundles are directly the property that the optimizer uses and cares about. Encoding attributes as operand bundles removes the need for an instruction sequence that represents the property (e.g., `icmp ne ptr %p, null` for `nonnull`) and for the optimizer to deduce the property from that instruction sequence.

- Expressing the property using operand bundles makes it easy to identify the use of the value as a use in an [llvm.assume](intrinsics-general.md#int-assume). This then simplifies and improves heuristics, e.g., for use “use-sensitive” optimizations.

<a id="preallocated-operand-bundles"></a>

<a id="ob-preallocated"></a>

#### Preallocated Operand Bundles

Preallocated operand bundles are characterized by the `"preallocated"` operand bundle tag. These operand bundles allow separation of the allocation of the call argument memory from the call site. This is necessary to pass non-trivially copyable objects by value in a way that is compatible with MSVC on some targets. There can be at most one `"preallocated"` operand bundle attached to a call site and it must have exactly one bundle operand, which is a token generated by `@llvm.call.preallocated.setup`. A call with this operand bundle should not adjust the stack before entering the function, as that will have been done by one of the `@llvm.call.preallocated.*` intrinsics.

    %foo = type { i64, i32 }

    ...

    %t = call token @llvm.call.preallocated.setup(i32 1)
    %a = call ptr @llvm.call.preallocated.arg(token %t, i32 0) preallocated(%foo)
    ; initialize %b
    call void @bar(i32 42, ptr preallocated(%foo) %a) ["preallocated"(token %t)]

<a id="gc-live-operand-bundles"></a>

<a id="ob-gc-live"></a>

#### GC Live Operand Bundles

A “gc-live” operand bundle is only valid on a [gc.statepoint](intrinsics-overview-and-basic.md#gc-statepoint) intrinsic. The operand bundle must contain every pointer to a garbage collected object which potentially needs to be updated by the garbage collector.

When lowered, any relocated value will be recorded in the corresponding [stackmap entry](Statepoints.html#statepoint-stackmap-format). See the intrinsic description for further details.

<a id="objc-arc-attached-call-operand-bundles"></a>

#### ObjC ARC Attached Call Operand Bundles

A `"clang.arc.attachedcall"` operand bundle on a call indicates the call is implicitly followed by a marker instruction and a call to an ObjC runtime function that uses the result of the call. The operand bundle takes a mandatory pointer to the runtime function (`@objc_retainAutoreleasedReturnValue` or `@objc_unsafeClaimAutoreleasedReturnValue`). The return value of a call with this bundle is used by a call to `@llvm.objc.clang.arc.noop.use` unless the called function’s return type is void, in which case the operand bundle is ignored.

    ; The marker instruction and a runtime function call are inserted after the call
    ; to @foo.
    call ptr @foo() [ "clang.arc.attachedcall"(ptr @objc_retainAutoreleasedReturnValue) ]
    call ptr @foo() [ "clang.arc.attachedcall"(ptr @objc_unsafeClaimAutoreleasedReturnValue) ]

The operand bundle is needed to ensure the call is immediately followed by the marker instruction and the ObjC runtime call in the final output.

<a id="pointer-authentication-operand-bundles"></a>

<a id="ob-ptrauth"></a>

#### Pointer Authentication Operand Bundles

Pointer Authentication operand bundles are characterized by the `"ptrauth"` operand bundle tag. They are described in the [Pointer Authentication](PointerAuth.html#operand-bundle) document.

<a id="kcfi-operand-bundles"></a>

<a id="ob-kcfi"></a>

#### KCFI Operand Bundles

A `"kcfi"` operand bundle on an indirect call indicates that the call will be preceded by a runtime type check, which validates that the call target is prefixed with a [type identifier](metadata.md#md-kcfi-type) that matches the operand bundle attribute. For example:

    call void %0() ["kcfi"(i32 1234)]

Clang emits KCFI operand bundles and the necessary metadata with `-fsanitize=kcfi`.

<a id="convergence-control-operand-bundles"></a>

<a id="convergencectrl"></a>

#### Convergence Control Operand Bundles

A “convergencectrl” operand bundle is only valid on a `convergent` operation. When present, the operand bundle must contain exactly one value of token type. See the [Convergent Operation Semantics](ConvergentOperations.html) document for details.

<a id="deactivation-symbol-operand-bundles"></a>

<a id="deactivationsymbol"></a>

#### Deactivation Symbol Operand Bundles

A `"deactivation-symbol"` operand bundle is valid on the following instructions (AArch64 only):

- Call to a normal function with `notail` attribute and a first argument and return value of type `ptr`.

- Call to `llvm.ptrauth.sign` or `llvm.ptrauth.auth` intrinsics.

This operand bundle specifies that if the deactivation symbol is defined to a valid value for the target, the marked instruction will return the value of its first argument instead of calling the specified function or intrinsic. This is achieved with `PATCHINST` relocations on the target instructions (see the AArch64 psABI for details).

<a id="module-level-inline-assembly"></a>

<a id="moduleasm"></a>

### Module-Level Inline Assembly

Modules may contain “module-level inline asm” blocks, which corresponds to the GCC “file scope inline asm” blocks:

    module asm
        "inline asm code goes here"
        "more can go here"

The sequence of string literals is internally concatenated using newlines as separators. The strings can contain any character by escaping non-printable characters. The escape sequence used is simply “\xx” where “xx” is the two digit hex code for the number.

Additionally, module-level inline assembly can specify an optional list of properties:

    module asm(target_features: "+foo", target_cpu: "bar")
        "inline asm code goes here"
        "more can go here"

Currently, the only supported properties are `target_features` and `target_cpu`, with the same meaning as the `"target-features"` and `"target-cpu"` function attributes.

Consecutive blocks with identical properties will be concatenated into one.

Note that the assembly string *must* be parseable by LLVM’s integrated assembler (unless it is disabled), even when emitting a `.s` file.

<a id="data-layout"></a>

<a id="langref-datalayout"></a>

### Data Layout

A module may specify a target-specific data layout string that specifies how data is to be laid out in memory. The syntax for the data layout is simply:

    target datalayout = "layout specification"

The *layout specification* consists of a list of specifications separated by the minus sign character (‘-‘). Each specification starts with a letter and may include other information after the letter to define some aspect of the data layout. The specifications accepted are as follows:

`E`  
Specifies that the target lays out data in big-endian form. That is, the bits with the most significance have the lowest address location.

`e`  
Specifies that the target lays out data in little-endian form. That is, the bits with the least significance have the lowest address location.

`S<size>`  
Specifies the natural alignment of the stack in bits. Alignment promotion of stack variables is limited to the natural stack alignment to avoid dynamic stack realignment. If omitted, the natural stack alignment defaults to “unspecified”, which does not prevent any alignment promotions.

`P<address space>`  
Specifies the address space that corresponds to program memory. Harvard architectures can use this to specify what space LLVM should place things such as functions into. If omitted, the program memory space defaults to the default address space of 0, which corresponds to a Von Neumann architecture that has code and data in the same space.

<a id="globals-addrspace"></a>

`G<address space>`  
Specifies the address space to be used by default when creating global variables. If omitted, the globals address space defaults to the default address space 0. Note: variable declarations without an address space are always created in address space 0, this property only affects the default value to be used when creating globals without additional contextual information (e.g., in LLVM passes).

<a id="alloca-addrspace"></a>

`A<address space>`  
Specifies the address space of objects created by ‘`alloca`’. Defaults to the default address space of 0.

`p[<flags>][<as>][(<name>)]:<size>:<abi>[:<pref>[:<idx>]]`  
This specifies the properties of a pointer in address space `as`. The `<size>` parameter specifies the size of the bitwise representation. For [non-integral pointers](#nointptrtype) the representation size may be larger than the address width of the underlying address space (e.g., to accommodate additional metadata). The alignment requirements are specified via the `<abi>` and `<pref>`erred alignments parameters. The fourth parameter `<idx>` is the size of the index that used for address calculations such as [getelementptr](instructions-memory.md#i-getelementptr). It must be less than or equal to the pointer size. If not specified, the default index size is equal to the pointer size. The index size also specifies the width of addresses in this address space. All sizes are in bits. The address space, `<as>`, is optional, and if not specified, denotes the default address space 0. The value of `<as>` must be in the range \[1,2^24). The optional `<flags>` are used to specify properties of pointers in this address space: the character `u` marks pointers as having an unstable representation, and `e` marks pointers having external state. See [Non-Integral Pointer Types](#nointptrtype). Additionally, the null pointer bit representation can be specified: `z` indicates it is all-zeros, and `o` indicates it is all-ones. At most one of `z` or `o` may be specified. If neither `z` nor `o` is specified, the null pointer bit representation defaults to all-zeros. The `<name>` is an optional name of that address space, surrounded by `(` and `)`. If the name is specified, it must be unique to that address space and cannot be `A`, `G`, or `P` which are pre-defined names used to denote alloca, global, and program address space respectively.

`i<size>:<abi>[:<pref>]`  
This specifies the alignment for an integer type of a given bit `<size>`. The value of `<size>` must be in the range \[1,2^24). For `i8`, the `<abi>` value must equal 8, that is, `i8` must be naturally aligned.

`v<size>:<abi>[:<pref>]`  
This specifies the alignment for a vector type of a given bit `<size>`. The value of `<size>` must be in the range \[1,2^24).

`ve`  
Specifies that vectors are element-aligned by default, rather than having natural alignment.

`f<size>:<abi>[:<pref>]`  
This specifies the alignment for a floating-point type of a given bit `<size>`. Only values of `<size>` that are supported by the target will work. 32 (float) and 64 (double) are supported on all targets; 80 or 128 (different flavors of long double) are also supported on some targets. The value of `<size>` must be in the range \[1,2^24).

`a:<abi>[:<pref>]`  
This specifies the alignment for an object of aggregate type. In addition to the usual requirements for alignment values, the value of `<abi>` can also be zero, which means one byte alignment.

`F<type><abi>`  
This specifies the alignment for function pointers. The options for `<type>` are:

- `i`: The alignment of function pointers is independent of the alignment of functions, and is a multiple of `<abi>`.

- `n`: The alignment of function pointers is a multiple of the explicit alignment specified on the function, and is a multiple of `<abi>`.

`m:<mangling>`  
If present, specifies that llvm names are mangled in the output. Symbols prefixed with the mangling escape character `\01` are passed through directly to the assembler without the escape character. The mangling style options are

- `e`: ELF mangling: Private symbols get a `.L` prefix.

- `l`: GOFF mangling: Private symbols get a `@` prefix.

- `m`: Mips mangling: Private symbols get a `$` prefix.

- `o`: Mach-O mangling: Private symbols get `L` prefix. Other symbols get a `_` prefix.

- `x`: Windows x86 COFF mangling: Private symbols get the usual prefix. Regular C symbols get a `_` prefix. Functions with `__stdcall`, `__fastcall`, and `__vectorcall` have custom mangling that appends `@N` where N is the number of bytes used to pass parameters. C++ symbols starting with `?` are not mangled in any way.

- `w`: Windows COFF mangling: Similar to `x`, except that normal C symbols do not receive a `_` prefix.

- `a`: XCOFF mangling: Private symbols get a `L..` prefix.

`n<size1>:<size2>:<size3>...`  
This specifies a set of native integer widths for the target CPU in bits. For example, it might contain `n32` for 32-bit PowerPC, `n32:64` for PowerPC 64, or `n8:16:32:64` for X86-64. Elements of this set are considered to support most general arithmetic operations efficiently.

`ni:<address space0>:<address space1>:<address space2>...`  
This marks pointer types with the specified address spaces as [unstable](#nointptrtype). The `0` address space cannot be specified as non-integral. It is only supported for backwards compatibility, the flags of the `p` specifier should be used instead for new code.

`<abi>` is a lower bound on what is required for a type to be considered aligned. This is used in various places, such as:

- The alignment for loads and stores if none is explicitly given.

- The alignment used to compute struct layout.

- The alignment used to compute allocation sizes and thus `getelementptr` offsets.

- The alignment below which accesses are considered underaligned.

`<pref>` allows providing a more optimal alignment that should be used when possible, primarily for `alloca` and the alignment of global variables. It is an optional value that must be greater than or equal to `<abi>`. If omitted, the preceding `:` should also be omitted and `<pref>` will be equal to `<abi>`.

Unless explicitly stated otherwise, every alignment specification is provided in bits and must be in the range \[1,2^16). The value must be a power of two times the width of a byte (i.e., `align = 8 * 2^N`).

When constructing the data layout for a given target, LLVM starts with a default set of specifications which are then (possibly) overridden by the specifications in the `datalayout` keyword. The default specifications are given in this list:

- `e` - little endian

- `p:64:64:64` - 64-bit pointers with 64-bit alignment.

- `p[n]:64:64:64` - Other address spaces are assumed to be the same as the default address space.

- `S0` - natural stack alignment is unspecified

- `i8:8:8` - i8 is 8-bit (byte) aligned as mandated

- `i16:16:16` - i16 is 16-bit aligned

- `i32:32:32` - i32 is 32-bit aligned

- `i64:32:64` - i64 has ABI alignment of 32-bits but preferred alignment of 64-bits

- `f16:16:16` - half is 16-bit aligned

- `f32:32:32` - float is 32-bit aligned

- `f64:64:64` - double is 64-bit aligned

- `f128:128:128` - quad is 128-bit aligned

- `v64:64:64` - 64-bit vector is 64-bit aligned

- `v128:128:128` - 128-bit vector is 128-bit aligned

- `a:0:64` - aggregates are 64-bit aligned

When LLVM is determining the alignment for a given type, it uses the following rules:

1.  If the type sought is an exact match for one of the specifications, that specification is used.

2.  If no match is found, and the type sought is an integer type, then the smallest integer type that is larger than the bitwidth of the sought type is used. If none of the specifications are larger than the bitwidth then the largest integer type is used. For example, given the default specifications above, the i7 type will use the alignment of i8 (next largest) while both i65 and i256 will use the alignment of i64 (largest specified).

The function of the data layout string may not be what you expect. Notably, this is not a specification from the frontend of what alignment the code generator should use.

Instead, if specified, the target data layout is required to match what the ultimate *code generator* expects. This string is used by the mid-level optimizers to improve code, and this only works if it matches what the ultimate code generator uses. There is no way to generate IR that does not embed this target-specific detail into the IR. If you don’t specify the string, the default specifications will be used to generate a Data Layout and the optimization phases will operate accordingly and introduce target specificity into the IR with respect to these default specifications.

<a id="target-triple"></a>

<a id="langref-triple"></a>

### Target Triple

A module may specify a target triple string that describes the target host. The syntax for the target triple is simply:

    target triple = "x86_64-apple-macosx10.7.0"

The *target triple* string consists of a series of identifiers delimited by the minus sign character (‘-‘). The canonical forms are:

    ARCHITECTURE-VENDOR-OPERATING_SYSTEM
    ARCHITECTURE-VENDOR-OPERATING_SYSTEM-ENVIRONMENT

This information is passed along to the backend so that it generates code for the proper architecture. It’s possible to override this on the command line with the `-mtriple` command-line option.

<a id="allocated-objects"></a>

<a id="allocatedobjects"></a>

### Allocated Objects

An allocated object, memory object, or simply object, is a region of a memory space that is reserved by a memory allocation such as [alloca](instructions-memory.md#i-alloca), heap allocation calls, and global variable definitions. Once it is allocated, the bytes stored in the region can only be read or written through a pointer that is [based on](#pointeraliasing) the allocation value. If a pointer that is not based on the object tries to read or write to the object, it is undefined behavior.

The following properties hold for all allocated objects, otherwise the behavior is undefined:

- no allocated object may cross the unsigned address space boundary (including the pointer after the end of the object),

- the size of all allocated objects must be non-negative and not exceed the largest signed integer that fits into the index type.

Allocated objects that are created with operations recognized by LLVM (such as [alloca](instructions-memory.md#i-alloca), heap allocation functions marked as such, and global variables) may *not* change their size. (`realloc`-style operations do not change the size of an existing allocated object; instead, they create a new allocated object. Even if the object is at the same location as the old one, old pointers cannot be used to access this new object.) However, allocated objects can also be created by means not recognized by LLVM, e.g., by directly calling `mmap`. Those allocated objects are allowed to grow to the right (i.e., keeping the same base address, but increasing their size) while maintaining the validity of existing pointers, as long as they always satisfy the properties described above. Currently, allocated objects are not permitted to grow to the left or to shrink, nor can they have holes.

<a id="object-lifetime"></a>

<a id="objectlifetime"></a>

### Object Lifetime

A lifetime of an [allocated object](#allocatedobjects) is a property that decides its accessibility. Unless stated otherwise, an allocated object is alive since its allocation, and dead after its deallocation. It is undefined behavior to access an allocated object that isn’t alive, but operations that don’t dereference it such as [getelementptr](instructions-memory.md#i-getelementptr), [ptrtoint](instructions-conversion.md#i-ptrtoint) and [icmp](instructions-other.md#i-icmp) return a valid result. This explains code motion of these instructions across operations that impact the object’s lifetime. A stack object’s lifetime can be explicitly specified using [llvm.lifetime.start](intrinsics-general.md#int-lifestart) and [llvm.lifetime.end](intrinsics-general.md#int-lifeend) intrinsic function calls.

As an exception to the above, loading from a stack object outside its lifetime is not undefined behavior and returns a poison value instead. Storing to it is still undefined behavior.

<a id="pointer-aliasing-rules"></a>

<a id="pointeraliasing"></a>

### Pointer Aliasing Rules

Any memory access must be done through a pointer value associated with an address range of the memory access, otherwise the behavior is undefined. Pointer values are associated with address ranges according to the following rules:

- A pointer value is associated with the addresses associated with any value it is *based* on.

- An address of a global variable is associated with the address range of the variable’s storage.

- The result value of an allocation instruction is associated with the address range of the allocated storage.

- A null pointer in the default address-space is associated with no address.

- An [undef value](constants.md#undefvalues) in *any* address-space is associated with no address.

- An integer constant other than zero or a pointer value returned from a function not defined within LLVM may be associated with address ranges allocated through mechanisms other than those provided by LLVM. Such ranges shall not overlap with any ranges of addresses allocated by mechanisms provided by LLVM.

A pointer value is *based* on another pointer value according to the following rules:

- A pointer value formed from a scalar `getelementptr` operation is *based* on the pointer-typed operand of the `getelementptr`.

- The pointer in lane *l* of the result of a vector `getelementptr` operation is *based* on the pointer in lane *l* of the vector-of-pointers-typed operand of the `getelementptr`.

- The result value of a `bitcast` is *based* on the operand of the `bitcast`.

- A pointer value formed by an `inttoptr` is *based* on all pointer values that contribute (directly or indirectly) to the computation of the pointer’s value.

- The “*based* on” relationship is transitive.

Note that this definition of *“based”* is intentionally similar to the definition of *“based”* in C99, though it is slightly weaker.

LLVM IR does not associate types with memory. The result type of a `load` merely indicates the size and alignment of the memory from which to load, as well as the interpretation of the value. The first operand type of a `store` similarly only indicates the size and alignment of the store.

Consequently, type-based alias analysis, aka TBAA, aka `-fstrict-aliasing`, is not applicable to general unadorned LLVM IR. [Metadata](metadata.md#metadata) may be used to encode additional information which specialized optimization passes may use to implement type-based alias analysis.

<a id="pointer-capture"></a>

<a id="pointercapture"></a>

### Pointer Capture

Given a function call and a pointer that is passed as an argument or stored in memory before the call, the call may capture two components of the pointer:

- The address of the pointer, which is its integral value. This also includes parts of the address or any information about the address, including the fact that it does not equal one specific value. We further distinguish whether only the fact that the address is/isn’t null is captured.

- The provenance of the pointer, which is the ability to perform memory accesses through the pointer, in the sense of the [pointer aliasing rules](#pointeraliasing). We further distinguish whether only read accesses are allowed, or both reads and writes.

These two cases are discussed in more detail in the following.

<a id="provenance-capture"></a>

#### Provenance capture

If an argument does not capture the provenance of the pointer, accesses that are based on the argument and are performed after the function returns (or unwinds) cause undefined behavior. In the case where only read provenance is captured, only stores cause undefined behavior.

More formally, an argument that does not capture provenance effectively provides the callee a new pointer with the same address and a derived provenance, where the derived provenance initially has the same permissions as the original, but all access permissions are removed once the function returns (or unwinds). Or in the case of only capturing read provenance, the permissions are changed to only allow read accesses.

This means that the following code is well-defined in isolation:

    define void @f(ptr captures(address) %a, ptr %b) {
      store ptr %a, ptr %b
      ret void
    }

Even though the pointer is stored in another location that persists past the return of the function, this does not cause undefined behavior by itself. It depends on whether/how the pointer will be used in the future.

    call void @f(ptr captures(address) %a, ptr %b)
    %a2 = load ptr, ptr %b ; This is still well-defined
    load i64, ptr %a2 ; This causes undefined behavior

In this example, the persisted pointer is accessed after the return of the function, which causes undefined behavior.

    call void @f(ptr captures(address, read_provenance) %a, ptr %b)
    %a2 = load ptr, ptr %b
    load i64, ptr %a2 ; This is still well-defined
    store i64 0, ptr %a2 ; This causes undefined behavior

In this example, we additionally declare that `read_provenance` is captured. This means that the `load` after the function return is still well-defined, while the store causes undefined behavior.

<a id="address-capture"></a>

#### Address capture

The address of the pointer is considered to be captured if the function can exhibit different observable behavior based on the address of the pointer.

For example, the following function captures the address of `%a`, because it will return a different value if the address has a specific value:

    @glb = global i8 0

    define i1 @f(ptr %a) {
      %c = icmp eq ptr %a, @glb
      ret i1 %c
    }

The function does not capture the provenance of the pointer, because the `icmp` instruction only operates on the pointer address.

Even if the function contains a comparison on the pointer address, this does not necessarily mean that it captures the address:

    define void @my_memmove(
        ptr captures(none) %dst, ptr captures(none) %src, i64 %size
    ) {
      %cmp = icmp ult ptr %dst, %src
      br i1 %cmp, label %perform_forward_copy, label %perform_backward_copy

      ; ...
    }

While the implementation differs based on the addresses of the arguments, the observable behavior stays the same in both branches. A common case where this occurs are runtime aliasing checks for loop versioning.

<a id="location-specific-capture"></a>

#### Location specific capture

We can further say that the capture only occurs through a specific location. In the following example, the pointer (both address and provenance) is captured through the return value only:

    define ptr @f(ptr %a) {
      %gep = getelementptr i8, ptr %a, i64 4
      ret ptr %gep
    }

However, we always consider direct inspection of the pointer address (e.g., using `ptrtoint`) to be location-independent. The following example is *not* considered a return-only capture, even though the `ptrtoint` ultimately only contributes to the return value:

    @lookup = constant [4 x i8] [i8 0, i8 1, i8 2, i8 3]

    define ptr @f(ptr %a) {
      %a.addr = ptrtoint ptr %a to i64
      %mask = and i64 %a.addr, 3
      %gep = getelementptr i8, ptr @lookup, i64 %mask
      ret ptr %gep
    }

This definition is chosen to allow capture analysis to continue with the return value in the usual fashion.

<a id="inference"></a>

#### Inference

The definitions given above are permissive to facilitate frontend-driven annotations based on language semantics. As inference generally cannot know how pointers will be used after the function returns, it needs to make conservative assumptions. Here is an example set of rules that could be used to infer `captures`:

- Volatile memory accesses capture the address of the pointer.

- getelementptr, bitcast, addrspacecast, select, phi: Do not capture anything.

- load, va_arg: Do not capture anything (unless volatile).

- icmp, ptrtoaddr: Captures only address.

- ptrtoint: Captures address and provenance.

- call/invoke: Depends on `captures` on arguments. The callee is never captured.

- store, atomicrmw, cmpxchg: Capture the address and provenance of the value operand. Do not capture the pointer operand (unless volatile).

- Other (including insertvalue and insertelement): Conservatively assume address and provenance are captured.

<a id="volatile-memory-accesses"></a>

<a id="volatile"></a>

### Volatile Memory Accesses

Certain memory accesses, such as [load](instructions-memory.md#i-load)’s, [store](instructions-memory.md#i-store)’s, and [llvm.memcpy](intrinsics-libc-and-arithmetic.md#int-memcpy)’s may be marked `volatile`. The optimizers must not change the number of volatile operations or change their order of execution relative to other volatile operations. The optimizers *may* change the order of volatile operations relative to non-volatile operations. This is not Java’s “volatile” and has no cross-thread synchronization behavior.

A volatile load or store may have additional target-specific semantics. Any volatile operation can have side effects, and any volatile operation can read and/or modify state which is not accessible via a regular load or store in this module. Volatile operations may use addresses which do not point to memory (like MMIO registers). This means the compiler may not use a volatile operation to prove a non-volatile access to that address has defined behavior. This includes addresses typically forbidden, such as the pointer with bit-value 0.

The allowed side-effects for volatile accesses are limited. If a non-volatile store to a given address would be legal, a volatile operation may modify the memory at that address. A volatile operation may not modify any other memory accessible by the module being compiled. A volatile operation may not call any code in the current module.

In general (without target-specific context), the address space of a volatile operation may not be changed. Different address spaces may have different trapping behavior when dereferencing an invalid pointer.

Volatile operations are permitted to trap. The compiler may not assume that execution will continue after a volatile operation.

IR-level volatile loads and stores cannot safely be optimized into `llvm.memcpy` or `llvm.memmove` intrinsics even when those intrinsics are flagged volatile. Likewise, the backend should never split or merge target-legal volatile load/store instructions. Similarly, IR-level volatile loads and stores cannot change from integer to floating-point or vice versa.

Rationale

Platforms may rely on volatile loads and stores of natively supported data width to be executed as single instruction. For example, in C this holds for an l-value of volatile primitive type with native hardware support, but not necessarily for aggregate types. The frontend upholds these expectations, which are intentionally unspecified in the IR. The rules above ensure that IR transformations do not violate the frontend’s contract with the language.

<a id="memory-model-for-concurrent-operations"></a>

<a id="memmodel"></a>

### Memory Model for Concurrent Operations

The LLVM IR does not define any way to start parallel threads of execution or to register signal handlers. Nonetheless, there are platform-specific ways to create them, and we define LLVM IR’s behavior in their presence. This model is inspired by the C++ memory model.

For a more informal introduction to this model, see the [LLVM Atomic Instructions and Concurrency Guide](Atomics.html).

We define a *happens-before* partial order as the least partial order that

- Is a superset of single-thread program order, and

- When `a` *synchronizes-with* `b`, includes an edge from `a` to `b`. *Synchronizes-with* pairs are introduced by platform-specific techniques, like pthread locks, thread creation, thread joining, etc., and by atomic instructions. (See also [Atomic Memory Ordering Constraints](#ordering)).

Note that program order does not introduce *happens-before* edges between a thread and signals executing inside that thread.

Every (defined) read operation (load instructions, memcpy, atomic loads/read-modify-writes, etc.) R reads a series of bytes written by (defined) write operations (store instructions, atomic stores/read-modify-writes, memcpy, etc.). For the purposes of this section, initialized globals are considered to have a write of the initializer which is atomic and happens before any other read or write of the memory in question. For each byte of a read R, R<sub>byte</sub> may see any write to the same byte, except:

- If write<sub>1</sub> happens before write<sub>2</sub>, and write<sub>2</sub> happens before R<sub>byte</sub>, then R<sub>byte</sub> does not see write<sub>1</sub>.

- If R<sub>byte</sub> happens before write<sub>3</sub>, then R<sub>byte</sub> does not see write<sub>3</sub>.

Given that definition, R<sub>byte</sub> is defined as follows:

- If R is volatile, the result is target-dependent. (Volatile is supposed to give guarantees which can support `sig_atomic_t` in C/C++, and may be used for accesses to addresses that do not behave like normal memory. It does not generally provide cross-thread synchronization.)

- Otherwise, if there is no write to the same byte that happens before R<sub>byte</sub>, R<sub>byte</sub> returns `undef` for that byte.

- Otherwise, if R<sub>byte</sub> may see exactly one write, R<sub>byte</sub> returns the value written by that write.

- Otherwise, if R is atomic, and all the writes R<sub>byte</sub> may see are atomic, it chooses one of the values written. See the [Atomic Memory Ordering Constraints](#ordering) section for additional constraints on how the choice is made. Targets may impose additional requirements on R and the writes it may see based on their `syncscope`.

- Otherwise R<sub>byte</sub> returns `undef`.

R returns the value composed of the series of bytes it read. This implies that some bytes within the value may be `undef` **without** the entire value being `undef`. Note that this only defines the semantics of the operation; it doesn’t mean that targets will emit more than one instruction to read the series of bytes.

Note that in cases where none of the atomic intrinsics are used, this model places only one restriction on IR transformations on top of what is required for single-threaded execution: introducing a store to a byte which might not otherwise be stored is not allowed in general. (Specifically, in the case where another thread might write to and read from an address, introducing a store can change a load that may see exactly one write into a load that may see multiple writes.)

<a id="atomic-memory-ordering-constraints"></a>

<a id="ordering"></a>

### Atomic Memory Ordering Constraints

Atomic instructions ([cmpxchg](instructions-memory.md#i-cmpxchg), [atomicrmw](instructions-memory.md#i-atomicrmw), [fence](instructions-memory.md#i-fence), [atomic load](instructions-memory.md#i-load), and [atomic store](instructions-memory.md#i-store)) take ordering parameters that determine which other atomic instructions on the same address they *synchronize with*. These semantics implement the Java or C++ memory models; if these descriptions aren’t precise enough, check those specs (see spec references in the [atomics guide](Atomics.html)). [fence](instructions-memory.md#i-fence) instructions treat these orderings somewhat differently since they don’t take an address. See that instruction’s documentation for details.

For a simpler introduction to the ordering constraints, see the [LLVM Atomic Instructions and Concurrency Guide](Atomics.html).

`unordered`  
The set of values that can be read is governed by the happens-before partial order. A value cannot be read unless some operation wrote it. This is intended to provide a guarantee strong enough to model Java’s non-volatile shared variables. This ordering cannot be specified for read-modify-write operations; it is not strong enough to make them atomic in any interesting way.

`monotonic`  
In addition to the guarantees of `unordered`, there is a single total order for modifications by `monotonic` operations on each address. All modification orders must be compatible with the happens-before order. There is no guarantee that the modification orders can be combined to a global total order for the whole program (and this often will not be possible). If the read in an atomic read-modify-write operation M ([cmpxchg](instructions-memory.md#i-cmpxchg) and [atomicrmw](instructions-memory.md#i-atomicrmw)) reads from a `monotonic` (or stronger) write W, W must be immediately before M in the address’s modification order. If one atomic read happens before another atomic read of the same address and both are at least `monotonic`, the later read must not see an earlier value in the address’s modification order. This disallows reordering of `monotonic` (or stronger) operations on the same address. If an address is written `monotonic`-ally by one thread, and other threads `monotonic`-ally read that address repeatedly, the other threads must eventually see the write. This corresponds to the C/C++ `memory_order_relaxed`.

`acquire`  
In addition to the guarantees of `monotonic`, a *synchronizes-with* edge may be formed with a `release` operation. This is intended to model C/C++’s `memory_order_acquire`.

`release`  
In addition to the guarantees of `monotonic`, if this operation writes a value which is subsequently read by an `acquire` operation, it *synchronizes-with* that operation. Furthermore, this occurs even if the value written by a `release` operation has been modified by a read-modify-write operation before being read. (Such a set of operations comprises a *release sequence*). This corresponds to the C/C++ `memory_order_release`.

`acq_rel` (acquire+release)  
Acts as both an `acquire` and `release` operation on its address. This corresponds to the C/C++ `memory_order_acq_rel`.

`seq_cst` (sequentially consistent)  
In addition to the guarantees of `acq_rel` (`acquire` for an operation that only reads, `release` for an operation that only writes), there is a global total order on all sequentially-consistent operations on all addresses. If an address is only accessed through sequentially-consistent operations, each sequentially-consistent read of that address sees the last preceding write to the same address in this global order. This corresponds to the C/C++ `memory_order_seq_cst` and Java `volatile`.

Note: this global total order is *not* guaranteed to be fully consistent with the *happens-before* partial order if non-`seq_cst` accesses are involved. See the C++ standard [[atomics.order]](https://wg21.link/atomics.order) section for more details on the exact guarantees.

If an atomic operation is marked `syncscope("singlethread")`, it only *synchronizes with* other operations running in the same thread (for example, in signal handlers) and it is related in the `seq_cst` order and the monotonic modification order with other operations in the same thread.

If an atomic operation is marked `syncscope("<target-scope>")`, where `<target-scope>` is a target-specific synchronization scope, then it is target-dependent if it *synchronizes with* other operations and if it is related with other operations in the `seq_cst` order and the monotonic modification order.

Otherwise, an atomic operation that is not marked `syncscope("singlethread")` or `syncscope("<target-scope>")` *synchronizes with* and is related in the `seq_cst` order and the monotonic modification order with other operations that are not marked `syncscope("singlethread")` or `syncscope("<target-scope>")`.

<a id="elementwise-atomic-operations"></a>

<a id="elementwise-atomics"></a>

### Elementwise Atomic Operations

The [atomicrmw](instructions-memory.md#i-atomicrmw) instruction may be marked `elementwise`. The access type must then be a fixed vector type whose total bit width is a power of two and whose element type is supported by the corresponding scalar atomic instruction. The [ordering](#ordering) of an `elementwise` instruction may not be `seq_cst`.

An `elementwise` atomic instruction behaves as if it were expanded into one scalar version of that instruction for each vector element. Each resulting scalar operation has the same [ordering](#ordering) and `syncscope` as the original instruction. Each scalar operation occupies the original instruction’s position in program order relative to other operations, but the scalar operations are not related in program order with respect to one another. Synchronizing with one scalar operation therefore does not, by itself, establish a happens-before relationship with any other scalar operation from the same `elementwise` instruction.

Without `elementwise`, vector `atomicrmw` instructions are performed atomically over the entire vector operation.

<a id="floating-point-environment"></a>

<a id="floatenv"></a>

### Floating-Point Environment

The default LLVM floating-point environment assumes that traps are disabled and status flags are not observable. Therefore, floating-point math operations do not have side effects and may be speculated freely. Results assume the round-to-nearest rounding mode, and subnormals are assumed to be preserved.

Running LLVM code in an environment where these assumptions are not met typically leads to undefined behavior. The `strictfp` and [denormal_fpenv](#denormal-fpenv) attributes as well as [Constrained Floating-Point Intrinsics](intrinsics-floating-point.md#constrainedfp) can be used to weaken LLVM’s assumptions and ensure defined behavior in non-default floating-point environments; see their respective documentation for details.

<a id="behavior-of-floating-point-nan-values"></a>

<a id="floatnan"></a>

### Behavior of Floating-Point NaN values

A floating-point NaN value consists of a sign bit, a quiet/signaling bit, and a payload (which makes up the rest of the mantissa except for the quiet/signaling bit). LLVM assumes that the quiet/signaling bit being set to `1` indicates a quiet NaN (QNaN), and a value of `0` indicates a signaling NaN (SNaN). In the following we will hence just call it the “quiet bit”.

The representation bits of a floating-point value do not mutate arbitrarily; in particular, if there is no floating-point operation being performed, NaN signs, quiet bits, and payloads are preserved.

For the purpose of this section, `bitcast` as well as the following operations are not “floating-point math operations”: `fneg`, `llvm.fabs`, and `llvm.copysign`. These operations act directly on the underlying bit representation and never change anything except possibly for the sign bit.

Floating-point math operations that return a NaN are an exception from the general principle that LLVM implements IEEE 754 semantics. Unless specified otherwise, the following rules apply whenever the IEEE 754 semantics say that a NaN value is returned: the result has a non-deterministic sign; the quiet bit and payload are non-deterministically chosen from the following set of options:

- The quiet bit is set and the payload is all-zero. (“Preferred NaN” case)

- The quiet bit is set and the payload is copied from any input operand that is a NaN. (“Quieting NaN propagation” case)

- The quiet bit and payload are copied from any input operand that is a NaN. (“Unchanged NaN propagation” case)

- The quiet bit is set and the payload is picked from a target-specific set of “extra” possible NaN payloads. The set can depend on the input operand values. This set is empty on x86 and ARM, but can be non-empty on other architectures. (For instance, on wasm, if any input NaN does not have the preferred all-zero payload or any input NaN is an SNaN, then this set contains all possible payloads; otherwise, it is empty. On SPARC, this set consists of the all-one payload.)

In particular, if all input NaNs are quiet (or if there are no input NaNs), then the output NaN is definitely quiet. Signaling NaN outputs can only occur if they are provided as an input value. For example, “fmul SNaN, 1.0” may be simplified to SNaN rather than QNaN. Similarly, if all input NaNs are preferred (or if there are no input NaNs) and the target does not have any “extra” NaN payloads, then the output NaN is guaranteed to be preferred.

Floating-point math operations are allowed to treat all NaNs as if they were quiet NaNs. For example, “pow(1.0, SNaN)” may be simplified to 1.0.

Code that requires different behavior than this should use the [Constrained Floating-Point Intrinsics](intrinsics-floating-point.md#constrainedfp). In particular, constrained intrinsics rule out the “Unchanged NaN propagation” case; they are guaranteed to return a QNaN.

Unfortunately, due to hard-or-impossible-to-fix issues, LLVM violates its own specification on some architectures:

- x86-32 without SSE2 enabled may convert floating-point values to x86_fp80 and back when performing floating-point math operations; this can lead to results with different precision than expected and it can alter NaN values. Since optimizations can make contradicting assumptions, this can lead to arbitrary miscompilations. See [issue #44218](https://github.com/llvm/llvm-project/issues/44218).

- x86-32 (even with SSE2 enabled) may implicitly perform such a conversion on values returned from a function for some calling conventions. See [issue #66803](https://github.com/llvm/llvm-project/issues/66803).

- Older MIPS versions use the opposite polarity for the quiet/signaling bit, and LLVM does not correctly represent this. See [issue #60796](https://github.com/llvm/llvm-project/issues/60796).

<a id="floating-point-semantics"></a>

<a id="floatsem"></a>

### Floating-Point Semantics

This section defines the semantics for core floating-point operations on types that use a format specified by IEEE 754. These types are: `half`, `float`, `double`, and `fp128`, which correspond to the binary16, binary32, binary64, and binary128 formats, respectively. The “core” operations are those defined in section 5 of IEEE 754, which all have corresponding LLVM operations.

The value returned by those operations matches that of the corresponding IEEE 754 operation executed in the [default LLVM floating-point environment](#floatenv), except that the behavior of NaN results is instead [as specified here](#floatnan). In particular, such a floating-point instruction returning a non-NaN value is guaranteed to always return the same bit-identical result on all machines and optimization levels.

This means that optimizations and backends may not change the observed bitwise result of these operations in any way (unless NaNs are returned), and frontends can rely on these operations providing correctly rounded results as described in the standard.

(Note that this is only about the value returned by these operations; see the [floating-point environment section](#floatenv) regarding flags and exceptions.)

Various flags, attributes, and metadata can alter the behavior of these operations and thus make them not bit-identical across machines and optimization levels any more: most notably, the [fast-math flags](#fastmath) as well as the [strictfp](#strictfp) and [denormal_fpenv](#denormal-fpenv) attributes and fpmath metadata \<fpmath-metadata\>. See their corresponding documentation for details.

<a id="fast-math-flags"></a>

<a id="fastmath"></a>

### Fast-Math Flags

LLVM IR floating-point operations ([fneg](instructions-arithmetic.md#i-fneg), [fadd](instructions-arithmetic.md#i-fadd), [fsub](instructions-arithmetic.md#i-fsub), [fmul](instructions-arithmetic.md#i-fmul), [fdiv](instructions-arithmetic.md#i-fdiv), [frem](instructions-arithmetic.md#i-frem), [fcmp](instructions-other.md#i-fcmp), [fptrunc](instructions-conversion.md#i-fptrunc), [fpext](instructions-conversion.md#i-fpext)), [uitofp](instructions-conversion.md#i-uitofp), [sitofp](instructions-conversion.md#i-sitofp), and [phi](instructions-other.md#i-phi), [select](instructions-other.md#i-select), or [call](instructions-other.md#i-call) instructions that return floating-point types may use the following flags to enable otherwise unsafe floating-point transformations.

`fast`  
This flag is a shorthand for specifying all fast-math flags at once, and imparts no additional semantics from using all of them.

`nnan`  
No NaNs - Allow optimizations to assume the arguments and result are not NaN. If an argument is a nan, or the result would be a nan, it produces a [poison value](constants.md#poisonvalues) instead.

`ninf`  
No Infs - Allow optimizations to assume the arguments and result are not +/-Inf. If an argument is +/-Inf, or the result would be +/-Inf, it produces a [poison value](constants.md#poisonvalues) instead.

`nsz`  
No Signed Zeros - Unless otherwise mentioned, the sign bit of 0.0 or -0.0 input operands can be non-deterministically flipped. This does not imply that -0.0 is poison and/or guaranteed to not exist in the operation.

Note: For [phi](instructions-other.md#i-phi), [select](instructions-other.md#i-select), and [call](instructions-other.md#i-call) instructions, the following return types are considered to be floating-point types:

- Floating-point scalar or vector types

- Array types (nested to any depth) of floating-point scalar or vector types

- Homogeneous literal struct types of floating-point scalar or vector types

<a id="rewrite-based-flags"></a>

#### Rewrite-based flags

The following flags have rewrite-based semantics. These flags allow expressions, potentially containing multiple non-consecutive instructions, to be rewritten into alternative instructions. When multiple instructions are involved in an expression, it is necessary that all of the instructions have the necessary rewrite-based flag present on them, and the rewritten instructions will generally have the intersection of the flags present on the input instruction.

In the following example, the floating-point expression in the body of `@orig` has `contract` and `reassoc` in common, and thus if it is rewritten into the expression in the body of `@target`, all of the new instructions get those two flags and only those flags as a result. Since the `arcp` is present on only one of the instructions in the expression, it is not present in the transformed expression. Furthermore, this reassociation here is only legal because both the instructions had the `reassoc` flag; if only one had it, it would not be legal to make the transformation.

    define double @orig(double %a, double %b, double %c) {
      %t1 = fmul contract reassoc double %a, %b
      %val = fmul contract reassoc arcp double %t1, %c
      ret double %val
    }

    define double @target(double %a, double %b, double %c) {
      %t1 = fmul contract reassoc double %b, %c
      %val = fmul contract reassoc double %a, %t1
      ret double %val
    }

These rules do not apply to the other fast-math flags. Whether or not a flag like `nnan` is present on any or all of the rewritten instructions is based on whether or not it is possible for said instruction to have a NaN input or output, given the original flags.

`arcp`  
Allows division to be treated as a multiplication by a reciprocal. Specifically, this permits `a / b` to be considered equivalent to `a * (1.0 / b)` (which may subsequently be susceptible to code motion), and it also permits `a / (b / c)` to be considered equivalent to `a * (c / b)`. Both of these rewrites can be applied in either direction: `a * (c / b)` can be rewritten into `a / (b / c)`.

`contract`  
Allow floating-point contraction (e.g., fusing a multiply followed by an addition into a fused multiply-and-add). This does not enable reassociation to form arbitrary contractions. For example, `(a*b) + (c*d) + e` can not be transformed into `(a*b) + ((c*d) + e)` to create two fma operations.

<a id="fastmath-afn"></a>

`afn`  
Approximate functions - Allow substitution of approximate calculations for functions (sin, log, sqrt, etc). See floating-point intrinsic definitions for places where this can apply to LLVM’s intrinsic math functions.

`reassoc`  
Allow algebraically equivalent transformations for floating-point instructions such as reassociation transformations. This may dramatically change results in floating-point.

<a id="use-list-order-directives"></a>

<a id="uselistorder"></a>

### Use-list Order Directives

Use-list directives encode the in-memory order of each use-list, allowing the order to be recreated. `<order-indexes>` is a comma-separated list of indexes that are assigned to the referenced value’s uses. The referenced value’s use-list is immediately sorted by these indexes.

Use-list directives may appear at function scope or global scope. They are not instructions, and have no effect on the semantics of the IR. When they’re at function scope, they must appear after the terminator of the final basic block.

**Syntax:**

    uselistorder <ty> <value>, { <order-indexes> }

**Examples:**

    define void @foo(i32 %arg1, i32 %arg2) {
    entry:
      ; ... instructions ...
    bb:
      ; ... instructions ...

      ; At function scope.
      uselistorder i32 %arg1, { 1, 0, 2 }
      uselistorder label %bb, { 1, 0 }
    }

    ; At global scope.
    uselistorder ptr @global, { 1, 2, 0 }
    uselistorder i32 7, { 1, 0 }
    uselistorder i32 (i32) @bar, { 1, 0 }

<a id="source-filename"></a>

<a id="id3"></a>

### Source Filename

The *source filename* string is set to the original module identifier, which will be the name of the compiled source file when compiling from source through the clang front end, for example. It is then preserved through the IR and bitcode.

This is currently necessary to generate a consistent unique global identifier for local functions used in profile data, which prepends the source file name to the local function name.

The syntax for the source file name is simply:

    source_filename = "/path/to/source.c"
