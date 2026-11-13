[Wiki](../index.md) › [LLVM LangRef](index.md)

# Type system

LLVM 23.1.0 Language Reference, part of the [index](index.md). Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html>. License: Apache-2.0 with LLVM exception.

<a id="type-system"></a>

<a id="typesystem"></a>

## Type System

The LLVM type system is one of the most important features of the intermediate representation. Being typed enables a number of optimizations to be performed on the intermediate representation directly, without having to do extra analyses on the side before the transformation. A strong type system makes it easier to read the generated code and enables novel analyses and transformations that are not feasible to perform on normal three address code representations.

<a id="void-type"></a>

<a id="t-void"></a>

### Void Type

**Overview:**

The void type does not represent any value and has no size.

**Syntax:**

    void

<a id="function-type"></a>

<a id="t-function"></a>

### Function Type

**Overview:**

The function type can be thought of as a function signature. It consists of a return type and a list of formal parameter types. The return type of a function type is a void type or first class type — except for [label](#t-label) and [metadata](#t-metadata) types.

**Syntax:**

    <returntype> (<parameter list>)

…where ‘`<parameter list>`’ is a comma-separated list of type specifiers. Optionally, the parameter list may include a type `...`, which indicates that the function takes a variable number of arguments. Variable argument functions can access their arguments with the [variable argument handling intrinsic](intrinsics-overview-and-basic.md#int-varargs) functions. ‘`<returntype>`’ is any type except [label](#t-label) and [metadata](#t-metadata).

**Examples:**

|                    |                                                                                                                                                                                                                     |
|--------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `i32 (i32)`        | function taking an `i32`, returning an `i32`                                                                                                                                                                        |
| `i32 (ptr, ...)`   | A vararg function that takes at least one [pointer](#t-pointer) argument and returns an integer. This is the signature for `printf` in LLVM. |
| `{i32, i32} (i32)` | A function taking an `i32`, returning a [structure](#t-struct) containing two `i32` values                                                   |

<a id="opaque-structure-types"></a>

<a id="t-opaque"></a>

### Opaque Structure Types

**Overview:**

Opaque structure types are used to represent structure types that do not have a body specified. This corresponds (for example) to the C notion of a forward declared structure. They can be named (`%X`) or unnamed (`%52`).

It is not possible to create SSA values with an opaque structure type. In practice, this largely limits their use to the value type of external globals.

**Syntax:**

    %X = type opaque
    %52 = type opaque

    @g = external global %X

<a id="first-class-types"></a>

<a id="t-firstclass"></a>

### First Class Types

The [first class](#t-firstclass) types are perhaps the most important. Values of these types are the only ones which can be produced by instructions.

<a id="single-value-types"></a>

<a id="t-single-value"></a>

#### Single Value Types

These are the types that are valid in registers from CodeGen’s perspective.

<a id="integer-type"></a>

<a id="t-integer"></a>

##### Integer Type

**Overview:**

The integer type is a very simple type that simply specifies an arbitrary bit width for the integer type desired. Any bit width from 1 bit to 2<sup>23</sup> (about 8 million) can be specified.

**Syntax:**

    iN

The number of bits the integer will occupy is specified by the `N` value.

<a id="examples"></a>

###### Examples:

| Type       | Description                                  |
|------------|----------------------------------------------|
| `i1`       | a single-bit integer.                        |
| `i32`      | a 32-bit integer.                            |
| `i1942652` | a really big integer of over 1 million bits. |

<a id="byte-type"></a>

<a id="t-byte"></a>

##### Byte Type

**Overview:**

The byte type represents raw memory data in SSA registers. It should be used when it cannot be determined whether a value holds a pointer or another type at run time, or if the value contains uninitialized or poison data. Frontends are expected to use a byte type when:

1.  Lowering memory operations like `memcpy` and `memmove` to load/store pairs without knowing the underlying type being copied.

2.  Working with union types that can hold a pointer alongside a non-pointer type.

3.  Working with possibly uninitialized data.

Otherwise, when known, the specific type should be used. Each bit can be:

- An integer bit (0 or 1)

- Part of a pointer value

- `poison`

Any bit width from 1 bit to 2<sup>23</sup> (about 8 million) can be specified.

The per-bit semantics described above (poison and conditional pointer provenance preservation) are mid-end only. At the IR-to-MIR boundary both SelectionDAG and GlobalISel lower `bN` as the equi-sized integer scalar (`iN`/`sN`); backend passes do not see the byte type and do not preserve its bit-level semantics.

**Syntax:**

    bN

The number of bits the byte occupies is specified by the `N` value.

<a id="id4"></a>

###### Examples:

| Type   | Description              |
|--------|--------------------------|
| `b1`   | a single-bit byte value. |
| `b32`  | a 32-bit byte value.     |
| `b128` | a 128-bit byte value.    |

<a id="floating-point-types"></a>

<a id="t-floating"></a>

##### Floating-Point Types

| Type        | Description                                                                                                                                                                                                                                                                    |
|-------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `half`      | 16-bit floating-point value (IEEE 754 binary16)                                                                                                                                                                                                                                |
| `bfloat`    | 16-bit “brain” floating-point value (7-bit significand). Provides the same number of exponent bits as `float`, so that it matches its dynamic range, but with greatly reduced precision. Used in Intel’s AVX-512 BF16 extensions and Arm’s ARMv8.6-A extensions, among others. |
| `float`     | 32-bit floating-point value (IEEE 754 binary32)                                                                                                                                                                                                                                |
| `double`    | 64-bit floating-point value (IEEE 754 binary64)                                                                                                                                                                                                                                |
| `fp128`     | 128-bit floating-point value (IEEE 754 binary128)                                                                                                                                                                                                                              |
| `x86_fp80`  | 80-bit floating-point value (X87)                                                                                                                                                                                                                                              |
| `ppc_fp128` | 128-bit floating-point value (two 64-bits)                                                                                                                                                                                                                                     |

<a id="x86-amx-type"></a>

##### X86_amx Type

**Overview:**

The x86_amx type represents a value held in an AMX tile register on an x86 machine. The operations allowed on it are quite limited. Only a few intrinsics are allowed: stride load and store, zero and dot product. No instruction is allowed for this type. There are no arguments, arrays, pointers, vectors or constants of this type.

**Syntax:**

    x86_amx

<a id="pointer-type"></a>

<a id="t-pointer"></a>

##### Pointer Type

**Overview:**

The pointer type `ptr` is used to specify memory locations. Pointers are commonly used to reference objects in memory.

Pointer types may have an optional address space attribute defining the numbered address space where the pointed-to object resides. For example, `ptr addrspace(5)` is a pointer to address space 5. In addition to integer constants, `addrspace` can also reference one of the address spaces defined in the [datalayout string](high-level-structure.md#langref-datalayout). `addrspace("A")` will use the alloca address space, `addrspace("G")` the default globals address space and `addrspace("P")` the program address space.

The representation of pointers can be different for each address space and does not necessarily need to be a plain integer address (e.g., for [non-integral pointers](high-level-structure.md#nointptrtype)). In addition to a representation bits size, pointers in each address space also have an index size which defines the bitwidth of indexing operations as well as the size of `integer addresses` in this address space. For example, CHERI capabilities are twice the size of the underlying addresses to accommodate for additional metadata such as bounds and permissions: on a 32-bit system the bitwidth of the pointer representation size is 64, but the underlying address width remains 32 bits.

The default address space is number zero.

The semantics of non-zero address spaces are target-specific. Memory access through a non-dereferenceable pointer is undefined behavior in any address space. Pointers with the bit-value 0 are only assumed to be non-dereferenceable in address space 0, unless the function is marked with the `null_pointer_is_valid` attribute. However, *volatile* access to any non-dereferenceable address may have defined behavior (according to the target), and in this case the attribute is not needed even for address 0.

If an object can be proven accessible through a pointer with a different address space, the access may be modified to use that address space. Exceptions apply if the operation is `volatile`.

Prior to LLVM 15, pointer types also specified a pointee type, such as `i8*`, `[4 x i32]*` or `i32 (i32*)*`. In LLVM 15, such “typed pointers” are still supported under non-default options. See the [opaque pointers document](OpaquePointers.html) for more information.

<a id="target-extension-type"></a>

<a id="t-target-type"></a>

##### Target Extension Type

**Overview:**

Target extension types represent types that must be preserved through optimization, but are otherwise generally opaque to the compiler. They may be used as function parameters or arguments, and in [phi](instructions-other.md#i-phi) or [select](instructions-other.md#i-select) instructions. Some types may be also used in [alloca](instructions-memory.md#i-alloca) instructions or as global values, and correspondingly it is legal to use [load](instructions-memory.md#i-load) and [store](instructions-memory.md#i-store) instructions on them. Full semantics for these types are defined by the target.

The only constants that target extension types may have are `zeroinitializer`, `undef`, and `poison`. Other possible values for target extension types may arise from target-specific intrinsics and functions.

These types cannot be converted to other types. As such, it is not legal to use them in [bitcast](instructions-conversion.md#i-bitcast) instructions (as a source or target type), nor is it legal to use them in [ptrtoint](instructions-conversion.md#i-ptrtoint) or [inttoptr](instructions-conversion.md#i-inttoptr) instructions. Similarly, they are not legal to use in an [icmp](instructions-other.md#i-icmp) instruction.

Target extension types have a name and optional type or integer parameters. The meanings of name and parameters are defined by the target. When being defined in LLVM IR, all of the type parameters must precede all of the integer parameters.

Specific target extension types are registered with LLVM as having specific properties. These properties can be used to restrict the type from appearing in certain contexts, such as being the type of a global variable or having a `zeroinitializer` constant be valid. A complete list of type properties may be found in the documentation for `llvm::TargetExtType::Property` ([doxygen](https://llvm.org/doxygen/classllvm_1_1TargetExtType.html)).

**Syntax:**

    target("label")
    target("label", void)
    target("label", void, i32)
    target("label", 0, 1, 2)
    target("label", void, i32, 0, 1, 2)

<a id="vector-type"></a>

<a id="t-vector"></a>

##### Vector Type

**Overview:**

A vector type is a simple derived type that represents a vector of elements. Vector types are used when multiple primitive data are operated in parallel using a single instruction (SIMD). A vector type requires a size (number of elements), an underlying primitive data type, and a scalable property to represent vectors where the exact hardware vector length is unknown at compile time. Vector types are considered [first class](#t-firstclass).

**Memory Layout:**

In general vector elements are laid out in memory in the same way as [array types](#t-array). Such an analogy works fine as long as the vector elements are byte sized. However, when the elements of the vector aren’t byte sized it gets a bit more complicated. One way to describe the layout is by describing what happens when a vector such as `<N x iM>` is bitcasted to an integer type with N\*M bits, and then following the rules for storing such an integer to memory.

A bitcast from a vector type to a scalar integer type will see the elements being packed together (without padding). The order in which elements are inserted in the integer depends on endianness. For little endian element zero is put in the least significant bits of the integer, and for big endian element zero is put in the most significant bits.

Using a vector such as `<i4 1, i4 2, i4 3, i4 5>` as an example, together with the analogy that we can replace a vector store by a bitcast followed by an integer store, we get this for big endian:

    %val = bitcast <4 x i4> <i4 1, i4 2, i4 3, i4 5> to i16

    ; Bitcasting from a vector to an integral type can be seen as
    ; concatenating the values:
    ;   %val now has the hexadecimal value 0x1235.

    store i16 %val, ptr %ptr

    ; In memory the content will be (8-bit addressing):
    ;
    ;    [%ptr + 0]: 00010010  (0x12)
    ;    [%ptr + 1]: 00110101  (0x35)

The same example for little endian:

    %val = bitcast <4 x i4> <i4 1, i4 2, i4 3, i4 5> to i16

    ; Bitcasting from a vector to an integral type can be seen as
    ; concatenating the values:
    ;   %val now has the hexadecimal value 0x5321.

    store i16 %val, ptr %ptr

    ; In memory the content will be (8-bit addressing):
    ;
    ;    [%ptr + 0]: 00100001  (0x21)
    ;    [%ptr + 1]: 01010011  (0x53)

When `<N*M>` isn’t evenly divisible by the byte size the exact memory layout is unspecified (just like it is for an integral type of the same size). This is because different targets could put the padding at different positions when the type size is smaller than the type’s store size.

**Syntax:**

    < <# elements> x <elementtype> >          ; Fixed-length vector
    < vscale x <# elements> x <elementtype> > ; Scalable vector

The number of elements is a constant integer value larger than 0; elementtype may be any integer, floating-point, pointer type, or a sized target extension type that has the `CanBeVectorElement` property. Vectors of size zero are not allowed. For scalable vectors, the total number of elements is a constant multiple (called vscale) of the specified number of elements; vscale is a positive power-of-two integer that is unknown at compile time and the same hardware-dependent constant for all scalable vectors at run time. The size of a specific scalable vector type is thus constant within IR, even if the exact size in bytes cannot be determined until run time.

**Examples:**

| Type                 | Description                                        |
|----------------------|----------------------------------------------------|
| `<4 x i32>`          | Vector of 4 32-bit integer values.                 |
| `<8 x float>`        | Vector of 8 32-bit floating-point values.          |
| `<2 x i64>`          | Vector of 2 64-bit integer values.                 |
| `<4 x ptr>`          | Vector of 4 pointers                               |
| `<vscale x 4 x i32>` | Vector with a multiple of 4 32-bit integer values. |

<a id="label-type"></a>

<a id="t-label"></a>

#### Label Type

**Overview:**

The label type represents code labels.

**Syntax:**

    label

<a id="token-type"></a>

<a id="t-token"></a>

#### Token Type

**Overview:**

The token type is used when a value is associated with an instruction but all uses of the value must not attempt to introspect or obscure it. As such, it is not appropriate to have a [phi](instructions-other.md#i-phi) or [select](instructions-other.md#i-select) of type token.

**Syntax:**

    token

<a id="metadata-type"></a>

<a id="t-metadata"></a>

#### Metadata Type

**Overview:**

The metadata type represents embedded metadata. No derived types may be created from metadata except for [function](#t-function) arguments.

**Syntax:**

    metadata

<a id="aggregate-types"></a>

<a id="t-aggregate"></a>

#### Aggregate Types

Aggregate Types are a subset of derived types that can contain multiple member types. [Arrays](#t-array) and [structs](#t-struct) are aggregate types. [Vectors](#t-vector) are not considered to be aggregate types.

<a id="array-type"></a>

<a id="t-array"></a>

##### Array Type

**Overview:**

The array type is a very simple derived type that arranges elements sequentially in memory. The array type requires a size (number of elements) and an underlying data type.

**Syntax:**

    [<# elements> x <elementtype>]

The number of elements is a constant integer value; `elementtype` may be any type with a size.

**Examples:**

| Type         | Description                        |
|--------------|------------------------------------|
| `[40 x i32]` | Array of 40 32-bit integer values. |
| `[41 x i32]` | Array of 41 32-bit integer values. |
| `[4 x i8]`   | Array of 4 8-bit integer values.   |

Here are some examples of multidimensional arrays:

| Type                    | Description                                            |
|-------------------------|--------------------------------------------------------|
| `[3 x [4 x i32]]`       | 3x4 array of 32-bit integer values.                    |
| `[12 x [10 x float]]`   | 12x10 array of single precision floating-point values. |
| `[2 x [3 x [4 x i16]]]` | 2x3x4 array of 16-bit integer values.                  |

There is no restriction on indexing beyond the end of the array implied by a static type (though there are restrictions on indexing beyond the bounds of an [allocated object](high-level-structure.md#allocatedobjects) in some cases). This means that single-dimension ‘variable sized array’ addressing can be implemented in LLVM with a zero length array type. An implementation of ‘pascal style arrays’ in LLVM could use the type “`{ i32, [0 x float]}`”, for example.

<a id="structure-type"></a>

<a id="t-struct"></a>

##### Structure Type

**Overview:**

The structure type is used to represent a collection of data members together in memory. The elements of a structure may be any type that has a size.

Structures in memory are accessed using ‘`load`’ and ‘`store`’ by getting a pointer to a field with the ‘`getelementptr`’ instruction. Structures in registers are accessed using the ‘`extractvalue`’ and ‘`insertvalue`’ instructions.

Structures may optionally be “packed” structures, which indicate that the alignment of the struct is one byte, and that there is no padding between the elements. In non-packed structs, padding between field types is inserted as defined by the DataLayout string in the module, which is required to match what the underlying code generator expects.

Structures can either be “literal” or “identified”. A literal structure is defined inline with other types (e.g., `[2 x {i32, i32}]`) whereas identified types are always defined at the top level with a name. Literal types are uniqued by their contents and can never be recursive or opaque since there is no way to write one. Identified types can be opaqued and are never uniqued. Identified types must not be recursive.

**Syntax:**

    %T1 = type { <type list> }     ; Identified normal struct type
    %T2 = type <{ <type list> }>   ; Identified packed struct type

**Examples:**

|                     |                                                                                                                                                                        |
|---------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `{ i32, i32, i32 }` | A triple of three `i32` values (this is a “homogeneous” struct as all element types are the same)                                                                      |
| `{ float, ptr }`    | A pair, where the first element is a `float` and the second element is a [pointer](#t-pointer). |
| `<{ i8, i32 }>`     | A packed struct known to be 5 bytes in size.                                                                                                                           |
