[Wiki](../index.md) › [LLVM LangRef](index.md)

# Intrinsics: overview, varargs, GC, code generator

LLVM 23.1.0 Language Reference, part of the [index](index.md). Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html>. License: Apache-2.0 with LLVM exception.

<a id="intrinsic-functions"></a>

<a id="intrinsics"></a>

## Intrinsic Functions

LLVM supports the notion of an “intrinsic function”. These functions have well known names and semantics and are required to follow certain restrictions. Overall, these intrinsics represent an extension mechanism for the LLVM language that does not require changing all of the transformations in LLVM when adding to the language (or the bitcode reader/writer, the parser, etc…).

Intrinsic function names must all start with an “`llvm.`” prefix. This prefix is reserved in LLVM for intrinsic names; thus, function names may not begin with this prefix. Intrinsic functions must always be external functions: you cannot define the body of intrinsic functions. Intrinsic functions may only be used in call or invoke instructions: it is illegal to take the address of an intrinsic function. Additionally, because intrinsic functions are part of the LLVM language, it is required if any are added that they be documented here.

Some intrinsic functions can be overloaded, i.e., the intrinsic represents a family of functions that perform the same operation but on different data types. Because LLVM can represent over 8 million different integer types, overloading is used commonly to allow an intrinsic function to operate on any integer type. One or more of the argument types or the result type can be overloaded to accept any integer type. Argument types may also be defined as exactly matching a previous argument’s type or the result type. This allows an intrinsic function which accepts multiple arguments, but needs all of them to be of the same type, to only be overloaded with respect to a single argument or the result.

Overloaded intrinsics will have the names of its overloaded argument types encoded into its function name, each preceded by a period. Only those types which are overloaded result in a name suffix. Arguments whose type is matched against another type do not. For example, the `llvm.ctpop` function can take an integer of any width and returns an integer of exactly the same integer width. This leads to a family of functions such as `i8 @llvm.ctpop.i8(i8 %val)` and `i29 @llvm.ctpop.i29(i29 %val)`. Only one type, the return type, is overloaded, and only one type suffix is required. Because the argument’s type is matched against the return type, it does not require its own name suffix.

