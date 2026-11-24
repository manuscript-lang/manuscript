[Wiki](../index.md) › [LLVM LangRef](index.md)

# Memory access and addressing

LLVM 23.1.0 Language Reference, part of the [index](index.md). Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html>. License: Apache-2.0 with LLVM exception.

<a id="memory-access-and-addressing-operations"></a>

<a id="memoryops"></a>

### Memory Access and Addressing Operations

A key design point of an SSA-based representation is how it represents memory. In LLVM, no memory locations are in SSA form, which makes things very simple. This section describes how to read, write, and allocate memory in LLVM.

<a id="alloca-instruction"></a>

<a id="i-alloca"></a>

#### ‘`alloca`’ Instruction

<a id="id204"></a>

##### Syntax:

    <result> = alloca [inalloca] <type> [, <ty> <NumElements>] [, align <alignment>] [, addrspace(<num>)]     ; yields type addrspace(num)*:result

<a id="id205"></a>

##### Overview:

The ‘`alloca`’ instruction allocates memory on the stack frame of the currently executing function, to be automatically released when this function returns to its caller. If the address space is not explicitly specified, the default address space 0 is used.

<a id="id206"></a>

##### Arguments:

The ‘`alloca`’ instruction allocates `sizeof(<type>)*NumElements` bytes of memory on the runtime stack, returning a pointer of the appropriate type to the program. If “NumElements” is specified, it is the number of elements allocated, otherwise “NumElements” is defaulted to be one.

If a constant alignment is specified, the value result of the allocation is guaranteed to be aligned to at least that boundary. The alignment may not be greater than `1 << 32`.

The alignment is only optional when parsing textual IR; for in-memory IR, it is always present. If not specified, the target can choose to align the allocation on any convenient boundary compatible with the type.

‘`type`’ may be any sized type.

Structs containing scalable vectors cannot be used in allocas unless all fields are the same scalable vector type (e.g., `{<vscale x 2 x i32>, <vscale x 2 x i32>}` contains the same type while `{<vscale x 2 x i32>, <vscale x 2 x i64>}` doesn’t).

<a id="id207"></a>

##### Semantics:

Memory is allocated; a pointer is returned. The allocated memory is uninitialized, and loading from uninitialized memory produces an undefined value. The operation itself is undefined if there is insufficient stack space for the allocation.’`alloca`’d memory is automatically released when the function returns. The ‘`alloca`’ instruction is commonly used to represent automatic variables that must have an address available. When the function returns (either with the `ret` or `resume` instructions), the memory is reclaimed. Allocating zero bytes is legal, but the returned pointer may not be unique. The order in which memory is allocated (ie., which way the stack grows) is not specified.

Note that ‘`alloca`’ outside of the alloca address space from the [datalayout string](high-level-structure.md#langref-datalayout) is meaningful only if the target has assigned it a semantics. For targets that specify a non-zero alloca address space in the [datalayout string](high-level-structure.md#langref-datalayout), the alloca address space needs to be explicitly specified in the instruction if it is to be used.

If the returned pointer is used by [llvm.lifetime.start](intrinsics-general.md#int-lifestart), the returned object is initially dead. See [llvm.lifetime.start](intrinsics-general.md#int-lifestart) and [llvm.lifetime.end](intrinsics-general.md#int-lifeend) for the precise semantics of lifetime-manipulating intrinsics.

If the element count is `undef` or `poison`, this instruction has undefined behavior.

<a id="id208"></a>

##### Example:

    %ptr = alloca i32                             ; yields ptr
    %ptr = alloca i32, i32 4                      ; yields ptr
    %ptr = alloca i32, i32 4, align 1024          ; yields ptr
    %ptr = alloca i32, align 1024                 ; yields ptr

<a id="load-instruction"></a>

<a id="i-load"></a>

#### ‘`load`’ Instruction

<a id="id209"></a>

##### Syntax:

    <result> = load [volatile] <ty>, ptr <pointer>[, align <alignment>][, !nontemporal !<nontemp_node>][, !invariant.load !<empty_node>][, !invariant.group !<empty_node>][, !nonnull !<empty_node>][, !dereferenceable !<deref_bytes_node>][, !dereferenceable_or_null !<deref_bytes_node>][, !align !<align_node>][, !noundef !<empty_node>]
    <result> = load atomic [volatile] <ty>, ptr <pointer> [syncscope("<target-scope>")] <ordering>, align <alignment> [, !invariant.group !<empty_node>]
    !<nontemp_node> = !{ i32 1 }
    !<empty_node> = !{}
    !<deref_bytes_node> = !{ i64 <dereferenceable_bytes> }
    !<align_node> = !{ i64 <value_alignment> }

<a id="id210"></a>

##### Overview:

The ‘`load`’ instruction is used to read from memory.

<a id="id211"></a>

##### Arguments:

The argument to the `load` instruction specifies the memory address from which to load. The type specified must be a [first class](type-system.md#t-firstclass) type of known size (i.e., not containing an [opaque structural type](type-system.md#t-opaque)). If the `load` is marked as `volatile`, then the optimizer is not allowed to modify the number or order of execution of this `load` with other [volatile operations](high-level-structure.md#volatile).

If the `load` is marked as `atomic`, it takes an extra [ordering](high-level-structure.md#ordering) and optional `syncscope("<target-scope>")` argument. The `release` and `acq_rel` orderings are not valid on `load` instructions. Atomic loads produce [defined](high-level-structure.md#memmodel) results when they may see multiple atomic stores. The type of the pointee must be an integer, pointer, floating-point, or vector type whose bit width is a power of two greater than or equal to eight. `align` must be explicitly specified on atomic loads. Note: if the alignment is not greater or equal to the size of the `<value>` type, the atomic operation is likely to require a lock and have poor performance. `!nontemporal` does not have any defined semantics for atomic loads.

The optional constant `align` argument specifies the alignment of the operation (that is, the alignment of the memory address). It is the responsibility of the code emitter to ensure that the alignment information is correct. Overestimating the alignment results in undefined behavior. Underestimating the alignment may produce less efficient code. An alignment of 1 is always safe. The maximum possible alignment is `1 << 32`. An alignment value higher than the size of the loaded type does *not* imply (without target specific knowledge) that memory up to the alignment value bytes can be safely loaded without trapping.

The alignment is only optional when parsing textual IR; for in-memory IR, it is always present. An omitted `align` argument means that the operation has the ABI alignment for the target.

The optional `!nontemporal` metadata must reference a single metadata name `<nontemp_node>` corresponding to a metadata node with one `i32` entry of value 1. The existence of the `!nontemporal` metadata on the instruction tells the optimizer and code generator that this load is not expected to be reused in the cache. The code generator may select special instructions to save cache bandwidth, such as the `MOVNT` instruction on x86.

The optional `!invariant.load` metadata must reference a single metadata name `<empty_node>` corresponding to a metadata node with no entries. See `invariant.load` metadata [invariant.load](metadata.md#md-invariant-load).

The optional `!invariant.group` metadata must reference a single metadata name  
`<empty_node>` corresponding to a metadata node with no entries. See `invariant.group` metadata [invariant.group](metadata.md#md-invariant-group).

The optional `!nonnull` metadata must reference a single metadata name `<empty_node>` corresponding to a metadata node with no entries. The existence of the `!nonnull` metadata on the instruction tells the optimizer that the value loaded is known to never be null. If the value is null at runtime, a poison value is returned instead. This is analogous to the `nonnull` attribute on parameters and return values. This metadata can only be applied to loads of a pointer type.

The optional `!dereferenceable` metadata must reference a single metadata name `<deref_bytes_node>` corresponding to a metadata node with one `i64` entry. See `dereferenceable` metadata [dereferenceable](metadata.md#md-dereferenceable).

The optional `!dereferenceable_or_null` metadata must reference a single metadata name `<deref_bytes_node>` corresponding to a metadata node with one `i64` entry. See `dereferenceable_or_null` metadata [dereferenceable_or_null](metadata.md#md-dereferenceable-or-null).

The optional `!align` metadata must reference a single metadata name `<align_node>` corresponding to a metadata node with one `i64` entry. The existence of the `!align` metadata on the instruction tells the optimizer that the value loaded is known to be aligned to a boundary specified by the integer value in the metadata node. The alignment must be a power of 2. This is analogous to the ‘’align’’ attribute on parameters and return values. This metadata can only be applied to loads of a pointer type. If the returned value is not appropriately aligned at runtime, a poison value is returned instead.

The optional `!noundef` metadata must reference a single metadata name `<empty_node>` corresponding to a node with no entries. The existence of `!noundef` metadata on the instruction tells the optimizer that the value loaded is known to be [well defined](constants.md#welldefinedvalues). If the value isn’t well defined, the behavior is undefined. If the `!noundef` metadata is combined with poison-generating metadata like `!nonnull`, violation of that metadata constraint will also result in undefined behavior.

<a id="id212"></a>

##### Semantics:

The location of memory pointed to is loaded. If the value being loaded is of scalar type then the number of bytes read does not exceed the minimum number of bytes needed to hold all bits of the type. For example, loading an `i24` reads at most three bytes. When loading a value of a type like `i20` with a size that is not an integral number of bytes, the load will be performed on the next larger multiple of the byte size (here `i24`) and truncated. If any of the truncated bits are non-zero, the result is a poison value. As such, a non-byte-sized load behaves like a byte-sized load followed by a `trunc nuw` operation.

If the value being loaded is of aggregate type, the bytes that correspond to padding may be accessed but are ignored, because it is impossible to observe padding from the loaded aggregate value. If `<pointer>` is not a well-defined value, the behavior is undefined. The behavior of loading a value of a type that differs from the type used to store it is described in the [bitcast](instructions-conversion.md#i-bitcast) section.

<a id="id213"></a>

##### Examples:

    %ptr = alloca i32                               ; yields ptr
    store i32 3, ptr %ptr                           ; yields void
    %val = load i32, ptr %ptr                       ; yields i32:val = i32 3

<a id="store-instruction"></a>

<a id="i-store"></a>

#### ‘`store`’ Instruction

<a id="id214"></a>

##### Syntax:

    store [volatile] <ty> <value>, ptr <pointer>[, align <alignment>][, !nontemporal !<nontemp_node>][, !invariant.group !<empty_node>]        ; yields void
    store atomic [volatile] <ty> <value>, ptr <pointer> [syncscope("<target-scope>")] <ordering>, align <alignment> [, !invariant.group !<empty_node>] ; yields void
    !<nontemp_node> = !{ i32 1 }
    !<empty_node> = !{}

<a id="id215"></a>

##### Overview:

The ‘`store`’ instruction is used to write to memory.

<a id="id216"></a>

##### Arguments:

There are two arguments to the `store` instruction: a value to store and an address at which to store it. The type of the `<pointer>` operand must be a pointer to the [first class](type-system.md#t-firstclass) type of the `<value>` operand. If the `store` is marked as `volatile`, then the optimizer is not allowed to modify the number or order of execution of this `store` with other [volatile operations](high-level-structure.md#volatile). Only values of [first class](type-system.md#t-firstclass) types of known size (i.e., not containing an [opaque structural type](type-system.md#t-opaque)) can be stored.

If the `store` is marked as `atomic`, it takes an extra [ordering](high-level-structure.md#ordering) and optional `syncscope("<target-scope>")` argument. The `acquire` and `acq_rel` orderings aren’t valid on `store` instructions. Atomic loads produce [defined](high-level-structure.md#memmodel) results when they may see multiple atomic stores. The type of the pointee must be an integer, pointer, floating-point, or vector type whose bit width is a power of two greater than or equal to eight. `align` must be explicitly specified on atomic stores. Note: if the alignment is not greater or equal to the size of the `<value>` type, the atomic operation is likely to require a lock and have poor performance. `!nontemporal` does not have any defined semantics for atomic stores.

The optional constant `align` argument specifies the alignment of the operation (that is, the alignment of the memory address). It is the responsibility of the code emitter to ensure that the alignment information is correct. Overestimating the alignment results in undefined behavior. Underestimating the alignment may produce less efficient code. An alignment of 1 is always safe. The maximum possible alignment is `1 << 32`. An alignment value higher than the size of the stored type does *not* imply (without target specific knowledge) that memory up to the alignment value bytes can be safely loaded without trapping.

The alignment is only optional when parsing textual IR; for in-memory IR, it is always present. An omitted `align` argument means that the operation has the ABI alignment for the target.

The optional `!nontemporal` metadata must reference a single metadata name `<nontemp_node>` corresponding to a metadata node with one `i32` entry of value 1. The existence of the `!nontemporal` metadata on the instruction tells the optimizer and code generator that this load is not expected to be reused in the cache. The code generator may select special instructions to save cache bandwidth, such as the `MOVNT` instruction on x86.

The optional `!invariant.group` metadata must reference a single metadata name `<empty_node>`. See `invariant.group` metadata.

<a id="id217"></a>

##### Semantics:

The contents of memory are updated to contain `<value>` at the location specified by the `<pointer>` operand. If `<value>` is of scalar type then the number of bytes written does not exceed the minimum number of bytes needed to hold all bits of the type. For example, storing an `i24` writes at most three bytes. When writing a value of a type like `i20` with a size that is not an integral number of bytes, the value will be zero extended to the next larger multiple of the byte size (here `i24`) and then stored. As such, a non-byte-sized store behaves like a `zext` followed by a byte-sized store.

If `<value>` is of aggregate type, padding is filled with [undef](constants.md#undefvalues). If `<pointer>` is not a well-defined value, the behavior is undefined.

<a id="id218"></a>

##### Example:

    %ptr = alloca i32                               ; yields ptr
    store i32 3, ptr %ptr                           ; yields void
    %val = load i32, ptr %ptr                       ; yields i32:val = i32 3

<a id="fence-instruction"></a>

<a id="i-fence"></a>

#### ‘`fence`’ Instruction

<a id="id219"></a>

##### Syntax:

    fence [syncscope("<target-scope>")] <ordering>  ; yields void

<a id="id220"></a>

##### Overview:

The ‘`fence`’ instruction is used to introduce happens-before edges between operations.

<a id="id221"></a>

##### Arguments:

‘`fence`’ instructions take an [ordering](high-level-structure.md#ordering) argument which defines what *synchronizes-with* edges they add. They can only be given `acquire`, `release`, `acq_rel`, and `seq_cst` orderings.

<a id="id222"></a>

##### Semantics:

A fence A which has (at least) `release` ordering semantics *synchronizes with* a fence B with (at least) `acquire` ordering semantics if and only if there exist atomic operations X and Y, both operating on some atomic object M, such that A is sequenced before X, X modifies M (either directly or through some side effect of a sequence headed by X), Y is sequenced before B, and Y observes M. This provides a *happens-before* dependency between A and B. Rather than an explicit `fence`, one (but not both) of the atomic operations X or Y might provide a `release` or `acquire` (resp.) ordering constraint and still *synchronize-with* the explicit `fence` and establish the *happens-before* edge.

A `fence` which has `seq_cst` ordering, in addition to having both `acquire` and `release` semantics specified above, participates in the global program order of other `seq_cst` operations and/or fences. Furthermore, the global ordering created by a `seq_cst` fence must be compatible with the individual total orders of `monotonic` (or stronger) memory accesses occurring before and after such a fence. The exact semantics of this interaction are somewhat complicated, see the C++ standard’s [[atomics.order]](https://wg21.link/atomics.order) section for more details.

A `fence` instruction can also take an optional “[syncscope](#syncscope)” argument.

<a id="id223"></a>

##### Example:

    fence acquire                                        ; yields void
    fence syncscope("singlethread") seq_cst              ; yields void
    fence syncscope("agent") seq_cst                     ; yields void

<a id="cmpxchg-instruction"></a>

<a id="i-cmpxchg"></a>

#### ‘`cmpxchg`’ Instruction

<a id="id224"></a>

##### Syntax:

    cmpxchg [weak] [volatile] ptr <pointer>, <ty> <cmp>, <ty> <new> [syncscope("<target-scope>")] <success ordering> <failure ordering>[, align <alignment>] ; yields  { ty, i1 }

<a id="id225"></a>

##### Overview:

The ‘`cmpxchg`’ instruction is used to atomically modify memory. It loads a value in memory and compares it to a given value. If they are equal, it tries to store a new value into the memory.

<a id="id226"></a>

##### Arguments:

There are three arguments to the ‘`cmpxchg`’ instruction: an address to operate on, a value to compare to the value currently be at that address, and a new value to place at that address if the compared values are equal. The type of `<cmp>` must be an integer or pointer type whose bit width is a power of two greater than or equal to eight. `<cmp>` and `<new>` must have the same type, and the type of `<pointer>` must be a pointer to that type. If the `cmpxchg` is marked as `volatile`, then the optimizer is not allowed to modify the number or order of execution of this `cmpxchg` with other [volatile operations](high-level-structure.md#volatile).

The success and failure [ordering](high-level-structure.md#ordering) arguments specify how this `cmpxchg` synchronizes with other atomic operations. Both ordering parameters must be at least `monotonic`, the failure ordering cannot be either `release` or `acq_rel`.

A `cmpxchg` instruction can also take an optional “[syncscope](#syncscope)” argument.

Note: if the alignment is not greater or equal to the size of the `<value>` type, the atomic operation is likely to require a lock and have poor performance.

The alignment is only optional when parsing textual IR; for in-memory IR, it is always present. If unspecified, the alignment is assumed to be equal to the size of the `<value>` type. Note that this default alignment assumption is different from the alignment used for the load/store instructions when align isn’t specified.

The pointer passed into cmpxchg must have alignment greater than or equal to the size in memory of the operand.

<a id="id227"></a>

##### Semantics:

The contents of memory at the location specified by the ‘`<pointer>`’ operand is read and compared to ‘`<cmp>`’; if the values are equal, ‘`<new>`’ is written to the location. The original value at the location is returned, together with a flag indicating success (true) or failure (false).

If the cmpxchg operation is marked as `weak` then a spurious failure is permitted: the operation may not write `<new>` even if the comparison matched.

If the cmpxchg operation is strong (the default), the i1 value is 1 if and only if the value loaded equals `cmp`.

A successful `cmpxchg` is a read-modify-write instruction for the purpose of identifying release sequences. A failed `cmpxchg` is equivalent to an atomic load with an ordering parameter determined the second ordering parameter.

<a id="id228"></a>

##### Example:

    entry:
      %orig = load atomic i32, ptr %ptr unordered, align 4                      ; yields i32
      br label %loop

    loop:
      %cmp = phi i32 [ %orig, %entry ], [%value_loaded, %loop]
      %squared = mul i32 %cmp, %cmp
      %val_success = cmpxchg ptr %ptr, i32 %cmp, i32 %squared acq_rel monotonic ; yields  { i32, i1 }
      %value_loaded = extractvalue { i32, i1 } %val_success, 0
      %success = extractvalue { i32, i1 } %val_success, 1
      br i1 %success, label %done, label %loop

    done:
      ...

<a id="atomicrmw-instruction"></a>

<a id="i-atomicrmw"></a>

#### ‘`atomicrmw`’ Instruction

<a id="id229"></a>

##### Syntax:

    atomicrmw [volatile] [elementwise] <operation> ptr <pointer>, <ty> <value> [syncscope("<target-scope>")] <ordering>[, align <alignment>]  ; yields ty

<a id="id230"></a>

##### Overview:

The ‘`atomicrmw`’ instruction is used to atomically modify memory.

<a id="id231"></a>

##### Arguments:

There are three arguments to the ‘`atomicrmw`’ instruction: an operation to apply, an address whose value to modify, an argument to the operation. The operation must be one of the following keywords:

- xchg

- add

- sub

- and

- nand

- or

- xor

- max

- min

- umax

- umin

- fadd

- fsub

- fmax

- fmin

- fmaximum

- fminimum

- fmaximumnum

- fminimumnum

- uinc_wrap

- udec_wrap

- usub_cond

- usub_sat

For all of these operations, the type of `<value>` must be a type whose bit width is a power of two greater than or equal to eight. For add/sub/and/nand/or/xor/max/min/umax/umin/uinc_wrap/udec_wrap/usub_cond/usub_sat, this must be an integer type or a fixed vector of integer type. For fadd/fsub/fmax/fmin/fmaximum/fminimum/fmaximumnum/fminimumnum, this must be a floating-point or fixed vector of floating-point type. For xchg, this must be an integer type, floating-point type, or pointer type, or, if the `elementwise` modifier is present, a fixed vector of integer type, floating-point type, or pointer type. The type of the `<pointer>` operand must be a pointer to the type of `<value>`. If the `atomicrmw` is marked as `volatile`, then the optimizer is not allowed to modify the number or order of execution of this `atomicrmw` with other [volatile operations](high-level-structure.md#volatile).

Note: if the alignment is not greater or equal to the size of the `<value>` type, the atomic operation is likely to require a lock and have poor performance.

The alignment is only optional when parsing textual IR; for in-memory IR, it is always present. If unspecified, the alignment is assumed to be equal to the size of the `<value>` type. Note that this default alignment assumption is different from the alignment used for the load/store instructions when align isn’t specified.

An `atomicrmw` instruction can also take an optional “[syncscope](#syncscope)” argument.

If `atomicrmw` is marked `elementwise`, the instruction has [elementwise atomic semantics](high-level-structure.md#elementwise-atomics).

<a id="id232"></a>

##### Semantics:

The contents of memory at the location specified by the ‘`<pointer>`’ operand are atomically read, modified, and written back. The original value at the location is returned. The modification is specified by the operation argument:

- xchg: `*ptr = val`

- add: `*ptr = *ptr + val`

- sub: `*ptr = *ptr - val`

- and: `*ptr = *ptr & val`

- nand: `*ptr = ~(*ptr & val)`

- or: `*ptr = *ptr | val`

- xor: `*ptr = *ptr ^ val`

- max: `*ptr = *ptr > val ? *ptr : val` (using a signed comparison)

- min: `*ptr = *ptr < val ? *ptr : val` (using a signed comparison)

- umax: `*ptr = *ptr > val ? *ptr : val` (using an unsigned comparison)

- umin: `*ptr = *ptr < val ? *ptr : val` (using an unsigned comparison)

- fadd: `*ptr = *ptr + val` (using floating point arithmetic)

- fsub: `*ptr = *ptr - val` (using floating point arithmetic)

- fmax: `*ptr = maxnum(*ptr, val)` (match the `llvm.maxnum.*` intrinsic)

- fmin: `*ptr = minnum(*ptr, val)` (match the `llvm.minnum.*` intrinsic)

- fmaximum: `*ptr = maximum(*ptr, val)` (match the `llvm.maximum.*` intrinsic)

- fminimum: `*ptr = minimum(*ptr, val)` (match the `llvm.minimum.*` intrinsic)

- fmaximumnum: `*ptr = maximumnum(*ptr, val)` (match the `llvm.maximumnum.*` intrinsic)

- fminimumnum: `*ptr = minimumnum(*ptr, val)` (match the `llvm.minimumnum.*` intrinsic)

- uinc_wrap: `*ptr = (*ptr u>= val) ? 0 : (*ptr + 1)` (increment value with wraparound to zero when incremented above input value)

- udec_wrap: `*ptr = ((*ptr == 0) || (*ptr u> val)) ? val : (*ptr - 1)` (decrement with wraparound to input value when decremented below zero).

- usub_cond: `*ptr = (*ptr u>= val) ? *ptr - val : *ptr` (subtract only if no unsigned overflow).

- usub_sat: `*ptr = (*ptr u>= val) ? *ptr - val : 0` (subtract with unsigned clamping to zero).

<a id="id233"></a>

##### Example:

    %old = atomicrmw add ptr %ptr, i32 1 acquire                        ; yields i32

<a id="getelementptr-instruction"></a>

<a id="i-getelementptr"></a>

#### ‘`getelementptr`’ Instruction

<a id="id234"></a>

##### Syntax:

    <result> = getelementptr <ty>, ptr <ptrval>{, <ty> <idx>}*
    <result> = getelementptr inbounds <ty>, ptr <ptrval>{, <ty> <idx>}*
    <result> = getelementptr nusw <ty>, ptr <ptrval>{, <ty> <idx>}*
    <result> = getelementptr nuw <ty>, ptr <ptrval>{, <ty> <idx>}*
    <result> = getelementptr inrange(S,E) <ty>, ptr <ptrval>{, <ty> <idx>}*
    <result> = getelementptr <ty>, <N x ptr> <ptrval>, <vector index type> <idx>

<a id="id235"></a>

##### Overview:

The ‘`getelementptr`’ instruction is used to get the address of a subelement of an [aggregate](type-system.md#t-aggregate) data structure. It performs address calculation only and does not access memory. The instruction can also be used to calculate a vector of such addresses.

<a id="id236"></a>

##### Arguments:

The first argument is always a type used as the basis for the calculations. The second argument is always a pointer or a vector of pointers, and is the base address to start from. The remaining arguments are indices that indicate which of the elements of the aggregate object are indexed. The interpretation of each index is dependent on the type being indexed into. The first index always indexes the pointer value given as the second argument, the second index indexes a value of the type pointed to (not necessarily the value directly pointed to, since the first index can be non-zero), etc. The first type indexed into must be a pointer value, subsequent types can be arrays, vectors, and structs. Note that subsequent types being indexed into can never be pointers, since that would require loading the pointer before continuing calculation.

The type of each index argument depends on the type it is indexing into. When indexing into a (optionally packed) structure, only `i32` integer **constants** are allowed (when using a vector of indices they must all be the **same** `i32` integer constant). When indexing into an array, pointer or vector, integers of any width are allowed, and they are not required to be constant. These integers are treated as signed values where relevant.

For example, let’s consider a C code fragment and how it gets compiled to LLVM:

    struct RT {
      char A;
      int B[10][20];
      char C;
    };
    struct ST {
      int X;
      double Y;
      struct RT Z;
    };

    int *foo(struct ST *s) {
      return &s[1].Z.B[5][13];
    }

The LLVM code generated by Clang is approximately:

    %struct.RT = type { i8, [10 x [20 x i32]], i8 }
    %struct.ST = type { i32, double, %struct.RT }

    define ptr @foo(ptr %s) {
    entry:
      %arrayidx = getelementptr inbounds %struct.ST, ptr %s, i64 1, i32 2, i32 1, i64 5, i64 13
      ret ptr %arrayidx
    }

<a id="id237"></a>

##### Semantics:

In the example above, the first index is indexing into the ‘`%struct.ST*`’ type, which is a pointer, yielding a ‘`%struct.ST`’ = ‘`{ i32, double, %struct.RT }`’ type, a structure. The second index indexes into the third element of the structure, yielding a ‘`%struct.RT`’ = ‘`{ i8 , [10 x [20 x i32]], i8 }`’ type, another structure. The third index indexes into the second element of the structure, yielding a ‘`[10 x [20 x i32]]`’ type, an array. The two dimensions of the array are subscripted into, yielding an ‘`i32`’ type. The ‘`getelementptr`’ instruction returns a pointer to this element.

Note that it is perfectly legal to index partially through a structure, returning a pointer to an inner element. Because of this, the LLVM code for the given testcase is equivalent to:

    define ptr @foo(ptr %s) {
      %t1 = getelementptr %struct.ST, ptr %s, i32 1
      %t2 = getelementptr %struct.ST, ptr %t1, i32 0, i32 2
      %t3 = getelementptr %struct.RT, ptr %t2, i32 0, i32 1
      %t4 = getelementptr [10 x [20 x i32]], ptr %t3, i32 0, i32 5
      %t5 = getelementptr [20 x i32], ptr %t4, i32 0, i32 13
      ret ptr %t5
    }

The indices are first converted to offsets in the pointer’s index type. If the currently indexed type is a struct type, the struct offset corresponding to the index is sign-extended or truncated to the pointer index type. Otherwise, the index itself is sign-extended or truncated, and then multiplied by the type allocation size (that is, the size rounded up to the ABI alignment) of the currently indexed type.

The offsets are then added to the low bits of the base address up to the index type width, with silently-wrapping two’s complement arithmetic. If the pointer size is larger than the index size, this means that the bits outside the index type width will not be affected.

The result value of the `getelementptr` may be outside the object pointed to by the base pointer. The result value may not necessarily be used to access memory though, even if it happens to point into allocated storage. See the [Pointer Aliasing Rules](high-level-structure.md#pointeraliasing) section for more information.

The `getelementptr` instruction may have a number of attributes that impose additional rules. If any of the rules are violated, the result value is a [poison value](constants.md#poisonvalues). In cases where the base is a vector of pointers, the attributes apply to each computation element-wise.

For `nusw` (no unsigned signed wrap):

- If the type of an index is larger than the pointer index type, the truncation to the pointer index type preserves the signed value (`trunc nsw`).

- The multiplication of an index by the type size does not wrap the pointer index type in a signed sense (`mul nsw`).

- The successive addition of each offset (without adding the base address) does not wrap the pointer index type in a signed sense (`add nsw`).

- The successive addition of the current address, truncated to the pointer index type and interpreted as an unsigned number, and each offset, interpreted as a signed number, does not wrap the pointer index type.

For `nuw` (no unsigned wrap):

- If the type of an index is larger than the pointer index type, the truncation to the pointer index type preserves the unsigned value (`trunc nuw`).

- The multiplication of an index by the type size does not wrap the pointer index type in an unsigned sense (`mul nuw`).

- The successive addition of each offset (without adding the base address) does not wrap the pointer index type in an unsigned sense (`add nuw`).

- The successive addition of the current address, truncated to the pointer index type and interpreted as an unsigned number, and each offset, also interpreted as an unsigned number, does not wrap the pointer index type (`add nuw`).

For `inbounds` all rules of the `nusw` attribute apply. Additionally, if the `getelementptr` has any non-zero indices, the following rules apply:

- The base pointer has an *in bounds* address of the [allocated object](high-level-structure.md#allocatedobjects) that it is [based](high-level-structure.md#pointeraliasing) on. This means that it points into that allocated object, or to its end. Note that the object does not have to be live anymore; being in-bounds of a deallocated object is sufficient. If the allocated object can grow, then the relevant size for being *in bounds* is the maximal size the object could have while satisfying the allocated object rules, not its current size.

- During the successive addition of offsets to the address, the resulting pointer must remain *in bounds* of the allocated object at each step.

Note that `getelementptr` with all-zero indices is always considered to be `inbounds`, even if the base pointer does not point to an allocated object. As a corollary, the only pointer in bounds of the null pointer in the default address space is the null pointer itself.

If `inbounds` is present on a `getelementptr` instruction, the `nusw` attribute will be automatically set as well. For this reason, the `nusw` will also not be printed in textual IR if `inbounds` is already present.

If the `inrange(Start, End)` attribute is present, loading from or storing to any pointer derived from the `getelementptr` has undefined behavior if the load or store would access memory outside the half-open range `[Start, End)` from the `getelementptr` expression result. The result of a pointer comparison or `ptrtoint` (including `ptrtoint`-like operations involving memory) involving a pointer derived from a `getelementptr` with the `inrange` keyword is undefined, with the exception of comparisons in the case where both operands are in the closed range `[Start, End]`. Note that the `inrange` keyword is currently only allowed in constant `getelementptr` expressions.

The getelementptr instruction is often confusing. For some more insight into how it works, see [the getelementptr FAQ](GetElementPtr.html).

<a id="id238"></a>

##### Example:

    %aptr = getelementptr {i32, [12 x i8]}, ptr %saptr, i64 0, i32 1
    %vptr = getelementptr {i32, <2 x i8>}, ptr %svptr, i64 0, i32 1, i32 1
    %eptr = getelementptr [12 x i8], ptr %aptr, i64 0, i32 1
    %iptr = getelementptr [10 x i32], ptr @arr, i16 0, i16 0

<a id="vector-of-pointers"></a>

##### Vector of pointers:

The `getelementptr` returns a vector of pointers, instead of a single address, when one or more of its arguments is a vector. In such cases, all vector arguments should have the same number of elements, and every scalar argument will be effectively broadcast into a vector during address calculation.

    ; All arguments are vectors:
    ;   A[i] = ptrs[i] + offsets[i]*sizeof(i8)
    %A = getelementptr i8, <4 x i8*> %ptrs, <4 x i64> %offsets

    ; Add the same scalar offset to each pointer of a vector:
    ;   A[i] = ptrs[i] + offset*sizeof(i8)
    %A = getelementptr i8, <4 x ptr> %ptrs, i64 %offset

    ; Add distinct offsets to the same pointer:
    ;   A[i] = ptr + offsets[i]*sizeof(i8)
    %A = getelementptr i8, ptr %ptr, <4 x i64> %offsets

    ; In all cases described above the type of the result is <4 x ptr>

The two following instructions are equivalent:

    getelementptr  %struct.ST, <4 x ptr> %s, <4 x i64> %ind1,
      <4 x i32> <i32 2, i32 2, i32 2, i32 2>,
      <4 x i32> <i32 1, i32 1, i32 1, i32 1>,
      <4 x i32> %ind4,
      <4 x i64> <i64 13, i64 13, i64 13, i64 13>

    getelementptr  %struct.ST, <4 x ptr> %s, <4 x i64> %ind1,
      i32 2, i32 1, <4 x i32> %ind4, i64 13

Let’s look at the C code, where the vector version of `getelementptr` makes sense:

    // Let's assume that we vectorize the following loop:
    double *A, *B; int *C;
    for (int i = 0; i < size; ++i) {
      A[i] = B[C[i]];
    }

    ; get pointers for 8 elements from array B
    %ptrs = getelementptr double, ptr %B, <8 x i32> %C
    ; load 8 elements from array B into A
    %A = call <8 x double> @llvm.masked.gather.v8f64.v8p0f64(
         <8 x ptr> align 8 %ptrs, <8 x i1> %mask, <8 x double> %passthru)