[Unnamed types](type-system.md#t-opaque) are encoded as `s_s`. Overloaded intrinsics that depend on an unnamed type in one of its overloaded argument types get an additional `.<number>` suffix. This allows differentiating intrinsics with different unnamed types as arguments. (For example: `llvm.ssa.copy.p0s_s.2(%42*)`) The number is tracked in the LLVM module and it ensures unique names in the module. While linking together two modules, it is still possible to get a name clash. In that case one of the names will be changed by getting a new number.

For target developers who are defining intrinsics for back-end code generation, any intrinsic overloads based solely the distinction between integer or floating point types should not be relied upon for correct code generation. In such cases, the recommended approach for target maintainers when defining intrinsics is to create separate integer and FP intrinsics rather than rely on overloading. For example, if different codegen is required for `llvm.target.foo(<4 x i32>)` and `llvm.target.foo(<4 x float>)` then these should be split into different intrinsics.

To learn how to add an intrinsic function, please see the [Extending LLVM Guide](ExtendingLLVM.html).

<a id="variable-argument-handling-intrinsics"></a>

<a id="int-varargs"></a>

### Variable Argument Handling Intrinsics

Variable argument support is defined in LLVM with the [va_arg](instructions-other.md#i-va-arg) instruction and these three intrinsic functions. These functions are related to the similarly named macros defined in the `<stdarg.h>` header file.

All of these functions take as arguments pointers to a target-specific value type “`va_list`”. The LLVM assembly language reference manual does not define what this type is, so all transformations should be prepared to handle these functions regardless of the type used. The intrinsics are overloaded, and can be used for pointers to different address spaces.

The underlying argument list is destroyed when a function returns, so a `va_list` must not outlive the function that created it.

This example shows how the [va_arg](instructions-other.md#i-va-arg) instruction and the variable argument handling intrinsic functions are used.

    ; This struct is different for every platform. For most platforms,
    ; it is merely a ptr.
    %struct.va_list = type { ptr }

    ; For Unix x86_64 platforms, va_list is the following struct:
    ; %struct.va_list = type { i32, i32, ptr, ptr }

    define i32 @test(i32 %X, ...) {
      ; Initialize variable argument processing
      %ap = alloca %struct.va_list
      call void @llvm.va_start.p0(ptr %ap)

      ; Read a single integer argument
      %tmp = va_arg ptr %ap, i32

      ; Demonstrate usage of llvm.va_copy and llvm.va_end
      %aq = alloca ptr
      call void @llvm.va_copy.p0(ptr %aq, ptr %ap)
      call void @llvm.va_end.p0(ptr %aq)

      ; Stop processing of arguments.
      call void @llvm.va_end.p0(ptr %ap)
      ret i32 %tmp
    }

    declare void @llvm.va_start.p0(ptr)
    declare void @llvm.va_copy.p0(ptr, ptr)
    declare void @llvm.va_end.p0(ptr)

<a id="llvm-va-start-intrinsic"></a>

<a id="int-va-start"></a>

#### ‘`llvm.va_start`’ Intrinsic

<a id="id359"></a>

##### Syntax:

    declare void @llvm.va_start.p0(ptr <arglist>)
    declare void @llvm.va_start.p5(ptr addrspace(5) <arglist>)

<a id="id360"></a>

##### Overview:

The ‘`llvm.va_start`’ intrinsic initializes `<arglist>` for subsequent use by `va_arg`.

<a id="id361"></a>

##### Arguments:

The argument is a pointer to a `va_list` element to initialize.

<a id="id362"></a>

##### Semantics:

The ‘`llvm.va_start`’ intrinsic works just like the `va_start` macro available in C. In a target-dependent way, it initializes the `va_list` element to which the argument points, so that the next call to `va_arg` will produce the first variable argument passed to the function. Unlike the C `va_start` macro, this intrinsic does not need to know the last argument of the function as the compiler can figure that out.

<a id="llvm-va-end-intrinsic"></a>

#### ‘`llvm.va_end`’ Intrinsic

<a id="id363"></a>

##### Syntax:

    declare void @llvm.va_end.p0(ptr <arglist>)
    declare void @llvm.va_end.p5(ptr addrspace(5) <arglist>)

<a id="id364"></a>

##### Overview:

The ‘`llvm.va_end`’ intrinsic destroys `<arglist>`, which has been initialized previously with `llvm.va_start` or `llvm.va_copy`.

<a id="id365"></a>

##### Arguments:

The argument is a pointer to a `va_list` to destroy.

<a id="id366"></a>

##### Semantics:

The ‘`llvm.va_end`’ intrinsic works just like the `va_end` macro available in C. In a target-dependent way, it destroys the `va_list` element to which the argument points. Calls to [llvm.va_start](#int-va-start) and [llvm.va_copy](#int-va-copy) must be matched exactly with calls to `llvm.va_end`.

When used, calls to `llvm.va_end` must be matched exactly with calls to [llvm.va_start](#int-va-start) and [llvm.va_copy](#int-va-copy).

<a id="llvm-va-copy-intrinsic"></a>

<a id="int-va-copy"></a>

#### ‘`llvm.va_copy`’ Intrinsic

<a id="id367"></a>

##### Syntax:

    declare void @llvm.va_copy.p0(ptr <destarglist>, ptr <srcarglist>)
    declare void @llvm.va_copy.p5(ptr addrspace(5) <destarglist>, ptr addrspace(5) <srcarglist>)

<a id="id368"></a>

##### Overview:

The ‘`llvm.va_copy`’ intrinsic copies the current argument position from the source argument list to the destination argument list.

<a id="id369"></a>

##### Arguments:

The first argument is a pointer to a `va_list` element to initialize. The second argument is a pointer to a `va_list` element to copy from. The address spaces of the two arguments must match.

<a id="id370"></a>

##### Semantics:

The ‘`llvm.va_copy`’ intrinsic works just like the `va_copy` macro available in C. In a target-dependent way, it copies the source `va_list` element into the destination `va_list` element. This intrinsic is necessary because the `llvm.va_start` intrinsic may be arbitrarily complex and require, for example, memory allocation.

On targets where `llvm.va_copy` is equivalent to `memcpy`, `memcpy` can be used instead to duplicate a `va_list`. `llvm.va_copy` is equivalent to `memcpy` on all currently supported targets.

<a id="accurate-garbage-collection-intrinsics"></a>

### Accurate Garbage Collection Intrinsics

LLVM’s support for [Accurate Garbage Collection](GarbageCollection.html) (GC) requires the frontend to generate code containing appropriate intrinsic calls and select an appropriate GC strategy which knows how to lower these intrinsics in a manner which is appropriate for the target collector.

These intrinsics allow identification of [GC roots on the stack](#int-gcroot), as well as garbage collector implementations that require [read](#int-gcread) and [write](#int-gcwrite) barriers. Frontends for type-safe garbage collected languages should generate these intrinsics to make use of the LLVM garbage collectors. For more details, see [Garbage Collection with LLVM](GarbageCollection.html).

LLVM provides an second experimental set of intrinsics for describing garbage collection safepoints in compiled code. These intrinsics are an alternative to the `llvm.gcroot` intrinsics, but are compatible with the ones for [read](#int-gcread) and [write](#int-gcwrite) barriers. The differences in approach are covered in the [Garbage Collection with LLVM](GarbageCollection.html) documentation. The intrinsics themselves are described in [Garbage Collection Safepoints in LLVM](Statepoints.html).

<a id="llvm-gcroot-intrinsic"></a>

<a id="int-gcroot"></a>

#### ‘`llvm.gcroot`’ Intrinsic

<a id="id371"></a>

##### Syntax:

    declare void @llvm.gcroot(ptr %ptrloc, ptr %metadata)

<a id="id372"></a>

##### Overview:

The ‘`llvm.gcroot`’ intrinsic declares the existence of a GC root to the code generator, and allows some metadata to be associated with it.

<a id="id373"></a>

##### Arguments:

The first argument specifies the address of a stack object that contains the root pointer. The second pointer (which must be either a constant or a global value address) contains the meta-data to be associated with the root.

<a id="id374"></a>

##### Semantics:

At runtime, a call to this intrinsic stores a null pointer into the “ptrloc” location. At compile-time, the code generator generates information to allow the runtime to find the pointer at GC safe points. The ‘`llvm.gcroot`’ intrinsic may only be used in a function which [specifies a GC algorithm](high-level-structure.md#gc).

<a id="llvm-gcread-intrinsic"></a>

<a id="int-gcread"></a>

#### ‘`llvm.gcread`’ Intrinsic

<a id="id375"></a>

##### Syntax:

    declare ptr @llvm.gcread(ptr %ObjPtr, ptr %Ptr)

<a id="id376"></a>

##### Overview:

The ‘`llvm.gcread`’ intrinsic identifies reads of references from heap locations, allowing garbage collector implementations that require read barriers.

<a id="id377"></a>

##### Arguments:

The second argument is the address to read from, which should be an address allocated from the garbage collector. The first object is a pointer to the start of the referenced object, if needed by the language runtime (otherwise null).

<a id="id378"></a>

##### Semantics:

The ‘`llvm.gcread`’ intrinsic has the same semantics as a load instruction, but may be replaced with substantially more complex code by the garbage collector runtime, as needed. The ‘`llvm.gcread`’ intrinsic may only be used in a function which [specifies a GC algorithm](high-level-structure.md#gc).

<a id="llvm-gcwrite-intrinsic"></a>

<a id="int-gcwrite"></a>

#### ‘`llvm.gcwrite`’ Intrinsic

<a id="id379"></a>

##### Syntax:

    declare void @llvm.gcwrite(ptr %P1, ptr %Obj, ptr %P2)

<a id="id380"></a>

##### Overview:

The ‘`llvm.gcwrite`’ intrinsic identifies writes of references to heap locations, allowing garbage collector implementations that require write barriers (such as generational or reference counting collectors).

<a id="id381"></a>

##### Arguments:

The first argument is the reference to store, the second is the start of the object to store it to, and the third is the address of the field of Obj to store to. If the runtime does not require a pointer to the object, Obj may be null.

<a id="id382"></a>

##### Semantics:

The ‘`llvm.gcwrite`’ intrinsic has the same semantics as a store instruction, but may be replaced with substantially more complex code by the garbage collector runtime, as needed. The ‘`llvm.gcwrite`’ intrinsic may only be used in a function which [specifies a GC algorithm](high-level-structure.md#gc).

<a id="llvm-experimental-gc-statepoint-intrinsic"></a>

<a id="gc-statepoint"></a>

#### ‘`llvm.experimental.gc.statepoint`’ Intrinsic

<a id="id383"></a>

##### Syntax:

    declare token
      @llvm.experimental.gc.statepoint(i64 <id>, i32 <num patch bytes>,
                     ptr elementtype(func_type) <target>,
                     i64 <#call args>, i64 <flags>,
                     ... (call parameters),
                     i64 0, i64 0)

<a id="id384"></a>

##### Overview:

The statepoint intrinsic represents a call which is parse-able by the runtime.

<a id="operands"></a>

##### Operands:

The ‘id’ operand is a constant integer that is reported as the ID field in the generated stackmap. LLVM does not interpret this parameter in any way and its meaning is up to the statepoint user to decide. Note that LLVM is free to duplicate code containing statepoint calls, and this may transform IR that had a unique ‘id’ per lexical call to statepoint to IR that does not.

If ‘num patch bytes’ is non-zero then the call instruction corresponding to the statepoint is not emitted and LLVM emits ‘num patch bytes’ bytes of nops in its place. LLVM will emit code to prepare the function arguments and retrieve the function return value in accordance to the calling convention; the former before the nop sequence and the latter after the nop sequence. It is expected that the user will patch over the ‘num patch bytes’ bytes of nops with a calling sequence specific to their runtime before executing the generated machine code. There are no guarantees with respect to the alignment of the nop sequence. Unlike [Stack maps and patch points in LLVM](StackMaps.html) statepoints do not have a concept of shadow bytes. Note that semantically the statepoint still represents a call or invoke to ‘target’, and the nop sequence after patching is expected to represent an operation equivalent to a call or invoke to ‘target’.

The ‘target’ operand is the function actually being called. The operand must have an [elementtype](high-level-structure.md#attr-elementtype) attribute specifying the function type of the target. The target can be specified as either a symbolic LLVM function, or as an arbitrary Value of pointer type. Note that the function type must match the signature of the callee and the types of the ‘call parameters’ arguments.

The ‘#call args’ operand is the number of arguments to the actual call. It must exactly match the number of arguments passed in the ‘call parameters’ variable-length section.

The ‘flags’ operand is used to specify extra information about the statepoint. This is currently only used to mark certain statepoints as GC transitions. This operand is a 64-bit integer with the following layout, where bit 0 is the least significant bit:

| Bit \# | Usage                                                        |
|--------|--------------------------------------------------------------|
| 0      | Set if the statepoint is a GC transition, cleared otherwise. |
| 1-63   | Reserved for future use; must be cleared.                    |

The ‘call parameters’ arguments are simply the arguments which need to be passed to the call target. They will be lowered according to the specified calling convention and otherwise handled like a normal call instruction. The number of arguments must exactly match what is specified in ‘# call args’. The types must match the signature of ‘target’.

The ‘call parameter’ attributes must be followed by two ‘i64 0’ constants. These were originally the length prefixes for ‘gc transition parameter’ and ‘deopt parameter’ arguments, but the role of these parameter sets have been entirely replaced with the corresponding operand bundles. In a future revision, these now redundant arguments will be removed.

<a id="id385"></a>

##### Semantics:

A statepoint is assumed to read and write all memory. As a result, memory operations can not be reordered past a statepoint. It is illegal to mark a statepoint as being either ‘readonly’ or ‘readnone’.

Note that legal IR can not perform any memory operation on a ‘gc pointer’ argument of the statepoint in a location statically reachable from the statepoint. Instead, the explicitly relocated value (from a `gc.relocate`) must be used.

<a id="llvm-experimental-gc-result-intrinsic"></a>

#### ‘`llvm.experimental.gc.result`’ Intrinsic

<a id="id386"></a>

##### Syntax:

    declare type
      @llvm.experimental.gc.result(token %statepoint_token)

<a id="id387"></a>

##### Overview:

`gc.result` extracts the result of the original call instruction which was replaced by the `gc.statepoint`. The `gc.result` intrinsic is actually a family of three intrinsics due to an implementation limitation. Other than the type of the return value, the semantics are the same.

<a id="id388"></a>

##### Operands:

The first and only argument is the `gc.statepoint` which starts the safepoint sequence of which this `gc.result` is a part. Despite the typing of this as a generic token, *only* the value defined by a `gc.statepoint` is legal here.

<a id="id389"></a>

##### Semantics:

The `gc.result` represents the return value of the call target of the `statepoint`. The type of the `gc.result` must exactly match the type of the target. If the call target returns void, there will be no `gc.result`.

A `gc.result` is modeled as a ‘readnone’ pure function. It has no side effects since it is just a projection of the return value of the previous call represented by the `gc.statepoint`.

<a id="llvm-experimental-gc-relocate-intrinsic"></a>

#### ‘`llvm.experimental.gc.relocate`’ Intrinsic

<a id="id390"></a>

##### Syntax:

    declare <pointer type>
      @llvm.experimental.gc.relocate(token %statepoint_token,
                                     i32 %base_offset,
                                     i32 %pointer_offset)

<a id="id391"></a>

##### Overview:

A `gc.relocate` returns the potentially relocated value of a pointer at the safepoint.

<a id="id392"></a>

##### Operands:

The first argument is the `gc.statepoint` which starts the safepoint sequence of which this `gc.relocation` is a part. Despite the typing of this as a generic token, *only* the value defined by a `gc.statepoint` is legal here.

The second and third arguments are both indices into operands of the corresponding statepoint’s [gc-live](high-level-structure.md#ob-gc-live) operand bundle.

The second argument is an index which specifies the allocation for the pointer being relocated. The associated value must be within the object with which the pointer being relocated is associated. The optimizer is free to change *which* interior derived pointer is reported, provided that it does not replace an actual base pointer with another interior derived pointer. Collectors are allowed to rely on the base pointer operand remaining an actual base pointer if so constructed.

The third argument is an index which specify the (potentially) derived pointer being relocated. It is legal for this index to be the same as the second argument if and only if a base pointer is being relocated.

<a id="id393"></a>

##### Semantics:

The return value of `gc.relocate` is the potentially relocated value of the pointer specified by its arguments. It is unspecified how the value of the returned pointer relates to the argument to the `gc.statepoint` other than that a) it points to the same source language object with the same offset, and b) the ‘based-on’ relationship of the newly relocated pointers is a projection of the unrelocated pointers. In particular, the integer value of the pointer returned is unspecified.

A `gc.relocate` is modeled as a `readnone` pure function. It has no side effects since it is just a way to extract information about work done during the actual call modeled by the `gc.statepoint`.

<a id="llvm-experimental-gc-get-pointer-base-intrinsic"></a>

<a id="gc-get-pointer-base"></a>

#### ‘`llvm.experimental.gc.get.pointer.base`’ Intrinsic

<a id="id394"></a>

##### Syntax:

    declare <pointer type>
      @llvm.experimental.gc.get.pointer.base(
        <pointer type> readnone captures(none) %derived_ptr)
        nounwind willreturn memory(none)

<a id="id395"></a>

##### Overview:

`gc.get.pointer.base` for a derived pointer returns its base pointer.

<a id="id396"></a>

##### Operands:

The only argument is a pointer which is based on some object with an unknown offset from the base of said object.

<a id="id397"></a>

##### Semantics:

This intrinsic is used in the abstract machine model for GC to represent the base pointer for an arbitrary derived pointer.

This intrinsic is inlined by the [RewriteStatepointsForGC](Statepoints.html#rewritestatepointsforgc) pass by replacing all uses of this callsite with the offset of a derived pointer from its base pointer value. The replacement is done as part of the lowering to the explicit statepoint model.

The return pointer type must be the same as the type of the parameter.

<a id="llvm-experimental-gc-get-pointer-offset-intrinsic"></a>

#### ‘`llvm.experimental.gc.get.pointer.offset`’ Intrinsic

<a id="id398"></a>

##### Syntax:

    declare i64
      @llvm.experimental.gc.get.pointer.offset(
        <pointer type> readnone captures(none) %derived_ptr)
        nounwind willreturn memory(none)

<a id="id399"></a>

##### Overview:

`gc.get.pointer.offset` for a derived pointer returns the offset from its base pointer.

<a id="id400"></a>

##### Operands:

The only argument is a pointer which is based on some object with an unknown offset from the base of said object.

<a id="id401"></a>

##### Semantics:

This intrinsic is used in the abstract machine model for GC to represent the offset of an arbitrary derived pointer from its base pointer.

This intrinsic is inlined by the [RewriteStatepointsForGC](Statepoints.html#rewritestatepointsforgc) pass by replacing all uses of this callsite with the offset of a derived pointer from its base pointer value. The replacement is done as part of the lowering to the explicit statepoint model.

Basically this call calculates difference between the derived pointer and its base pointer (see [‘llvm.experimental.gc.get.pointer.base’ Intrinsic](#gc-get-pointer-base)) both ptrtoint casted. But this cast done outside the [RewriteStatepointsForGC](Statepoints.html#rewritestatepointsforgc) pass could result in the pointers lost for further lowering from the abstract model to the explicit physical one.

<a id="code-generator-intrinsics"></a>

### Code Generator Intrinsics

These intrinsics are provided by LLVM to expose special features that may only be implemented with code generator support.

<a id="llvm-returnaddress-intrinsic"></a>

#### ‘`llvm.returnaddress`’ Intrinsic

<a id="id402"></a>

##### Syntax:

    declare ptr @llvm.returnaddress(i32 <level>)

<a id="id403"></a>

##### Overview:

The ‘`llvm.returnaddress`’ intrinsic attempts to compute a target-specific value indicating the return address of the current function or one of its callers.

<a id="id404"></a>

##### Arguments:

The argument to this intrinsic indicates which function to return the address for. Zero indicates the calling function, one indicates its caller, etc. The argument is **required** to be a constant integer value.

<a id="id405"></a>

##### Semantics:

The ‘`llvm.returnaddress`’ intrinsic either returns a pointer indicating the return address of the specified call frame, or zero if it cannot be identified. The value returned by this intrinsic is likely to be incorrect or 0 for arguments other than zero, so it should only be used for debugging purposes.

Note that calling this intrinsic does not prevent function inlining or other aggressive transformations, so the value returned may not be that of the obvious source-language caller.

<a id="llvm-addressofreturnaddress-intrinsic"></a>

#### ‘`llvm.addressofreturnaddress`’ Intrinsic

<a id="id406"></a>

##### Syntax:

    declare ptr @llvm.addressofreturnaddress()

<a id="id407"></a>

##### Overview:

The ‘`llvm.addressofreturnaddress`’ intrinsic returns a target-specific pointer to the place in the stack frame where the return address of the current function is stored.

<a id="id408"></a>

##### Semantics:

Note that calling this intrinsic does not prevent function inlining or other aggressive transformations, so the value returned may not be that of the obvious source-language caller.

This intrinsic is only implemented for x86 and aarch64.

<a id="llvm-sponentry-intrinsic"></a>

#### ‘`llvm.sponentry`’ Intrinsic

<a id="id409"></a>

##### Syntax:

    declare ptr @llvm.sponentry()

<a id="id410"></a>

##### Overview:

The ‘`llvm.sponentry`’ intrinsic returns the stack pointer value at the entry of the current function calling this intrinsic.

<a id="id411"></a>

##### Semantics:

Note this intrinsic is only verified on AArch64 and ARM.

<a id="llvm-stackaddress-intrinsic"></a>

#### ‘`llvm.stackaddress`’ Intrinsic

<a id="id412"></a>

##### Syntax:

    declare ptr @llvm.stackaddress.p0()

<a id="id413"></a>

##### Overview:

The ‘`llvm.stackaddress`’ intrinsic returns the starting address of the stack region that may be used by called functions.

<a id="id414"></a>

##### Semantics:

This intrinsic returns the *logical* value of the stack pointer register, that is, the address separating the stack space of the current function from the stack space that may be modified by called functions. It corresponds to the address returned by ‘`llvm.sponentry`’, offset by the size of the current function’s stack frame.

On certain targets (e.g. x86), the logical and actual (or physical) values of the stack pointer register are the same. However, on other architectures (e.g. SPARCv9), the logical value of the stack pointer register may differ from the physical value. ‘`llvm.stackaddress`’ handles this discrepancy and returns the correct boundary address.

<a id="llvm-frameaddress-intrinsic"></a>

#### ‘`llvm.frameaddress`’ Intrinsic

<a id="id415"></a>

##### Syntax:

    declare ptr @llvm.frameaddress(i32 <level>)

<a id="id416"></a>

##### Overview:

The ‘`llvm.frameaddress`’ intrinsic attempts to return the target-specific frame pointer value for the specified stack frame.

<a id="id417"></a>

##### Arguments:

The argument to this intrinsic indicates which function to return the frame pointer for. Zero indicates the calling function, one indicates its caller, etc. The argument is **required** to be a constant integer value.

<a id="id418"></a>

##### Semantics:

The ‘`llvm.frameaddress`’ intrinsic either returns a pointer indicating the frame address of the specified call frame, or zero if it cannot be identified. The value returned by this intrinsic is likely to be incorrect or 0 for arguments other than zero, so it should only be used for debugging purposes.

Note that calling this intrinsic does not prevent function inlining or other aggressive transformations, so the value returned may not be that of the obvious source-language caller.

<a id="llvm-swift-async-context-addr-intrinsic"></a>

#### ‘`llvm.swift.async.context.addr`’ Intrinsic

<a id="id419"></a>

##### Syntax:

    declare ptr @llvm.swift.async.context.addr()

<a id="id420"></a>

##### Overview:

The ‘`llvm.swift.async.context.addr`’ intrinsic returns a pointer to the part of the extended frame record containing the asynchronous context of a Swift execution.

<a id="id421"></a>

##### Semantics:

If the caller has a `swiftasync` parameter, that argument will initially be stored at the returned address. If not, it will be initialized to null.

<a id="llvm-localescape-and-llvm-localrecover-intrinsics"></a>

#### ‘`llvm.localescape`’ and ‘`llvm.localrecover`’ Intrinsics

<a id="id422"></a>

##### Syntax:

    declare void @llvm.localescape(...)
    declare ptr @llvm.localrecover(ptr %func, ptr %fp, i32 %idx)

<a id="id423"></a>

##### Overview:

The ‘`llvm.localescape`’ intrinsic escapes offsets of a collection of static allocas, and the ‘`llvm.localrecover`’ intrinsic applies those offsets to a live frame pointer to recover the address of the allocation. The offset is computed during frame layout of the caller of `llvm.localescape`.

<a id="id424"></a>

##### Arguments:

All arguments to ‘`llvm.localescape`’ must be pointers to static allocas or casts of static allocas. Each function can only call ‘`llvm.localescape`’ once, and it can only do so from the entry block.

The `func` argument to ‘`llvm.localrecover`’ must be a constant bitcasted pointer to a function defined in the current module. The code generator cannot determine the frame allocation offset of functions defined in other modules.

The `fp` argument to ‘`llvm.localrecover`’ must be a frame pointer of a call frame that is currently live. The return value of ‘`llvm.localaddress`’ is one way to produce such a value, but various runtimes also expose a suitable pointer in platform-specific ways.

The `idx` argument to ‘`llvm.localrecover`’ indicates which alloca passed to ‘`llvm.localescape`’ to recover. It is zero-indexed.

<a id="id425"></a>

##### Semantics:

These intrinsics allow a group of functions to share access to a set of local stack allocations of a one parent function. The parent function may call the ‘`llvm.localescape`’ intrinsic once from the function entry block, and the child functions can use ‘`llvm.localrecover`’ to access the escaped allocas. The ‘`llvm.localescape`’ intrinsic blocks inlining, as inlining changes where the escaped allocas are allocated, which would break attempts to use ‘`llvm.localrecover`’.

<a id="llvm-seh-try-begin-and-llvm-seh-try-end-intrinsics"></a>

#### ‘`llvm.seh.try.begin`’ and ‘`llvm.seh.try.end`’ Intrinsics

<a id="id426"></a>

##### Syntax:

    declare void @llvm.seh.try.begin()
    declare void @llvm.seh.try.end()

<a id="id427"></a>

##### Overview:

The ‘`llvm.seh.try.begin`’ and ‘`llvm.seh.try.end`’ intrinsics mark the boundary of a \_try region for Windows SEH Asynchronous Exception Handling.

<a id="id428"></a>

##### Semantics:

When a C-function is compiled with Windows SEH Asynchronous Exception option, -feh_asynch (aka MSVC -EHa), these two intrinsics are injected to mark \_try boundary and to prevent potential exceptions from being moved across boundary. Any set of operations can then be confined to the region by reading their leaf inputs via volatile loads and writing their root outputs via volatile stores.

<a id="llvm-seh-scope-begin-and-llvm-seh-scope-end-intrinsics"></a>

#### ‘`llvm.seh.scope.begin`’ and ‘`llvm.seh.scope.end`’ Intrinsics

<a id="id429"></a>

##### Syntax:

    declare void @llvm.seh.scope.begin()
    declare void @llvm.seh.scope.end()

<a id="id430"></a>

##### Overview:

The ‘`llvm.seh.scope.begin`’ and ‘`llvm.seh.scope.end`’ intrinsics mark the boundary of a CPP object lifetime for Windows SEH Asynchronous Exception Handling (MSVC option -EHa).

<a id="id431"></a>

##### Semantics:

LLVM’s ordinary exception-handling representation associates EH cleanups and handlers only with `invoke`s, which normally correspond only to call sites. To support arbitrary faulting instructions, it must be possible to recover the current EH scope for any instruction. Turning every operation in LLVM that could fault into an `invoke` of a new, potentially-throwing intrinsic would require adding a large number of intrinsics, impede optimization of those operations, and make compilation slower by introducing many extra basic blocks. These intrinsics can be used instead to mark the region protected by a cleanup, such as for a local C++ object with a non-trivial destructor. `llvm.seh.scope.begin` is used to mark the start of the region; it is always called with `invoke`, with the unwind block being the desired unwind destination for any potentially-throwing instructions within the region. `llvm.seh.scope.end` is used to mark when the scope ends and the EH cleanup is no longer required (e.g., because the destructor is being called).

<a id="llvm-read-register-llvm-read-volatile-register-llvm-write-register-and-llvm-write-volatile-register-intrinsics"></a>

<a id="int-write-volatile-register"></a>

<a id="int-write-register"></a>

<a id="int-read-volatile-register"></a>

<a id="int-read-register"></a>

#### ‘`llvm.read_register`’, ‘`llvm.read_volatile_register`’, ‘`llvm.write_register`’, and ‘`llvm.write_volatile_register`’ Intrinsics

<a id="id432"></a>

##### Syntax:

    declare i32 @llvm.read_register.i32(metadata)
    declare i64 @llvm.read_register.i64(metadata)
    declare i32 @llvm.read_volatile_register.i32(metadata)
    declare i64 @llvm.read_volatile_register.i64(metadata)
    declare void @llvm.write_register.i32(metadata, i32 @value)
    declare void @llvm.write_register.i64(metadata, i64 @value)
    declare void @llvm.write_volatile_register.i32(metadata, i32 @value)
    declare void @llvm.write_volatile_register.i64(metadata, i64 @value)
    !0 = !{!"sp\00"}

<a id="id433"></a>

##### Overview:

The ‘`llvm.read_register`’, ‘`llvm.read_volatile_register`’, ‘`llvm.write_register`’, and ‘`llvm.write_volatile_register`’ intrinsics provide access to the named register. The register must be valid on the architecture being compiled to. The type needs to be compatible with the register being accessed.

<a id="id434"></a>

##### Semantics:

The ‘`llvm.read_register`’ and ‘`llvm.read_volatile_register`’ intrinsics return the current value of the register, where possible. The ‘`llvm.write_register`’ and ‘`llvm.write_volatile_register`’ intrinsics set the current value of the register, where possible.

A call to ‘`llvm.read_volatile_register`’ or ‘`llvm.write_volatile_register`’ is assumed to have side-effects and will not be reordered or eliminated by the optimizer.

This is useful to implement named register global variables that need to always be mapped to a specific register, as is common practice on bare-metal programs including OS kernels.

The compiler doesn’t check for register availability or use of the used register in surrounding code, including inline assembly. Because of that, allocatable registers are not supported by ‘`llvm.read_register`’, ‘`llvm.read_volatile_register`’, or ‘`llvm.write_register`’.

‘`llvm.write_volatile_register`’ supports allocatable registers. Writing to an allocatable register means the value is copied into that physical register at the point of the call; the register may subsequently be reused by the register allocator for other purposes. The backend emits a `FAKE_USE` of the physical register after the write to prevent the store from being dead-eliminated before register allocation.

Warning: Register support is target-specific. The IR-level verifier does not validate register names; an unsupported name results in a fatal error during code generation. Supported registers vary by target and can be found in each target’s `getRegisterByName` implementation. ‘`llvm.write_volatile_register`’ support for allocatable registers is currently only implemented on AArch64.

<a id="llvm-stacksave-intrinsic"></a>

<a id="int-stacksave"></a>

#### ‘`llvm.stacksave`’ Intrinsic

<a id="id435"></a>

##### Syntax:

    declare ptr @llvm.stacksave.p0()
    declare ptr addrspace(5) @llvm.stacksave.p5()

<a id="id436"></a>

##### Overview:

The ‘`llvm.stacksave`’ intrinsic is used to remember the current state of the function stack, for use with [llvm.stackrestore](#int-stackrestore). This is useful for implementing language features like scoped automatic variable sized arrays in C99.

<a id="id437"></a>

##### Semantics:

This intrinsic returns an opaque pointer value that can be passed to [llvm.stackrestore](#int-stackrestore). When an `llvm.stackrestore` intrinsic is executed with a value saved from `llvm.stacksave`, it effectively restores the state of the stack to the state it was in when the `llvm.stacksave` intrinsic executed. In practice, this pops any [alloca](instructions-memory.md#i-alloca) blocks from the stack that were allocated after the `llvm.stacksave` was executed. The address space should typically be the [alloca address space](high-level-structure.md#alloca-addrspace).

<a id="llvm-stackrestore-intrinsic"></a>

<a id="int-stackrestore"></a>

#### ‘`llvm.stackrestore`’ Intrinsic

<a id="id438"></a>

##### Syntax:

    declare void @llvm.stackrestore.p0(ptr %ptr)
    declare void @llvm.stackrestore.p5(ptr addrspace(5) %ptr)

<a id="id439"></a>

##### Overview:

The ‘`llvm.stackrestore`’ intrinsic is used to restore the state of the function stack to the state it was in when the corresponding [llvm.stacksave](#int-stacksave) intrinsic executed. This is useful for implementing language features like scoped automatic variable sized arrays in C99. The address space should typically be the [alloca address space](high-level-structure.md#alloca-addrspace).

<a id="id440"></a>

##### Semantics:

See the description for [llvm.stacksave](#int-stacksave).

<a id="llvm-structured-gep-intrinsic"></a>

<a id="i-structured-gep"></a>

#### ‘`llvm.structured.gep`’ Intrinsic

<a id="id441"></a>

##### Syntax:

    declare <ret_type>
    @llvm.structured.gep(ptr elementtype(<basetype>) <source>
                         {, [i32/i64] <index> }*)

<a id="id442"></a>

##### Overview:

The ‘`llvm.structured.gep`’ intrinsic (structured **G**et**E**lement**P**tr) computes a new pointer address resulting from a logical indexing into the `<source>` pointer. The returned address depends on the indices and may depend on the layout of `<basetype>` at runtime.

<a id="id443"></a>

##### Arguments:

`ptr elementtype(<basetype>) <source>`: A pointer to the memory location used as base for the address computation.

The `source` argument must be annotated with an [elementtype](high-level-structure.md#attr-elementtype) attribute at the call-site. This attribute specifies the type of the element pointed to by the pointer source. This type will be used along with the provided indices and source operand to compute a new pointer representing the result of a logical indexing into the basetype pointed by source.

The `basetype` is only associated with `<source>` for this particular call. A frontend could possibly emit multiple structured GEP with the same source pointer but a different `basetype`.

`[i32/i64] index, ...`: Indices used to traverse into the `basetype` and compute a pointer to the target element. Indices can be 32-bit or 64-bit unsigned integers. Indices being handled one by one, both sizes can be mixed in the same instruction. The precision used to compute the resulting pointer is target-dependent. When used to index into a struct, only integer constants are allowed.

<a id="id444"></a>

##### Semantics:

The `llvm.structured.gep` performs a logical traversal of the type `basetype` using the list of provided indices, computing the pointer addressing the targeted element/field assuming `source` points to a physically laid out `basetype`. The physical layout of the source depends on the target and does not necessarily match the one described by the datalayout.

The first index determines which element/field of `basetype` is selected, computes the pointer to access this element/field assuming `source` points to the start of `basetype`. This pointer becomes the new `source`, the current type the new `basetype`, and the next indices is consumed until a scalar type is reached or all indices are consumed.

All indices must be consumed, and it is illegal to index into a scalar type. Meaning the maximum number of indices depends on the depth of the basetype.

Because this instruction performs a logical addressing, all indices are assumed to be inbounds. This means it is not possible to access the next element in the logical layout by overflowing:

- If the indexed type is a struct with N fields, the index must be an immediate/constant value in the range `[0; N[`.

- If indexing into an array or vector, the index can be a variable, but is assumed to be inbounds with regards to the current basetype logical layout.

- If the traversed type is an array or vector of N elements with `N > 0`, the index is assumed to belong to `[0; N[`.

- If the traversed type is an array of size `0`, the array size is assumed to be known at runtime, and the instruction assumes the index is always inbounds.

In all cases **except** when the accessed type is a 0-sized array, indexing out of bounds yields `poison`. When the index value is unknown, optimizations can use the type bounds to determine the range of values the index can have. If the source pointer is poison, the instruction returns poison. The resulting pointer belongs to the same address space as `source`. This instruction does not dereference the pointer.

<a id="id445"></a>

##### Example:

**Simple case: logical access of a struct field**

    struct A { int a, int b, int c, int d };
    int val = my_struct->b;

Could be translated to:

    %A = type { i32, i32, i32, i32 }
    %src = call ptr @llvm.structured.gep(ptr elementtype(%A) %my_struct, i32 1)
    %val = load i32, ptr %src

**A more complex case**

This instruction can also be used on the same pointer with different basetypes, as long as codegen knows how those are physically laid out. Let’s consider the following code:

    struct S {
        uint a;
        uint b;
        uint c;
        uint d;
    }

    int val = my_struct->b;

In this example, the frontend doesn’t know the exact physical layout, but knows those logical layouts are lowered to the same physical layout:

- `{ i32, i32, i32, i32 }`

- `[ i32 x 4 ]`

This means it is valid to lower the following code to either:

    %S = type { i32, i32, i32, i32 }
    %src = call ptr @llvm.structured.gep(ptr elementtype(%S) %my_struct, i32 1)
    load i32, ptr %src

Or:

    %src = call ptr @llvm.structured.gep(ptr elementtype([ 4 x i32 ]) %my_struct, i32 1)
    load i32, ptr %src

This is, however, dependent on context that codegen has an insight on. The fact that `[ i32 x 4 ]` and `%S` are equivalent depends on the target.

<a id="llvm-structured-alloca-intrinsic"></a>

<a id="i-structured-alloca"></a>

#### ‘`llvm.structured.alloca`’ Intrinsic

<a id="id446"></a>

##### Syntax:

    declare elementtype(<allocated_type>) ptr
    @llvm.structured.alloca()

<a id="id447"></a>

##### Overview:

The ‘`llvm.structured.alloca`’ intrinsic allocates uninitialized memory on the stack for a logical type, such as an aggregate, an array, or a scalar.

Unlike the standard [alloca](instructions-memory.md#i-alloca) instruction, the physical memory layout of a `llvm.structured.alloca` is completely opaque to the IR. Exact padding, size, alignment and subtype offsets is target-dependent and may differ from the standard `DataLayout`.

<a id="id448"></a>

##### Arguments:

The intrinsic must be annotated with an [elementtype](high-level-structure.md#attr-elementtype) attribute at the call-site on the return value. This attribute specifies the type of the allocated element.

<a id="id449"></a>

##### Semantics:

The `llvm.structured.alloca` intrinsic allocates uninitialized memory for a logical type. Loading from uninitialized memory produces an undefined value. This intrinsic does not guarantee that the allocated memory will store a value of the given type, only that it allocates enough space for it on the destination target. While the type’s size and layout are constant (independent of location), the exact padding and offsets between subtypes are opaque to the IR and are determined by the target’s backend.

The resulting pointer is in the [alloca address space](high-level-structure.md#alloca-addrspace) defined in the [datalayout string](high-level-structure.md#langref-datalayout).

Standard pointer arithmetic (`getelementptr`, `ptradd`) and lifetime intrinsics ([llvm.lifetime.start](intrinsics-general.md#int-lifestart), [llvm.lifetime.end](intrinsics-general.md#int-lifeend)) are permitted on the returned pointer. However, because the physical layout is opaque, using physical pointer arithmetic requires the frontend or emitting pass to have explicit knowledge of the backend’s layout rules.

<a id="id450"></a>

##### Example:

    %S = type { i32, i32, i32, i32 }

    ; Allocate one instance of %S on the stack
    %ptr = call elementtype(%S) ptr @llvm.structured.alloca()

    ; Access the second field of the allocated struct
    %field_ptr = call ptr @llvm.structured.gep(ptr elementtype(%S) %ptr, i32 1)
    %val = load i32, ptr %field_ptr

    ; Allocate an array of 10 i32s on the stack
    %array_ptr = call elementtype([10 x i32]) ptr @llvm.structured.alloca()

    ; Allocate a single i32 on the stack
    %scalar_ptr = call elementtype(i32) ptr @llvm.structured.alloca()

    ; Although the exact size of 'i32' or '%S' is opaque, it is constant
    ; for the duration of the module. This allows, for example, reusing
    ; an allocation slot for two different values of the same type.
    %a = call elementtype(float) ptr @llvm.structured.alloca()
    %b = call elementtype(float) ptr @llvm.structured.alloca()
    ; %a and %b are guaranteed to have the same allocation size.

<a id="llvm-get-dynamic-area-offset-intrinsic"></a>

<a id="int-get-dynamic-area-offset"></a>

#### ‘`llvm.get.dynamic.area.offset`’ Intrinsic

<a id="id451"></a>

##### Syntax:

    declare i32 @llvm.get.dynamic.area.offset.i32()
    declare i64 @llvm.get.dynamic.area.offset.i64()

<a id="id452"></a>

##### Overview:

The ‘`llvm.get.dynamic.area.offset.*`’ intrinsic family is used to get the offset from native stack pointer to the address of the most recent dynamic alloca on the caller’s stack. These intrinsics are intended for use in combination with [llvm.stacksave](#int-stacksave) to get a pointer to the most recent dynamic alloca. This is useful, for example, for AddressSanitizer’s stack unpoisoning routines.

<a id="id453"></a>

##### Semantics:

These intrinsics return a non-negative integer value that can be used to get the address of the most recent dynamic alloca, allocated by [alloca](instructions-memory.md#i-alloca) on the caller’s stack. In particular, for targets where stack grows downwards, adding this offset to the native stack pointer would get the address of the most recent dynamic alloca. For targets where stack grows upwards, the situation is a bit more complicated, because subtracting this value from stack pointer would get the address one past the end of the most recent dynamic alloca.

Although for most targets `llvm.get.dynamic.area.offset <int_get_dynamic_area_offset>` returns just a zero, for others, such as PowerPC and PowerPC64, it returns a compile-time-known constant value.

The return value type of [llvm.get.dynamic.area.offset](#int-get-dynamic-area-offset) must match the target’s [alloca address space](high-level-structure.md#alloca-addrspace) type.

<a id="llvm-prefetch-intrinsic"></a>

<a id="int-prefetch"></a>

#### ‘`llvm.prefetch`’ Intrinsic

<a id="id454"></a>

##### Syntax:

    declare void @llvm.prefetch(ptr <address>, i32 <rw>, i32 <locality>, i32 <cache type>)

<a id="id455"></a>

##### Overview:

The ‘`llvm.prefetch`’ intrinsic is a hint to the code generator to insert a prefetch instruction if supported; otherwise, it is a noop. Prefetches have no effect on the behavior of the program but can change its performance characteristics.

<a id="id456"></a>

##### Arguments:

`address` is the address to be prefetched, `rw` is the specifier determining if the fetch should be for a read (0) or write (1), and `locality` is a temporal locality specifier ranging from (0) - no locality, to (3) - extremely local keep in cache. The `cache type` specifies whether the prefetch is performed on the data (1) or instruction (0) cache. The `rw`, `locality` and `cache type` arguments must be constant integers.

<a id="id457"></a>

##### Semantics:

This intrinsic does not modify the behavior of the program. In particular, prefetches cannot trap and do not produce a value. On targets that support this intrinsic, the prefetch can provide hints to the processor cache for better performance.

<a id="llvm-pcmarker-intrinsic"></a>

#### ‘`llvm.pcmarker`’ Intrinsic

<a id="id458"></a>

##### Syntax:

    declare void @llvm.pcmarker(i32 <id>)

<a id="id459"></a>

##### Overview:

The ‘`llvm.pcmarker`’ intrinsic is a method to export a Program Counter (PC) in a region of code to simulators and other tools. The method is target specific, but it is expected that the marker will use exported symbols to transmit the PC of the marker. The marker makes no guarantees that it will remain with any specific instruction after optimizations. It is possible that the presence of a marker will inhibit optimizations. The intended use is to be inserted after optimizations to allow correlations of simulation runs.

<a id="id460"></a>

##### Arguments:

`id` is a numerical id identifying the marker.

<a id="id461"></a>

##### Semantics:

This intrinsic does not modify the behavior of the program. Backends that do not support this intrinsic may ignore it.

<a id="llvm-readcyclecounter-intrinsic"></a>

#### ‘`llvm.readcyclecounter`’ Intrinsic

<a id="id462"></a>

##### Syntax:

    declare i64 @llvm.readcyclecounter()

<a id="id463"></a>

##### Overview:

The ‘`llvm.readcyclecounter`’ intrinsic provides access to the cycle counter register (or similar low latency, high accuracy clocks) on those targets that support it. On X86, it should map to RDTSC. On Alpha, it should map to RPCC. As the backing counters overflow quickly (on the order of 9 seconds on alpha), this should only be used for small timings.

<a id="id464"></a>

##### Semantics:

When directly supported, reading the cycle counter should not modify any memory. Implementations are allowed to either return an application specific value or a system wide value. On backends without support, this is lowered to a constant 0.

Note that runtime support may be conditional on the privilege-level code is running at and the host platform.

<a id="llvm-readsteadycounter-intrinsic"></a>

#### ‘`llvm.readsteadycounter`’ Intrinsic

<a id="id465"></a>

##### Syntax:

    declare i64 @llvm.readsteadycounter()

<a id="id466"></a>

##### Overview:

The ‘`llvm.readsteadycounter`’ intrinsic provides access to the fixed frequency clock on targets that support it. Unlike ‘`llvm.readcyclecounter`’, this clock is expected to tick at a constant rate, making it suitable for measuring elapsed time. The actual frequency of the clock is implementation defined.

<a id="id467"></a>

##### Semantics:

When directly supported, reading the steady counter should not modify any memory. Implementations are allowed to either return an application specific value or a system wide value. On backends without support, this is lowered to a constant 0.

<a id="llvm-clear-cache-intrinsic"></a>

#### ‘`llvm.clear_cache`’ Intrinsic

<a id="id468"></a>

##### Syntax:

    declare void @llvm.clear_cache(ptr, ptr)

<a id="id469"></a>

##### Overview:

The ‘`llvm.clear_cache`’ intrinsic ensures visibility of modifications in the specified range to the execution unit of the processor. On targets with non-unified instruction and data cache, the implementation flushes the instruction cache.

<a id="id470"></a>

##### Semantics:

On platforms with coherent instruction and data caches (e.g., x86), this intrinsic is a nop. On platforms with non-coherent instruction and data cache (e.g., ARM, MIPS), the intrinsic is lowered either to appropriate instructions or a system call, if cache flushing requires special privileges.

The default behavior is to emit a call to `__clear_cache` from the run time library.

This intrinsic does *not* empty the instruction pipeline. Modifications of the current function are outside the scope of the intrinsic.

<a id="llvm-instrprof-increment-intrinsic"></a>

#### ‘`llvm.instrprof.increment`’ Intrinsic

<a id="id471"></a>

##### Syntax:

    declare void @llvm.instrprof.increment(ptr <name>, i64 <hash>,
                                           i32 <num-counters>, i32 <index>)

<a id="id472"></a>

##### Overview:

The ‘`llvm.instrprof.increment`’ intrinsic can be emitted by a frontend for use with instrumentation-based profiling. These will be lowered by the `-instrprof` pass to generate execution counts of a program at runtime.

<a id="id473"></a>

##### Arguments:

The first argument is a pointer to a global variable containing the name of the entity being instrumented. This should generally be the (mangled) function name for a set of counters.

The second argument is a hash value that can be used by the consumer of the profile data to detect changes to the instrumented source, and the third is the number of counters associated with `name`. It is an error if `hash` or `num-counters` differ between two instances of `instrprof.increment` that refer to the same name.

The last argument refers to which of the counters for `name` should be incremented. It should be a value between 0 and `num-counters`.

<a id="id474"></a>

##### Semantics:

This intrinsic represents an increment of a profiling counter. It will cause the `-instrprof` pass to generate the appropriate data structures and the code to increment the appropriate value, in a format that can be written out by a compiler runtime and consumed via the `llvm-profdata` tool.

The intrinsic is lowered differently for contextual profiling by the `-ctx-instr-lower` pass. Here:

- the entry basic block increment counter is lowered as a call to compiler-rt, to either `__llvm_ctx_profile_start_context` or `__llvm_ctx_profile_get_context`. Either returns a pointer to a context object which contains a buffer into which counter increments can happen. Note that the pointer value returned by compiler-rt may have its LSB set - counter increments happen offset from the address with the LSB cleared.

- all the other lowerings of `llvm.instrprof.increment[.step]` happen within that context.

- the context is assumed to be a local value to the function, and no concurrency concerns need to be handled by LLVM.

<a id="llvm-instrprof-increment-step-intrinsic"></a>

#### ‘`llvm.instrprof.increment.step`’ Intrinsic

<a id="id475"></a>

##### Syntax:

    declare void @llvm.instrprof.increment.step(ptr <name>, i64 <hash>,
                                                i32 <num-counters>,
                                                i32 <index>, i64 <step>)

<a id="id476"></a>

##### Overview:

The ‘`llvm.instrprof.increment.step`’ intrinsic is an extension to the ‘`llvm.instrprof.increment`’ intrinsic with an additional fifth argument to specify the step of the increment.

<a id="id477"></a>

##### Arguments:

The first four arguments are the same as ‘`llvm.instrprof.increment`’ intrinsic.

The last argument specifies the value of the increment of the counter variable.

<a id="id478"></a>

##### Semantics:

See description of ‘`llvm.instrprof.increment`’ intrinsic.

<a id="llvm-instrprof-callsite-intrinsic"></a>

#### ‘`llvm.instrprof.callsite`’ Intrinsic

<a id="id479"></a>

##### Syntax:

    declare void @llvm.instrprof.callsite(ptr <name>, i64 <hash>,
                                          i32 <num-counters>,
                                          i32 <index>, ptr <callsite>)

<a id="id480"></a>

##### Overview:

The ‘`llvm.instrprof.callsite`’ intrinsic should be emitted before a callsite that’s not to a “fake” callee (like another intrinsic or asm). It is used by contextual profiling and has side-effects. Its lowering happens in IR, and target-specific backends should never encounter it.

<a id="id481"></a>

##### Arguments:

The first 4 arguments are similar to `llvm.instrprof.increment`. The indexing is specific to callsites, meaning callsites are indexed from 0, independent from the indexes used by the other intrinsics (such as `llvm.instrprof.increment[.step]`).

The last argument is the called value of the callsite this intrinsic precedes.

<a id="id482"></a>

##### Semantics:

This is lowered by contextual profiling. In contextual profiling, functions get, from compiler-rt, a pointer to a context object. The context object consists of a buffer LLVM can use to perform counter increments (i.e., the lowering of `llvm.instrprof.increment[.step]`. The address range following the counter buffer, `<num-counters>` x `sizeof(ptr)` - sized, is expected to contain pointers to contexts of functions called from this function (“subcontexts”). LLVM does not dereference into that memory region, just calculates GEPs.

The lowering of `llvm.instrprof.callsite` consists of:

- write to `__llvm_ctx_profile_expected_callee` the `<callsite>` value;

- write to `__llvm_ctx_profile_callsite` the address into this function’s context of the `<index>` position into the subcontexts region.

`__llvm_ctx_profile_{expected_callee|callsite}` are initialized by compiler-rt and are TLS. They are both vectors of pointers of size 2. The index into each is determined when the current function obtains the pointer to its context from compiler-rt. The pointer’s LSB gives the index.

<a id="llvm-instrprof-timestamp-intrinsic"></a>

#### ‘`llvm.instrprof.timestamp`’ Intrinsic

<a id="id483"></a>

##### Syntax:

    declare void @llvm.instrprof.timestamp(i8* <name>, i64 <hash>,
                                           i32 <num-counters>, i32 <index>)

<a id="id484"></a>

##### Overview:

The ‘`llvm.instrprof.timestamp`’ intrinsic is used to implement temporal profiling.

<a id="id485"></a>

##### Arguments:

The arguments are the same as ‘`llvm.instrprof.increment`’. The `index` is expected to always be zero.

<a id="id486"></a>

##### Semantics:

Similar to the ‘`llvm.instrprof.increment`’ intrinsic, but it stores a timestamp representing when this function was executed for the first time.

<a id="llvm-instrprof-cover-intrinsic"></a>

#### ‘`llvm.instrprof.cover`’ Intrinsic

<a id="id487"></a>

##### Syntax:

    declare void @llvm.instrprof.cover(ptr <name>, i64 <hash>,
                                       i32 <num-counters>, i32 <index>)

<a id="id488"></a>

##### Overview:

The ‘`llvm.instrprof.cover`’ intrinsic is used to implement coverage instrumentation.

<a id="id489"></a>

##### Arguments:

The arguments are the same as the first four arguments of ‘`llvm.instrprof.increment`’.

<a id="id490"></a>

##### Semantics:

Similar to the ‘`llvm.instrprof.increment`’ intrinsic, but it stores zero to the profiling variable to signify that the function has been covered. We store zero because this is more efficient on some targets.

<a id="llvm-instrprof-value-profile-intrinsic"></a>

#### ‘`llvm.instrprof.value.profile`’ Intrinsic

<a id="id491"></a>

##### Syntax:

    declare void @llvm.instrprof.value.profile(ptr <name>, i64 <hash>,
                                               i64 <value>, i32 <value_kind>,
                                               i32 <index>)

<a id="id492"></a>

##### Overview:

The ‘`llvm.instrprof.value.profile`’ intrinsic can be emitted by a frontend for use with instrumentation-based profiling. This will be lowered by the `-instrprof` pass to find out the target values, instrumented expressions take in a program at runtime.

<a id="id493"></a>

##### Arguments:

The first argument is a pointer to a global variable containing the name of the entity being instrumented. `name` should generally be the (mangled) function name for a set of counters.

The second argument is a hash value that can be used by the consumer of the profile data to detect changes to the instrumented source. It is an error if `hash` differs between two instances of `llvm.instrprof.*` that refer to the same name.

The third argument is the value of the expression being profiled. The profiled expression’s value should be representable as an unsigned 64-bit value. The fourth argument represents the kind of value profiling that is being done. The supported value profiling kinds are enumerated through the `InstrProfValueKind` type declared in the `<include/llvm/ProfileData/InstrProf.h>` header file. The last argument is the index of the instrumented expression within `name`. It should be \>= 0.

<a id="id494"></a>

##### Semantics:

This intrinsic represents the point where a call to a runtime routine should be inserted for value profiling of target expressions. `-instrprof` pass will generate the appropriate data structures and replace the `llvm.instrprof.value.profile` intrinsic with the call to the profile runtime library with proper arguments.

<a id="llvm-instrprof-mcdc-parameters-intrinsic"></a>

#### ‘`llvm.instrprof.mcdc.parameters`’ Intrinsic

<a id="id495"></a>

##### Syntax:

    declare void @llvm.instrprof.mcdc.parameters(ptr <name>, i64 <hash>,
                                                 i32 <bitmap-bits>)

<a id="id496"></a>

##### Overview:

The ‘`llvm.instrprof.mcdc.parameters`’ intrinsic is used to initiate MC/DC code coverage instrumentation for a function.

<a id="id497"></a>

##### Arguments:

The first argument is a pointer to a global variable containing the name of the entity being instrumented. This should generally be the (mangled) function name for a set of counters.

The second argument is a hash value that can be used by the consumer of the profile data to detect changes to the instrumented source.

The third argument is the number of bitmap bits required by the function to record the number of test vectors executed for each boolean expression.

<a id="id498"></a>

##### Semantics:

This intrinsic represents basic MC/DC parameters initiating one or more MC/DC instrumentation sequences in a function. It will cause the `-instrprof` pass to generate the appropriate data structures and the code to instrument MC/DC test vectors in a format that can be written out by a compiler runtime and consumed via the `llvm-profdata` tool.

<a id="llvm-instrprof-mcdc-tvbitmap-update-intrinsic"></a>

#### ‘`llvm.instrprof.mcdc.tvbitmap.update`’ Intrinsic

<a id="id499"></a>

##### Syntax:

    declare void @llvm.instrprof.mcdc.tvbitmap.update(ptr <name>, i64 <hash>,
                                                      i32 <bitmap-index>,
                                                      ptr <mcdc-temp-addr>)

<a id="id500"></a>

##### Overview:

The ‘`llvm.instrprof.mcdc.tvbitmap.update`’ intrinsic is used to track MC/DC test vector execution after each boolean expression has been fully executed. The overall value of the condition bitmap, after it has been successively updated with the true or false evaluation of each condition, uniquely identifies an executed MC/DC test vector and is used as a bit index into the global test vector bitmap.

<a id="id501"></a>

##### Arguments:

The first argument is a pointer to a global variable containing the name of the entity being instrumented. This should generally be the (mangled) function name for a set of counters.

The second argument is a hash value that can be used by the consumer of the profile data to detect changes to the instrumented source.

The third argument is the bit index into the global test vector bitmap corresponding to the function.

The fourth argument is the address of the condition bitmap, which contains a value representing an executed MC/DC test vector. It is loaded and used as the bit index of the test vector bitmap.

<a id="id502"></a>

##### Semantics:

This intrinsic represents the final operation of an MC/DC instrumentation sequence and will cause the `-instrprof` pass to generate the code to instrument an update of a function’s global test vector bitmap to indicate that a test vector has been executed. The global test vector bitmap can be consumed by the `llvm-profdata` and `llvm-cov` tools.

<a id="llvm-thread-pointer-intrinsic"></a>

#### ‘`llvm.thread.pointer`’ Intrinsic

<a id="id503"></a>

##### Syntax:

    declare ptr @llvm.thread.pointer.p0()
    declare ptr addrspace(5) @llvm.thread.pointer.p5()

<a id="id504"></a>

##### Overview:

The ‘`llvm.thread.pointer`’ intrinsic returns the value of the thread pointer.

<a id="id505"></a>

##### Semantics:

The ‘`llvm.thread.pointer`’ intrinsic returns a pointer to the TLS area for the current thread. The exact semantics of this value are target specific: it may point to the start of TLS area, to the end, or somewhere in the middle. Depending on the target, this intrinsic may read a register, call a helper function, read from an alternate memory space, or perform other operations necessary to locate the TLS area. Not all targets support this intrinsic. The address space must be the [globals address space](high-level-structure.md#globals-addrspace).

<a id="llvm-call-preallocated-setup-intrinsic"></a>

#### ‘`llvm.call.preallocated.setup`’ Intrinsic

<a id="id506"></a>

##### Syntax:

    declare token @llvm.call.preallocated.setup(i32 %num_args)

<a id="id507"></a>

##### Overview:

The ‘`llvm.call.preallocated.setup`’ intrinsic returns a token which can be used with a call’s `"preallocated"` operand bundle to indicate that certain arguments are allocated and initialized before the call.

<a id="id508"></a>

##### Semantics:

The ‘`llvm.call.preallocated.setup`’ intrinsic returns a token which is associated with at most one call. The token can be passed to ‘`@llvm.call.preallocated.arg`’ to get a pointer to get that corresponding argument. The token must be the parameter to a `"preallocated"` operand bundle for the corresponding call.

Nested calls to ‘`llvm.call.preallocated.setup`’ are allowed, but must be properly nested. e.g.

    %t1 = call token @llvm.call.preallocated.setup(i32 0)
    %t2 = call token @llvm.call.preallocated.setup(i32 0)
    call void foo() ["preallocated"(token %t2)]
    call void foo() ["preallocated"(token %t1)]

is allowed, but not

    %t1 = call token @llvm.call.preallocated.setup(i32 0)
    %t2 = call token @llvm.call.preallocated.setup(i32 0)
    call void foo() ["preallocated"(token %t1)]
    call void foo() ["preallocated"(token %t2)]

<a id="llvm-call-preallocated-arg-intrinsic"></a>

<a id="int-call-preallocated-arg"></a>

#### ‘`llvm.call.preallocated.arg`’ Intrinsic

<a id="id509"></a>

##### Syntax:

    declare ptr @llvm.call.preallocated.arg(token %setup_token, i32 %arg_index)

<a id="id510"></a>

##### Overview:

The ‘`llvm.call.preallocated.arg`’ intrinsic returns a pointer to the corresponding preallocated argument for the preallocated call.

<a id="id511"></a>

##### Semantics:

The ‘`llvm.call.preallocated.arg`’ intrinsic returns a pointer to the `%arg_index`th argument with the `preallocated` attribute for the call associated with the `%setup_token`, which must be from ‘`llvm.call.preallocated.setup`’.

A call to ‘`llvm.call.preallocated.arg`’ must have a call site `preallocated` attribute. The type of the `preallocated` attribute must match the type used by the `preallocated` attribute of the corresponding argument at the preallocated call. The type is used in the case that an `llvm.call.preallocated.setup` does not have a corresponding call (e.g., due to DCE), where otherwise we cannot know how large the arguments are.

It is undefined behavior if this is called with a token from an ‘`llvm.call.preallocated.setup`’ if another ‘`llvm.call.preallocated.setup`’ has already been called or if the preallocated call corresponding to the ‘`llvm.call.preallocated.setup`’ has already been called.

<a id="llvm-call-preallocated-teardown-intrinsic"></a>

<a id="int-call-preallocated-teardown"></a>

#### ‘`llvm.call.preallocated.teardown`’ Intrinsic

<a id="id512"></a>

##### Syntax:

    declare ptr @llvm.call.preallocated.teardown(token %setup_token)

<a id="id513"></a>

##### Overview:

The ‘`llvm.call.preallocated.teardown`’ intrinsic cleans up the stack created by a ‘`llvm.call.preallocated.setup`’.

<a id="id514"></a>

##### Semantics:

The token argument must be a ‘`llvm.call.preallocated.setup`’.

The ‘`llvm.call.preallocated.teardown`’ intrinsic cleans up the stack allocated by the corresponding ‘`llvm.call.preallocated.setup`’. Exactly one of this or the preallocated call must be called to prevent stack leaks. It is undefined behavior to call both a ‘`llvm.call.preallocated.teardown`’ and the preallocated call for a given ‘`llvm.call.preallocated.setup`’.

For example, if the stack is allocated for a preallocated call by a ‘`llvm.call.preallocated.setup`’, then an initializer function called on an allocated argument throws an exception, there should be a ‘`llvm.call.preallocated.teardown`’ in the exception handler to prevent stack leaks.

Following the nesting rules in ‘`llvm.call.preallocated.setup`’, nested calls to ‘`llvm.call.preallocated.setup`’ and ‘`llvm.call.preallocated.teardown`’ are allowed but must be properly nested.

<a id="id515"></a>

##### Example:

        %cs = call token @llvm.call.preallocated.setup(i32 1)
        %x = call ptr @llvm.call.preallocated.arg(token %cs, i32 0) preallocated(i32)
        invoke void @constructor(ptr %x) to label %conta unwind label %contb
    conta:
        call void @foo1(ptr preallocated(i32) %x) ["preallocated"(token %cs)]
        ret void
    contb:
        %s = catchswitch within none [label %catch] unwind to caller
    catch:
        %p = catchpad within %s []
        call void @llvm.call.preallocated.teardown(token %cs)
        ret void
