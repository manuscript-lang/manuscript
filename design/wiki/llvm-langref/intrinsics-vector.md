[Wiki](../index.md) › [LLVM LangRef](index.md)

# Intrinsics: vector, matrix and predication

LLVM 23.1.0 Language Reference, part of the [index](index.md). Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html>. License: Apache-2.0 with LLVM exception.

<a id="vector-reduction-intrinsics"></a>

### Vector Reduction Intrinsics

Horizontal reductions of vectors can be expressed using the following intrinsics. Each one takes a vector operand as an input and applies its respective operation across all elements of the vector, returning a single scalar result of the same element type.

<a id="llvm-vector-reduce-add-intrinsic"></a>

<a id="int-vector-reduce-add"></a>

#### ‘`llvm.vector.reduce.add.*`’ Intrinsic

<a id="id908"></a>

##### Syntax:

    declare i32 @llvm.vector.reduce.add.v4i32(<4 x i32> %a)
    declare i64 @llvm.vector.reduce.add.v2i64(<2 x i64> %a)

<a id="id909"></a>

##### Overview:

The ‘`llvm.vector.reduce.add.*`’ intrinsics do an integer `ADD` reduction of a vector, returning the result as a scalar. The return type matches the element-type of the vector input.

<a id="id910"></a>

##### Arguments:

The argument to this intrinsic must be a vector of integer values.

<a id="llvm-vector-reduce-fadd-intrinsic"></a>

<a id="int-vector-reduce-fadd"></a>

#### ‘`llvm.vector.reduce.fadd.*`’ Intrinsic

<a id="id911"></a>

##### Syntax:

    declare float @llvm.vector.reduce.fadd.v4f32(float %start_value, <4 x float> %a)
    declare double @llvm.vector.reduce.fadd.v2f64(double %start_value, <2 x double> %a)

<a id="id912"></a>

##### Overview:

The ‘`llvm.vector.reduce.fadd.*`’ intrinsics do a floating-point `ADD` reduction of a vector, returning the result as a scalar. The return type matches the element-type of the vector input.

If the intrinsic call has the ‘reassoc’ flag set, then the reduction will not preserve the associativity of an equivalent scalarized counterpart. Otherwise the reduction will be *sequential*, thus implying that the operation respects the associativity of a scalarized reduction. That is, the reduction begins with the start value and performs an fadd operation with consecutively increasing vector element indices. See the following pseudocode:

    float sequential_fadd(start_value, input_vector)
      result = start_value
      for i = 0 to length(input_vector)
        result = result + input_vector[i]
      return result

<a id="id913"></a>

##### Arguments:

The first argument to this intrinsic is a scalar start value for the reduction. The type of the start value matches the element-type of the vector input. The second argument must be a vector of floating-point values.

To ignore the start value, negative zero (`-0.0`) can be used, as it is the neutral value of floating point addition.

<a id="id914"></a>

##### Examples:

    %unord = call reassoc float @llvm.vector.reduce.fadd.v4f32(float -0.0, <4 x float> %input) ; relaxed reduction
    %ord = call float @llvm.vector.reduce.fadd.v4f32(float %start_value, <4 x float> %input) ; sequential reduction

<a id="llvm-vector-reduce-mul-intrinsic"></a>

<a id="int-vector-reduce-mul"></a>

#### ‘`llvm.vector.reduce.mul.*`’ Intrinsic

<a id="id915"></a>

##### Syntax:

    declare i32 @llvm.vector.reduce.mul.v4i32(<4 x i32> %a)
    declare i64 @llvm.vector.reduce.mul.v2i64(<2 x i64> %a)

<a id="id916"></a>

##### Overview:

The ‘`llvm.vector.reduce.mul.*`’ intrinsics do an integer `MUL` reduction of a vector, returning the result as a scalar. The return type matches the element-type of the vector input.

<a id="id917"></a>

##### Arguments:

The argument to this intrinsic must be a vector of integer values.

<a id="llvm-vector-reduce-fmul-intrinsic"></a>

<a id="int-vector-reduce-fmul"></a>

#### ‘`llvm.vector.reduce.fmul.*`’ Intrinsic

<a id="id918"></a>

##### Syntax:

    declare float @llvm.vector.reduce.fmul.v4f32(float %start_value, <4 x float> %a)
    declare double @llvm.vector.reduce.fmul.v2f64(double %start_value, <2 x double> %a)

<a id="id919"></a>

##### Overview:

The ‘`llvm.vector.reduce.fmul.*`’ intrinsics do a floating-point `MUL` reduction of a vector, returning the result as a scalar. The return type matches the element-type of the vector input.

If the intrinsic call has the ‘reassoc’ flag set, then the reduction will not preserve the associativity of an equivalent scalarized counterpart. Otherwise the reduction will be *sequential*, thus implying that the operation respects the associativity of a scalarized reduction. That is, the reduction begins with the start value and performs an fmul operation with consecutively increasing vector element indices. See the following pseudocode:

    float sequential_fmul(start_value, input_vector)
      result = start_value
      for i = 0 to length(input_vector)
        result = result * input_vector[i]
      return result

<a id="id920"></a>

##### Arguments:

The first argument to this intrinsic is a scalar start value for the reduction. The type of the start value matches the element-type of the vector input. The second argument must be a vector of floating-point values.

To ignore the start value, one (`1.0`) can be used, as it is the neutral value of floating point multiplication.

<a id="id921"></a>

##### Examples:

    %unord = call reassoc float @llvm.vector.reduce.fmul.v4f32(float 1.0, <4 x float> %input) ; relaxed reduction
    %ord = call float @llvm.vector.reduce.fmul.v4f32(float %start_value, <4 x float> %input) ; sequential reduction

<a id="llvm-vector-reduce-and-intrinsic"></a>

<a id="int-vector-reduce-and"></a>

#### ‘`llvm.vector.reduce.and.*`’ Intrinsic

<a id="id922"></a>

##### Syntax:

    declare i32 @llvm.vector.reduce.and.v4i32(<4 x i32> %a)

<a id="id923"></a>

##### Overview:

The ‘`llvm.vector.reduce.and.*`’ intrinsics do a bitwise `AND` reduction of a vector, returning the result as a scalar. The return type matches the element-type of the vector input.

<a id="id924"></a>

##### Arguments:

The argument to this intrinsic must be a vector of integer values.

<a id="llvm-vector-reduce-or-intrinsic"></a>

<a id="int-vector-reduce-or"></a>

#### ‘`llvm.vector.reduce.or.*`’ Intrinsic

<a id="id925"></a>

##### Syntax:

    declare i32 @llvm.vector.reduce.or.v4i32(<4 x i32> %a)

<a id="id926"></a>

##### Overview:

The ‘`llvm.vector.reduce.or.*`’ intrinsics do a bitwise `OR` reduction of a vector, returning the result as a scalar. The return type matches the element-type of the vector input.

<a id="id927"></a>

##### Arguments:

The argument to this intrinsic must be a vector of integer values.

<a id="llvm-vector-reduce-xor-intrinsic"></a>

<a id="int-vector-reduce-xor"></a>

#### ‘`llvm.vector.reduce.xor.*`’ Intrinsic

<a id="id928"></a>

##### Syntax:

    declare i32 @llvm.vector.reduce.xor.v4i32(<4 x i32> %a)

<a id="id929"></a>

##### Overview:

The ‘`llvm.vector.reduce.xor.*`’ intrinsics do a bitwise `XOR` reduction of a vector, returning the result as a scalar. The return type matches the element-type of the vector input.

<a id="id930"></a>

##### Arguments:

The argument to this intrinsic must be a vector of integer values.

<a id="llvm-vector-reduce-smax-intrinsic"></a>

<a id="int-vector-reduce-smax"></a>

#### ‘`llvm.vector.reduce.smax.*`’ Intrinsic

<a id="id931"></a>

##### Syntax:

    declare i32 @llvm.vector.reduce.smax.v4i32(<4 x i32> %a)

<a id="id932"></a>

##### Overview:

The ‘`llvm.vector.reduce.smax.*`’ intrinsics do a signed integer `MAX` reduction of a vector, returning the result as a scalar. The return type matches the element-type of the vector input.

<a id="id933"></a>

##### Arguments:

The argument to this intrinsic must be a vector of integer values.

<a id="llvm-vector-reduce-smin-intrinsic"></a>

<a id="int-vector-reduce-smin"></a>

#### ‘`llvm.vector.reduce.smin.*`’ Intrinsic

<a id="id934"></a>

##### Syntax:

    declare i32 @llvm.vector.reduce.smin.v4i32(<4 x i32> %a)

<a id="id935"></a>

##### Overview:

The ‘`llvm.vector.reduce.smin.*`’ intrinsics do a signed integer `MIN` reduction of a vector, returning the result as a scalar. The return type matches the element-type of the vector input.

<a id="id936"></a>

##### Arguments:

The argument to this intrinsic must be a vector of integer values.

<a id="llvm-vector-reduce-umax-intrinsic"></a>

<a id="int-vector-reduce-umax"></a>

#### ‘`llvm.vector.reduce.umax.*`’ Intrinsic

<a id="id937"></a>

##### Syntax:

    declare i32 @llvm.vector.reduce.umax.v4i32(<4 x i32> %a)

<a id="id938"></a>

##### Overview:

The ‘`llvm.vector.reduce.umax.*`’ intrinsics do an unsigned integer `MAX` reduction of a vector, returning the result as a scalar. The return type matches the element-type of the vector input.

<a id="id939"></a>

##### Arguments:

The argument to this intrinsic must be a vector of integer values.

<a id="llvm-vector-reduce-umin-intrinsic"></a>

<a id="int-vector-reduce-umin"></a>

#### ‘`llvm.vector.reduce.umin.*`’ Intrinsic

<a id="id940"></a>

##### Syntax:

    declare i32 @llvm.vector.reduce.umin.v4i32(<4 x i32> %a)

<a id="id941"></a>

##### Overview:

The ‘`llvm.vector.reduce.umin.*`’ intrinsics do an unsigned integer `MIN` reduction of a vector, returning the result as a scalar. The return type matches the element-type of the vector input.

<a id="id942"></a>

##### Arguments:

The argument to this intrinsic must be a vector of integer values.

<a id="llvm-vector-reduce-fmax-intrinsic"></a>

<a id="int-vector-reduce-fmax"></a>

#### ‘`llvm.vector.reduce.fmax.*`’ Intrinsic

<a id="id943"></a>

##### Syntax:

    declare float @llvm.vector.reduce.fmax.v4f32(<4 x float> %a)
    declare double @llvm.vector.reduce.fmax.v2f64(<2 x double> %a)

<a id="id944"></a>

##### Overview:

The ‘`llvm.vector.reduce.fmax.*`’ intrinsics do a floating-point `MAX` reduction of a vector, returning the result as a scalar. The return type matches the element-type of the vector input.

This instruction has the same comparison and `nsz` semantics as the ‘`llvm.maxnum.*`’ intrinsic.

The reduction is performed in a non-deterministic order. This is only observable if one of the inputs is a signaling NaN.

For example, if a reduction is performed over `<sNaN, 0.0, 1.0>`, then all of [NaN](high-level-structure.md#floatnan), `0.0` and `1.0` are possible results, depending on which order is picked.

<a id="id945"></a>

##### Arguments:

The argument to this intrinsic must be a vector of floating-point values.

<a id="llvm-vector-reduce-fmin-intrinsic"></a>

<a id="int-vector-reduce-fmin"></a>

#### ‘`llvm.vector.reduce.fmin.*`’ Intrinsic

<a id="id946"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare float @llvm.vector.reduce.fmin.v4f32(<4 x float> %a)
    declare double @llvm.vector.reduce.fmin.v2f64(<2 x double> %a)

<a id="id947"></a>

##### Overview:

The ‘`llvm.vector.reduce.fmin.*`’ intrinsics do a floating-point `MIN` reduction of a vector, returning the result as a scalar. The return type matches the element-type of the vector input.

This instruction has the same comparison and `nsz` semantics as the ‘`llvm.minnum.*`’ intrinsic.

The reduction is performed in a non-deterministic order. This is only observable if one of the inputs is a signaling NaN.

For example, if a reduction is performed over `<sNaN, 0.0, 1.0>`, then all of [NaN](high-level-structure.md#floatnan), `0.0` and `1.0` are possible results, depending on which order is picked.

<a id="id948"></a>

##### Arguments:

The argument to this intrinsic must be a vector of floating-point values.

<a id="llvm-vector-reduce-fmaximum-intrinsic"></a>

<a id="int-vector-reduce-fmaximum"></a>

#### ‘`llvm.vector.reduce.fmaximum.*`’ Intrinsic

<a id="id949"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare float @llvm.vector.reduce.fmaximum.v4f32(<4 x float> %a)
    declare double @llvm.vector.reduce.fmaximum.v2f64(<2 x double> %a)

<a id="id950"></a>

##### Overview:

The ‘`llvm.vector.reduce.fmaximum.*`’ intrinsics do a floating-point `MAX` reduction of a vector, returning the result as a scalar. The return type matches the element-type of the vector input.

This instruction has the same comparison semantics as the ‘`llvm.maximum.*`’ intrinsic. That is, this intrinsic propagates NaNs and +0.0 is considered greater than -0.0. If any element of the vector is a NaN, the result is NaN.

<a id="id951"></a>

##### Arguments:

The argument to this intrinsic must be a vector of floating-point values.

<a id="llvm-vector-reduce-fminimum-intrinsic"></a>

<a id="int-vector-reduce-fminimum"></a>

#### ‘`llvm.vector.reduce.fminimum.*`’ Intrinsic

<a id="id952"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare float @llvm.vector.reduce.fminimum.v4f32(<4 x float> %a)
    declare double @llvm.vector.reduce.fminimum.v2f64(<2 x double> %a)

<a id="id953"></a>

##### Overview:

The ‘`llvm.vector.reduce.fminimum.*`’ intrinsics do a floating-point `MIN` reduction of a vector, returning the result as a scalar. The return type matches the element-type of the vector input.

This instruction has the same comparison semantics as the ‘`llvm.minimum.*`’ intrinsic. That is, this intrinsic propagates NaNs and -0.0 is considered less than +0.0. If any element of the vector is a NaN, the result is NaN.

<a id="id954"></a>

##### Arguments:

The argument to this intrinsic must be a vector of floating-point values.

<a id="vector-partial-reduction-intrinsics"></a>

### Vector Partial Reduction Intrinsics

Partial reductions of vectors can be expressed using the intrinsics described in this section. Each one reduces the concatenation of the two vector arguments down to the number of elements of the result vector type.

Other than the reduction operator (e.g. add, fadd), the way in which the concatenated arguments is reduced is entirely unspecified. By their nature these intrinsics are not expected to be useful in isolation but can instead be used to implement the first phase of an overall reduction operation.

The typical use case is loop vectorization where reductions are split into an in-loop phase, where maintaining an unordered vector result is important for performance, and an out-of-loop phase is required to calculate the final scalar result.

By avoiding the introduction of new ordering constraints, these intrinsics enhance the ability to leverage a target’s accumulation instructions.

<a id="llvm-vector-partial-reduce-add-intrinsic"></a>

#### ‘`llvm.vector.partial.reduce.add.*`’ Intrinsic

<a id="id955"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <4 x i32> @llvm.vector.partial.reduce.add.v4i32.v4i32.v8i32(<4 x i32> %a, <8 x i32> %b)
    declare <4 x i32> @llvm.vector.partial.reduce.add.v4i32.v4i32.v16i32(<4 x i32> %a, <16 x i32> %b)
    declare <vscale x 4 x i32> @llvm.vector.partial.reduce.add.nxv4i32.nxv4i32.nxv8i32(<vscale x 4 x i32> %a, <vscale x 8 x i32> %b)
    declare <vscale x 4 x i32> @llvm.vector.partial.reduce.add.nxv4i32.nxv4i32.nxv16i32(<vscale x 4 x i32> %a, <vscale x 16 x i32> %b)

<a id="id956"></a>

##### Arguments:

The first argument is an integer vector with the same type as the result.

The second argument is a vector with a length that is a known integer multiple of the result’s type, while maintaining the same element type.

<a id="llvm-vector-partial-reduce-fadd-intrinsic"></a>

#### ‘`llvm.vector.partial.reduce.fadd.*`’ Intrinsic

<a id="id957"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <4 x f32> @llvm.vector.partial.reduce.fadd.v4f32.v8f32(<4 x f32> %a, <8 x f32> %b)
    declare <vscale x 4 x f32> @llvm.vector.partial.reduce.fadd.nxv4f32.nxv8f32(<vscale x 4 x f32> %a, <vscale x 8 x f32> %b)

<a id="id958"></a>

##### Arguments:

The first argument is a floating-point vector with the same type as the result.

The second argument is a vector with a length that is a known integer multiple of the result’s type, while maintaining the same element type.

<a id="id959"></a>

##### Semantics:

As the way in which the arguments to this floating-point intrinsic are reduced is unspecified, this intrinsic will assume floating-point reassociation and contraction can be leveraged to implement the reduction, which may result in variations to the results due to reordering or by lowering to different instructions (including combining multiple instructions into a single one).

<a id="vector-manipulation-intrinsics"></a>

### Vector Manipulation Intrinsics

<a id="llvm-vector-insert-intrinsic"></a>

#### ‘`llvm.vector.insert`’ Intrinsic

<a id="id960"></a>

##### Syntax:

This is an overloaded intrinsic.

    ; Insert fixed type into scalable type
    declare <vscale x 4 x float> @llvm.vector.insert.nxv4f32.v4f32(<vscale x 4 x float> %vec, <4 x float> %subvec, i64 <idx>)
    declare <vscale x 2 x double> @llvm.vector.insert.nxv2f64.v2f64(<vscale x 2 x double> %vec, <2 x double> %subvec, i64 <idx>)

    ; Insert scalable type into scalable type
    declare <vscale x 4 x float> @llvm.vector.insert.nxv4f64.nxv2f64(<vscale x 4 x float> %vec, <vscale x 2 x float> %subvec, i64 <idx>)

    ; Insert fixed type into fixed type
    declare <4 x double> @llvm.vector.insert.v4f64.v2f64(<4 x double> %vec, <2 x double> %subvec, i64 <idx>)

<a id="id961"></a>

##### Overview:

The ‘`llvm.vector.insert.*`’ intrinsics insert a vector into another vector starting from a given index. The return type matches the type of the vector we insert into. Conceptually, this can be used to build a scalable vector out of non-scalable vectors, however this intrinsic can also be used on purely fixed types.

Scalable vectors can only be inserted into other scalable vectors.

<a id="id962"></a>

##### Arguments:

The `vec` is the vector which `subvec` will be inserted into. The `subvec` is the vector that will be inserted.

`idx` represents the starting element number at which `subvec` will be inserted. `idx` must be a constant multiple of `subvec`’s known minimum vector length. If `subvec` is a scalable vector, `idx` is first scaled by the runtime scaling factor of `subvec`. The elements of `vec` starting at `idx` are overwritten with `subvec`. Elements `idx` through (`idx` + num_elements(`subvec`) - 1) must be valid `vec` indices. If this condition cannot be determined statically but is false at runtime, then the result vector is a [poison value](constants.md#poisonvalues).

<a id="llvm-vector-extract-intrinsic"></a>

#### ‘`llvm.vector.extract`’ Intrinsic

<a id="id963"></a>

##### Syntax:

This is an overloaded intrinsic.

    ; Extract fixed type from scalable type
    declare <4 x float> @llvm.vector.extract.v4f32.nxv4f32(<vscale x 4 x float> %vec, i64 <idx>)
    declare <2 x double> @llvm.vector.extract.v2f64.nxv2f64(<vscale x 2 x double> %vec, i64 <idx>)

    ; Extract scalable type from scalable type
    declare <vscale x 2 x float> @llvm.vector.extract.nxv2f32.nxv4f32(<vscale x 4 x float> %vec, i64 <idx>)

    ; Extract fixed type from fixed type
    declare <2 x double> @llvm.vector.extract.v2f64.v4f64(<4 x double> %vec, i64 <idx>)

<a id="id964"></a>

##### Overview:

The ‘`llvm.vector.extract.*`’ intrinsics extract a vector from within another vector starting from a given index. The return type must be explicitly specified. Conceptually, this can be used to decompose a scalable vector into non-scalable parts, however this intrinsic can also be used on purely fixed types.

Scalable vectors can only be extracted from other scalable vectors.

<a id="id965"></a>

##### Arguments:

The `vec` is the vector from which we will extract a subvector.

The `idx` specifies the starting element number within `vec` from which a subvector is extracted. `idx` must be a constant multiple of the known-minimum vector length of the result type. If the result type is a scalable vector, `idx` is first scaled by the result type’s runtime scaling factor. Elements `idx` through (`idx` + num_elements(result_type) - 1) must be valid vector indices. If this condition cannot be determined statically but is false at runtime, then the result vector is a [poison value](constants.md#poisonvalues). The `idx` parameter must be a vector index constant type (for most targets this will be an integer pointer type).

<a id="llvm-vector-reverse-intrinsic"></a>

#### ‘`llvm.vector.reverse`’ Intrinsic

<a id="id966"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <2 x i8> @llvm.vector.reverse.v2i8(<2 x i8> %a)
    declare <vscale x 4 x i32> @llvm.vector.reverse.nxv4i32(<vscale x 4 x i32> %a)

<a id="id967"></a>

##### Overview:

The ‘`llvm.vector.reverse.*`’ intrinsics reverse a vector. The intrinsic takes a single vector and returns a vector of matching type but with the original lane order reversed. These intrinsics work for both fixed and scalable vectors. While this intrinsic supports all vector types the recommended way to express this operation for fixed-width vectors is still to use a shufflevector, as that may allow for more optimization opportunities.

<a id="id968"></a>

##### Arguments:

The argument to this intrinsic must be a vector.

<a id="llvm-vector-deinterleave2-3-4-5-6-7-8-intrinsic"></a>

#### ‘`llvm.vector.deinterleave2/3/4/5/6/7/8`’ Intrinsic

<a id="id969"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare {<2 x double>, <2 x double>} @llvm.vector.deinterleave2.v4f64(<4 x double> %vec1)
    declare {<vscale x 4 x i32>, <vscale x 4 x i32>}  @llvm.vector.deinterleave2.nxv8i32(<vscale x 8 x i32> %vec1)
    declare {<vscale x 2 x i8>, <vscale x 2 x i8>, <vscale x 2 x i8>} @llvm.vector.deinterleave3.nxv6i8(<vscale x 6 x i8> %vec1)
    declare {<2 x i32>, <2 x i32>, <2 x i32>, <2 x i32>, <2 x i32>} @llvm.vector.deinterleave5.v10i32(<10 x i32> %vec1)
    declare {<2 x i32>, <2 x i32>, <2 x i32>, <2 x i32>, <2 x i32>, <2 x i32>, <2 x i32>} @llvm.vector.deinterleave7.v14i32(<14 x i32> %vec1)

<a id="id970"></a>

##### Overview:

The ‘`llvm.vector.deinterleave2/3/4/5/6/7/8`’ intrinsics deinterleave adjacent lanes into 2 through to 8 separate vectors, respectively, and return them as the result.

This intrinsic works for both fixed and scalable vectors. While this intrinsic supports all vector types the recommended way to express this operation for factor of 2 on fixed-width vectors is still to use a shufflevector, as that may allow for more optimization opportunities.

For example:

    {<2 x i64>, <2 x i64>} llvm.vector.deinterleave2.v4i64(<4 x i64> <i64 0, i64 1, i64 2, i64 3>); ==> {<2 x i64> <i64 0, i64 2>, <2 x i64> <i64 1, i64 3>}
    {<2 x i32>, <2 x i32>, <2 x i32>} llvm.vector.deinterleave3.v6i32(<6 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5>)
      ; ==> {<2 x i32> <i32 0, i32 3>, <2 x i32> <i32 1, i32 4>, <2 x i32> <i32 2, i32 5>}

<a id="id971"></a>

##### Arguments:

The argument is a vector whose type corresponds to the logical concatenation of the aggregated result types.

<a id="llvm-vector-interleave2-3-4-5-6-7-8-intrinsic"></a>

#### ‘`llvm.vector.interleave2/3/4/5/6/7/8`’ Intrinsic

<a id="id972"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <4 x double> @llvm.vector.interleave2.v4f64(<2 x double> %vec1, <2 x double> %vec2)
    declare <vscale x 8 x i32> @llvm.vector.interleave2.nxv8i32(<vscale x 4 x i32> %vec1, <vscale x 4 x i32> %vec2)
    declare <vscale x 6 x i8> @llvm.vector.interleave3.nxv6i8(<vscale x 2 x i8> %vec0, <vscale x 2 x i8> %vec1, <vscale x 2 x i8> %vec2)
    declare <10 x i32> @llvm.vector.interleave5.v10i32(<2 x i32> %vec0, <2 x i32> %vec1, <2 x i32> %vec2, <2 x i32> %vec3, <2 x i32> %vec4)
    declare <14 x i32> @llvm.vector.interleave7.v14i32(<2 x i32> %vec0, <2 x i32> %vec1, <2 x i32> %vec2, <2 x i32> %vec3, <2 x i32> %vec4, <2 x i32> %vec5, <2 x i32> %vec6)

<a id="id973"></a>

##### Overview:

The ‘`llvm.vector.interleave2/3/4/5/6/7/8`’ intrinsic constructs a vector by interleaving all the input vectors.

This intrinsic works for both fixed and scalable vectors. While this intrinsic supports all vector types the recommended way to express this operation for factor of 2 on fixed-width vectors is still to use a shufflevector, as that may allow for more optimization opportunities.

For example:

    <4 x i64> llvm.vector.interleave2.v4i64(<2 x i64> <i64 0, i64 2>, <2 x i64> <i64 1, i64 3>); ==> <4 x i64> <i64 0, i64 1, i64 2, i64 3>
    <6 x i32> llvm.vector.interleave3.v6i32(<2 x i32> <i32 0, i32 3>, <2 x i32> <i32 1, i32 4>, <2 x i32> <i32 2, i32 5>)
     ; ==> <6 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5>

<a id="id974"></a>

##### Arguments:

All arguments must be vectors of the same type whereby their logical concatenation matches the result type.

<a id="llvm-vector-splice-left-intrinsic"></a>

#### ‘`llvm.vector.splice.left`’ Intrinsic

<a id="id975"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <2 x double> @llvm.vector.splice.left.v2f64(<2 x double> %vec1, <2 x double> %vec2, i32 %offset)
    declare <vscale x 4 x i32> @llvm.vector.splice.left.nxv4i32(<vscale x 4 x i32> %vec1, <vscale x 4 x i32> %vec2, i32 %offset)

<a id="id976"></a>

##### Overview:

The ‘`llvm.vector.splice.left.*`’ intrinsics construct a vector by concatenating two vectors together, shifting the elements left by `offset`, and extracting the lower half.

These intrinsics work for both fixed and scalable vectors. While this intrinsic supports all vector types the recommended way to express this operation for fixed-width vectors with an immediate offset is still to use a shufflevector, as that may allow for more optimization opportunities.

For example:

    llvm.vector.splice.left(<A,B,C,D>, <E,F,G,H>, 1);
                        ==> <A,B,C,D,E,F,G,H>
                        ==> <B,C,D,E,F,G,H,_>
                        ==> <B,C,D,E>

<a id="id977"></a>

##### Arguments:

The first two operands are vectors with the same type. `offset` is an unsigned scalar i32 that determines how many elements to shift left by.

<a id="id978"></a>

##### Semantics:

For a vector type with a runtime length of N, if `offset` \> N then the result is a [poison value](constants.md#poisonvalues).

<a id="llvm-vector-splice-right-intrinsic"></a>

#### ‘`llvm.vector.splice.right`’ Intrinsic

<a id="id979"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <2 x double> @llvm.vector.splice.right.v2f64(<2 x double> %vec1, <2 x double> %vec2, i32 %offset)
    declare <vscale x 4 x i32> @llvm.vector.splice.right.nxv4i32(<vscale x 4 x i32> %vec1, <vscale x 4 x i32> %vec2, i32 %offset)

<a id="id980"></a>

##### Overview:

The ‘`llvm.vector.splice.right.*`’ intrinsics construct a vector by concatenating two vectors together, shifting the elements right by `offset`, and extracting the upper half.

These intrinsics work for both fixed and scalable vectors. While this intrinsic supports all vector types the recommended way to express this operation for fixed-width vectors with an immediate offset is still to use a shufflevector, as that may allow for more optimization opportunities.

For example:

    llvm.vector.splice.right(<A,B,C,D>, <E,F,G,H>, 1);
                         ==> <A,B,C,D,E,F,G,H>
                         ==> <_,A,B,C,D,E,F,G>
                         ==>         <D,E,F,G>

<a id="id981"></a>

##### Arguments:

The first two operands are vectors with the same type. `offset` is an unsigned scalar i32 that determines how many elements to shift right by.

<a id="id982"></a>

##### Semantics:

For a vector type with a runtime length of N, if `offset` \> N then the result is a [poison value](constants.md#poisonvalues).

<a id="llvm-stepvector-intrinsic"></a>

#### ‘`llvm.stepvector`’ Intrinsic

This is an overloaded intrinsic. You can use `llvm.stepvector` to generate a vector whose lane values comprise the linear sequence \<0, 1, 2, …\>. It is primarily intended for scalable vectors.

    declare <vscale x 4 x i32> @llvm.stepvector.nxv4i32()
    declare <vscale x 8 x i16> @llvm.stepvector.nxv8i16()

The ‘`llvm.stepvector`’ intrinsics are used to create vectors of integers whose elements contain a linear sequence of values starting from 0 with a step of 1. This intrinsic can only be used for vectors with integer elements that are at least 8 bits in size. If the sequence value exceeds the allowed limit for the element type then the result for that lane is truncated.

These intrinsics work for both fixed and scalable vectors. While this intrinsic supports all vector types, the recommended way to express this operation for fixed-width vectors is still to generate a constant vector instead.

<a id="id983"></a>

##### Arguments:

None.

<a id="vector-mask-intrinsics"></a>

### Vector Mask Intrinsics

<a id="llvm-get-active-lane-mask-intrinsics"></a>

<a id="int-get-active-lane-mask"></a>

#### ‘`llvm.get.active.lane.mask.*`’ Intrinsics

<a id="id984"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <4 x i1> @llvm.get.active.lane.mask.v4i1.i32(i32 %base, i32 %n)
    declare <8 x i1> @llvm.get.active.lane.mask.v8i1.i64(i64 %base, i64 %n)
    declare <16 x i1> @llvm.get.active.lane.mask.v16i1.i64(i64 %base, i64 %n)
    declare <vscale x 16 x i1> @llvm.get.active.lane.mask.nxv16i1.i64(i64 %base, i64 %n)

<a id="id985"></a>

##### Overview:

Create a mask representing active and inactive vector lanes.

<a id="id986"></a>

##### Arguments:

Both arguments have the same scalar integer type. The result is a vector with the i1 element type.

<a id="id987"></a>

##### Semantics:

The ‘`llvm.get.active.lane.mask.*`’ intrinsics are semantically equivalent to:

    %m[i] = icmp ult (%base + i), %n

where `%m` is a vector (mask) of active/inactive lanes with its elements indexed by `i`, and `%base`, `%n` are the two arguments to `llvm.get.active.lane.mask.*`, `%icmp` is an integer compare and `ult` the unsigned less-than comparison operator. Overflow cannot occur in `(%base + i)` and its comparison against `%n` as it is performed in integer numbers and not in machine numbers. The above is equivalent to:

    %m = @llvm.get.active.lane.mask(%base, %n)

This can, for example, be emitted by the loop vectorizer in which case `%base` is the first element of the vector induction variable (VIV) and `%n` is the loop tripcount. Thus, these intrinsics perform an element-wise less than comparison of VIV with the loop tripcount, producing a mask of true/false values representing active/inactive vector lanes, except if the VIV overflows in which case they return false in the lanes where the VIV overflows. The arguments are scalar types to accommodate scalable vector types, for which it is unknown what the type of the step vector needs to be that enumerate its lanes without overflow.

This mask `%m` can e.g., be used in masked load/store instructions. These intrinsics provide a hint to the backend. I.e., for a vector loop, the back-edge taken count of the original scalar loop is explicit as the second argument.

<a id="id988"></a>

##### Examples:

    %active.lane.mask = call <4 x i1> @llvm.get.active.lane.mask.v4i1.i64(i64 %elem0, i64 429)
    %wide.masked.load = call <4 x i32> @llvm.masked.load.v4i32.p0v4i32(ptr align 4 %3, <4 x i1> %active.lane.mask, <4 x i32> poison)

<a id="llvm-loop-dependence-war-mask-intrinsics"></a>

<a id="int-loop-dependence-war-mask"></a>

#### ‘`llvm.loop.dependence.war.mask.*`’ Intrinsics

<a id="id989"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <4 x i1> @llvm.loop.dependence.war.mask.v4i1.i64(i64 %addrA, i64 %addrB, i64 immarg %elementSize)
    declare <8 x i1> @llvm.loop.dependence.war.mask.v8i1.i32(i32 %addrA, i32 %addrB, i32 immarg %elementSize)
    declare <16 x i1> @llvm.loop.dependence.war.mask.v16i1.i64(i64 %addrA, i64 %addrB, i64 immarg %elementSize)
    declare <vscale x 16 x i1> @llvm.loop.dependence.war.mask.nxv16i1.i64(i64 %addrA, i64 %addrB, i64 immarg %elementSize)

<a id="id990"></a>

##### Overview:

Given a vector load from address `%addrA` followed by a vector store to address `%addrB`, this instruction generates a mask where an active lane indicates that the write-after-read sequence can be performed safely for that lane, without the danger of a write-after-read hazard occurring.

A write-after-read hazard occurs when a write-after-read sequence for a given lane in a vector ends up being executed as a read-after-write sequence due to the aliasing of pointers.

<a id="id991"></a>

##### Arguments:

The first two arguments are integers and the last argument is an immediate. The result is a vector with the i1 element type.

<a id="id992"></a>

##### Semantics:

`%elementSize` is the size of the accessed elements in bytes. The intrinsic returns `poison` if the distance between `%addrA` and `%addrB` is smaller than `VF * %elementsize` and either `%addrA + VF * %elementSize` or `%addrB + VF * %elementSize` wrap.

The element of the result mask is active when loading from `%addrA` then storing to `%addrB` is safe and doesn’t result in a write-after-read hazard, meaning that:

- (addrB - addrA) \<= 0 (guarantees that all lanes are loaded before any stores), or

- elementSize \* lane \< (addrB - addrA) (guarantees that this lane is loaded before the store to the same address)

<a id="id993"></a>

##### Examples:

    %addrA = ptrtoaddr ptr %ptrA to i64
    %addrB = ptrtoaddr ptr %ptrB to i64
    %loop.dependence.mask = call <4 x i1> @llvm.loop.dependence.war.mask.v4i1.i64(i64 %addrA, i64 %addrB, i64 4)
    %vecA = call <4 x i32> @llvm.masked.load.v4i32.p0(ptr align 4 %ptrA, <4 x i1> %loop.dependence.mask, <4 x i32> poison)
    [...]
    call @llvm.masked.store.v4i32.p0(<4 x i32> %vecA, ptr align 4 %ptrB, <4 x i1> %loop.dependence.mask)

    ; For the above example, consider the following cases:
    ;
    ; 1. addrA >= addrB
    ;
    ;   load =      <0,1,2,3>     ; uint32_t load = array[i+2];
    ;  store =  <0,1,2,3>         ; array[i] = store;
    ;
    ; This results in an all-true mask, as the load always occurs before the
    ; store, so it does not depend on any values to be stored.
    ;
    ; 2. addrB - addrA = 2 * elementSize:
    ;
    ;   load =  <0,1,2,3>         ; uint32_t load = array[i];
    ;  store =      <0,1,2,3>     ; array[i+2] = store;
    ;
    ; This results in a mask with the first two lanes active. This is because
    ; we can only read two lanes before we would read values that have yet to
    ; be written.
    ;
    ; 3. addrB - addrA = 4 * elementSize
    ;
    ;   load =  <0,1,2,3>         ; uint32_t load = array[i];
    ;  store =          <0,1,2,3> ; array[i+4] = store;
    ;
    ; This results in an all-true mask, as the store is a full vector ahead
    ; of the load, so all values will be written before any lane is read.

<a id="llvm-loop-dependence-raw-mask-intrinsics"></a>

<a id="int-loop-dependence-raw-mask"></a>

#### ‘`llvm.loop.dependence.raw.mask.*`’ Intrinsics

<a id="id994"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <4 x i1> @llvm.loop.dependence.raw.mask.v4i1.i64(i64 %addrA, i64 %addrB, i64 immarg %elementSize)
    declare <8 x i1> @llvm.loop.dependence.raw.mask.v8i1.i32(i32 %addrA, i32 %addrB, i32 immarg %elementSize)
    declare <16 x i1> @llvm.loop.dependence.raw.mask.v16i1.i64(i64 %addrA, i64 %addrB, i64 immarg %elementSize)
    declare <vscale x 16 x i1> @llvm.loop.dependence.raw.mask.nxv16i1.i64(i64 %addrA, i64 %addrB, i64 immarg %elementSize)

<a id="id995"></a>

##### Overview:

Given a vector store to address `%addrA` followed by a vector load from address `%addrB`, this instruction generates a mask where an active lane indicates that the read-after-write sequence can be performed safely for that lane, without a read-after-write hazard or a store-to-load forwarding hazard being introduced.

A read-after-write hazard occurs when a read-after-write sequence for a given lane in a vector ends up being executed as a write-after-read sequence due to the aliasing of pointers.

A store-to-load forwarding hazard occurs when a vector store writes to an address that partially overlaps with the address of a subsequent vector load, meaning that the vector load can’t be performed until the vector store is complete.

<a id="id996"></a>

##### Arguments:

The first two arguments are integers and the last argument is an immediate. The result is a vector with the i1 element type.

<a id="id997"></a>

##### Semantics:

`%elementSize` is the size of the accessed elements in bytes. The intrinsic returns `poison` if the distance between `%addrA` and `%addrB` is smaller than `VF * %elementsize` and either `%addrA + VF * %elementSize` or `%addrB + VF * %elementSize` wrap.

The element of the result mask is active when storing to `%addrA` then loading from `%addrB` is safe and doesn’t result in aliasing, meaning that:

- elementSize \* lane \< abs(addrB - addrA) (guarantees that the store of this lane occurs before loading from this address), or

- addrA == addrB (doesn’t introduce any new hazards that weren’t in the scalar code)

<a id="id998"></a>

##### Examples:

    %addrA = ptrtoaddr ptr %ptrA to i64
    %addrB = ptrtoaddr ptr %ptrB to i64
    %loop.dependence.mask = call <4 x i1> @llvm.loop.dependence.raw.mask.v4i1.i64(i64 %addrA, i64 %addrB, i64 4)
    call @llvm.masked.store.v4i32.p0(<4 x i32> %vecA, ptr align 4 %ptrA, <4 x i1> %loop.dependence.mask)
    [...]
    %vecB = call <4 x i32> @llvm.masked.load.v4i32.p0(ptr align 4 %ptrB, <4 x i1> %loop.dependence.mask, <4 x i32> poison)

    ; For the above example, consider the following cases:
    ;
    ; 1. addrA == addrB
    ;
    ;  store = <0,1,2,3>       ; array[i] = store;
    ;   load = <0,1,2,3>       ; uint32_t load = array[i];
    ;
    ; This results in a all-true mask. There is no conflict.
    ;
    ; 2. addrB - addrA = 2 * elementSize
    ;
    ;  store =  <0,1,2,3>      ; array[i] = store;
    ;   load =      <0,1,2,3>  ; uint32_t load = array[i+2];
    ;
    ; This results in a mask with the first two lanes active. In this case,
    ; only two lanes can be written without overwriting values yet to be read.
    ;
    ; 3. addrB - addrA = -2 * elementSize
    ;
    ;  store =      <0,1,2,3>  ; array[i+2] = store;
    ;   load =  <0,1,2,3>      ; uint32_t load = array[i];
    ;
    ; This also results in a mask with the first two lanes active. This is
    ; because if any more lanes were active the load would be dependent on the
    ; completion of the store.

<a id="experimental-vector-intrinsics"></a>

### Experimental Vector Intrinsics

<a id="llvm-experimental-cttz-elts-intrinsic"></a>

#### ‘`llvm.experimental.cttz.elts`’ Intrinsic

<a id="id999"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.experimental.cttz.elts` on any vector of integer elements, both fixed width and scalable.

    declare i8 @llvm.experimental.cttz.elts.i8.v8i1(<8 x i1> <src>, i1 <is_zero_poison>)

<a id="id1000"></a>

##### Overview:

The ‘`llvm.experimental.cttz.elts`’ intrinsic counts the number of trailing zero elements of a vector.

<a id="id1001"></a>

##### Arguments:

The first argument is the vector to be counted. This argument must be a vector with integer element type. The return type must also be an integer type which is wide enough to hold the maximum number of elements of the source vector. The result is a [poison value](constants.md#poisonvalues) if the return type is not wide enough for the number of elements in the input vector.

The second argument is a constant flag that indicates whether the intrinsic returns a valid result if the first argument is all zero. If the first argument is all zero and the second argument is true, the result is poison.

<a id="id1002"></a>

##### Semantics:

The ‘`llvm.experimental.cttz.elts`’ intrinsic counts the trailing (least significant) zero elements in a vector. If `src == 0` the result is the number of elements in the input vector.

<a id="llvm-experimental-get-vector-length-intrinsic"></a>

#### ‘`llvm.experimental.get.vector.length`’ Intrinsic

<a id="id1003"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare i32 @llvm.experimental.get.vector.length.i32(i32 %cnt, i32 immarg %vf, i1 immarg %scalable)
    declare i32 @llvm.experimental.get.vector.length.i64(i64 %cnt, i32 immarg %vf, i1 immarg %scalable)

<a id="id1004"></a>

##### Overview:

The ‘`llvm.experimental.get.vector.length.*`’ intrinsics take a number of elements to process and returns how many of the elements can be processed with the requested vectorization factor.

<a id="id1005"></a>

##### Arguments:

The first argument is an unsigned value of any scalar integer type and specifies the total number of elements to be processed. The second argument is an i32 immediate for the vectorization factor. The third argument indicates if the vectorization factor should be multiplied by vscale.

<a id="id1006"></a>

##### Semantics:

Returns a non-negative i32 value (explicit vector length) that is unknown at compile time and depends on the hardware specification. If the result value does not fit in the result type, then the result is a [poison value](constants.md#poisonvalues).

This intrinsic is intended to be used by loop vectorization with VP intrinsics in order to get the number of elements to process on each loop iteration. The result should be used to decrease the count for the next iteration until the count reaches zero.

Let `%max_lanes` be the number of lanes in the type described by `%vf` and `%scalable`, here are the constraints on the returned value:

- If `%cnt` equals to 0, returns 0.

- The returned value is always less than or equal to `%max_lanes`.

- The returned value is always greater than or equal to `ceil(%cnt / ceil(%cnt / %max_lanes))`, if `%cnt` is non-zero.

- The returned values are monotonically non-increasing in each loop iteration. That is, the returned value of an iteration is at least as large as that of any later iteration.

Note that it has the following implications:

- For a loop that uses this intrinsic, the number of iterations is equal to `ceil(%C / %max_lanes)` where `%C` is the initial `%cnt` value.

- If `%cnt` is non-zero, the return value is non-zero as well.

- If `%cnt` is less than or equal to `%max_lanes`, the return value is equal to `%cnt`.

<a id="llvm-experimental-vector-histogram-intrinsic"></a>

#### ‘`llvm.experimental.vector.histogram.*`’ Intrinsic

These intrinsics are overloaded.

These intrinsics represent histogram-like operations; that is, updating values in memory that may not be contiguous, and where multiple elements within a single vector may be updating the same value in memory.

The update operation must be specified as part of the intrinsic name. For a simple histogram like the following the `add` operation would be used.

    void simple_histogram(int *restrict buckets, unsigned *indices, int N, int inc) {
      for (int i = 0; i < N; ++i)
        buckets[indices[i]] += inc;
    }

More update operation types may be added in the future.

    declare void @llvm.experimental.vector.histogram.add.v8p0.i32(<8 x ptr> %ptrs, i32 %inc, <8 x i1> %mask)
    declare void @llvm.experimental.vector.histogram.add.nxv2p0.i64(<vscale x 2 x ptr> %ptrs, i64 %inc, <vscale x 2 x i1> %mask)
    declare void @llvm.experimental.vector.histogram.uadd.sat.v8p0.i32(<8 x ptr> %ptrs, i32 %inc, <8 x i1> %mask)
    declare void @llvm.experimental.vector.histogram.umax.v8p0.i32(<8 x ptr> %ptrs, i32 %val, <8 x i1> %mask)
    declare void @llvm.experimental.vector.histogram.umin.v8p0.i32(<8 x ptr> %ptrs, i32 %val, <8 x i1> %mask)

<a id="id1007"></a>

##### Arguments:

The first argument is a vector of pointers to the memory locations to be updated. The second argument is a scalar used to update the value from memory; it must match the type of value to be updated. The final argument is a mask value to exclude locations from being modified.

<a id="id1008"></a>

##### Semantics:

The ‘`llvm.experimental.vector.histogram.*`’ intrinsics are used to perform updates on potentially overlapping values in memory. The intrinsics represent the following sequence of operations:

1.  Gather load from the `ptrs` operand, with element type matching that of the `inc` operand.

2.  Update of the values loaded from memory. In the case of the `add` update operation, this means:

    1.  Perform a cross-vector histogram operation on the `ptrs` operand.

    2.  Multiply the result by the `inc` operand.

    3.  Add the result to the values loaded from memory

3.  Scatter the result of the update operation to the memory locations from the `ptrs` operand.

The `mask` operand will apply to at least the gather and scatter operations.

<a id="llvm-experimental-vector-extract-last-active-intrinsic"></a>

#### ‘`llvm.experimental.vector.extract.last.active`’ Intrinsic

This is an overloaded intrinsic.

    declare i32 @llvm.experimental.vector.extract.last.active.v4i32(<4 x i32> %data, <4 x i1> %mask, i32 %passthru)
    declare i16 @llvm.experimental.vector.extract.last.active.nxv8i16(<vscale x 8 x i16> %data, <vscale x 8 x i1> %mask, i16 %passthru)

<a id="id1009"></a>

##### Arguments:

The first argument is the data vector to extract a lane from. The second is a mask vector controlling the extraction. The third argument is a passthru value.

The two input vectors must have the same number of elements, and the type of the passthru value must match that of the elements of the data vector.

<a id="id1010"></a>

##### Semantics:

The ‘`llvm.experimental.vector.extract.last.active`’ intrinsic will extract an element from the data vector at the index matching the highest active lane of the mask vector. If no mask lanes are active then the passthru value is returned instead.

<a id="llvm-experimental-vector-compress-intrinsics"></a>

<a id="int-vector-compress"></a>

#### ‘`llvm.experimental.vector.compress.*`’ Intrinsics

LLVM provides an intrinsic for compressing data within a vector based on a selection mask. Semantically, this is similar to [llvm.masked.compressstore](#int-compressstore) but with weaker assumptions and without storing the results to memory, i.e., the data remains in the vector.

<a id="id1011"></a>

##### Syntax:

This is an overloaded intrinsic. A number of scalar values of integer, floating point or pointer data type are collected from an input vector and placed adjacently within the result vector. A mask defines which elements to collect from the vector. The remaining lanes are filled with values from `passthru`.

    declare <8 x i32> @llvm.experimental.vector.compress.v8i32(<8 x i32> <value>, <8 x i1> <mask>, <8 x i32> <passthru>)
    declare <16 x float> @llvm.experimental.vector.compress.v16f32(<16 x float> <value>, <16 x i1> <mask>, <16 x float> undef)

<a id="id1012"></a>

##### Overview:

Selects elements from input vector `value` according to the `mask`. All selected elements are written into adjacent lanes in the result vector, from lower to higher. The mask holds an entry for each vector lane, and is used to select elements to be kept. If a `passthru` vector is given, all remaining lanes are filled with the corresponding lane’s value from `passthru`. The main difference to [llvm.masked.compressstore](#int-compressstore) is that the we do not need to guard against memory access for unselected lanes. This allows for branchless code and better optimization for all targets that do not support or have inefficient instructions of the explicit semantics of [llvm.masked.compressstore](#int-compressstore) but still have some form of compress operations. The result vector can be written with a similar effect, as all the selected values are at the lower positions of the vector, but without requiring branches to avoid writes where the mask is `false`.

<a id="id1013"></a>

##### Arguments:

The first operand is the input vector, from which elements are selected. The second operand is the mask, a vector of boolean values. The third operand is the passthru vector, from which elements are filled into remaining lanes. The mask and the input vector must have the same number of vector elements. The input and passthru vectors must have the same type.

<a id="id1014"></a>

##### Semantics:

The `llvm.experimental.vector.compress` intrinsic compresses data within a vector. It collects elements from possibly non-adjacent lanes of a vector and places them contiguously in the result vector based on a selection mask, filling the remaining lanes with values from `passthru`. This intrinsic performs the logic of the following C++ example. All values in `out` after the last selected one are undefined if `passthru` is undefined. If all entries in the `mask` are 0, the `out` vector is `passthru`. If any element of the mask is poison, all elements of the result are poison. Otherwise, if any element of the mask is undef, all elements of the result are undef. If `passthru` is undefined, the number of valid lanes is equal to the number of `true` entries in the mask, i.e., all lanes \>= number-of-selected-values are undefined.

    // Consecutively place selected values in a vector.
    using VecT __attribute__((vector_size(N))) = int;
    VecT compress(VecT vec, VecT mask, VecT passthru) {
      VecT out;
      int idx = 0;
      for (int i = 0; i < N / sizeof(int); ++i) {
        out[idx] = vec[i];
        idx += static_cast<bool>(mask[i]);
      }
      for (; idx < N / sizeof(int); ++idx) {
        out[idx] = passthru[idx];
      }
      return out;
    }

<a id="llvm-experimental-vector-match-intrinsic"></a>

#### ‘`llvm.experimental.vector.match.*`’ Intrinsic

<a id="id1015"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <<n> x i1> @llvm.experimental.vector.match(<<n> x <ty>> %op1, <<m> x <ty>> %op2, <<n> x i1> %mask)
    declare <vscale x <n> x i1> @llvm.experimental.vector.match(<vscale x <n> x <ty>> %op1, <<m> x <ty>> %op2, <vscale x <n> x i1> %mask)

<a id="id1016"></a>

##### Overview:

Find active elements of the first argument matching any elements of the second.

<a id="id1017"></a>

##### Arguments:

The first argument is the search vector, the second argument the vector of elements we are searching for (i.e., for which we consider a match successful), and the third argument is a mask that controls which elements of the first argument are active. The first two arguments must be vectors of matching integer element types. The first and third arguments and the result type must have matching element counts (fixed or scalable). The second argument must be a fixed vector, but its length may be different from the remaining arguments.

<a id="id1018"></a>

##### Semantics:

The ‘`llvm.experimental.vector.match`’ intrinsic compares each active element in the first argument against the elements of the second argument, placing `1` in the corresponding element of the output vector if any equality comparison is successful, and `0` otherwise. Inactive elements in the mask are set to `0` in the output.

<a id="matrix-intrinsics"></a>

### Matrix Intrinsics

Operations on matrixes requiring shape information (like number of rows/columns or the memory layout) can be expressed using the matrix intrinsics. These intrinsics require matrix dimensions to be passed as immediate arguments, and matrixes are passed and returned as vectors. This means that for a `R` x `C` matrix, element `i` of column `j` is at index `j * R + i` in the corresponding vector, with indices starting at 0. Currently column-major layout is assumed. The intrinsics support both integer and floating point matrixes.

<a id="llvm-matrix-transpose-intrinsic"></a>

#### ‘`llvm.matrix.transpose.*`’ Intrinsic

<a id="id1019"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare vectorty @llvm.matrix.transpose.*(vectorty %In, i32 <Rows>, i32 <Cols>)

<a id="id1020"></a>

##### Overview:

The ‘`llvm.matrix.transpose.*`’ intrinsics treat `%In` as a `<Rows> x <Cols>` matrix and return the transposed matrix in the result vector.

<a id="id1021"></a>

##### Arguments:

The first argument `%In` is a vector that corresponds to a `<Rows> x <Cols>` matrix. Thus, arguments `<Rows>` and `<Cols>` correspond to the number of rows and columns, respectively, and must be positive, constant integers. The returned vector must have `<Rows> * <Cols>` elements, and have the same float or integer element type as `%In`.

<a id="llvm-matrix-multiply-intrinsic"></a>

#### ‘`llvm.matrix.multiply.*`’ Intrinsic

<a id="id1022"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare vectorty @llvm.matrix.multiply.*(vectorty %A, vectorty %B, i32 <OuterRows>, i32 <Inner>, i32 <OuterColumns>)

<a id="id1023"></a>

##### Overview:

The ‘`llvm.matrix.multiply.*`’ intrinsics treat `%A` as a `<OuterRows> x <Inner>` matrix, `%B` as a `<Inner> x <OuterColumns>` matrix, and multiplies them. The result matrix is returned in the result vector.

<a id="id1024"></a>

##### Arguments:

The first vector argument `%A` corresponds to a matrix with `<OuterRows> * <Inner>` elements, and the second argument `%B` to a matrix with `<Inner> * <OuterColumns>` elements. Arguments `<OuterRows>`, `<Inner>` and `<OuterColumns>` must be positive, constant integers. The returned vector must have `<OuterRows> * <OuterColumns>` elements. Vectors `%A`, `%B`, and the returned vector all have the same float or integer element type.

<a id="llvm-matrix-column-major-load-intrinsic"></a>

#### ‘`llvm.matrix.column.major.load.*`’ Intrinsic

<a id="id1025"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.matrix.column.major.load` to load any vector type with a stride of any bitwidth up to 64.

    declare <4 x i32> @llvm.matrix.column.major.load.v4i32.i64(
        ptrty %Ptr, i64 %Stride, i1 <IsVolatile>, i32 <Rows>, i32 <Cols>)
    declare <9 x double> @llvm.matrix.column.major.load.v9f64.i32(
        ptrty %Ptr, i32 %Stride, i1 <IsVolatile>, i32 <Rows>, i32 <Cols>)

<a id="id1026"></a>

##### Overview:

The ‘`llvm.matrix.column.major.load.*`’ intrinsics load a `<Rows> x <Cols>` matrix using a stride of `%Stride` to compute the start address of the different columns. This allows for convenient loading of sub matrixes. Independent of `%Stride`’s bitwidth, the offset is computed using the target daya layout’s pointer index type. If `<IsVolatile>` is true, the intrinsic is considered a [volatile memory access](high-level-structure.md#volatile). The result matrix is returned in the result vector. If the `%Ptr` argument is known to be aligned to some boundary, this can be specified as an attribute on the argument.

<a id="id1027"></a>

##### Arguments:

The first argument `%Ptr` is a pointer type to the returned vector type, and corresponds to the start address to load from. The second argument `%Stride` is a positive integer for which `%Stride >= <Rows>`. `%Stride` is used to compute the column memory addresses. I.e., for a column `C`, its start memory addresses is calculated with `%Ptr + C * %Stride`. The third Argument `<IsVolatile>` is a boolean value. The fourth and fifth arguments, `<Rows>` and `<Cols>`, correspond to the number of rows and columns, respectively, and must be positive, constant integers. The returned vector must have `<Rows> * <Cols>` elements.

The [align](high-level-structure.md#attr-align) parameter attribute can be provided for the `%Ptr` arguments.

<a id="llvm-matrix-column-major-store-intrinsic"></a>

#### ‘`llvm.matrix.column.major.store.*`’ Intrinsic

<a id="id1028"></a>

##### Syntax:

This is an overloaded intrinsic. `llvm.matrix.column.major.store` to store any vector type with a stride of any bitwidth up to 64.

    declare void @llvm.matrix.column.major.store.v4i32.i64(
        <4 x i32> %In, ptrty %Ptr, i64 %Stride, i1 <IsVolatile>, i32 <Rows>,
        i32 <Cols>)
    declare void @llvm.matrix.column.major.store.v9f64.i32(
        <9 x double> %In, ptrty %Ptr, i32 %Stride, i1 <IsVolatile>, i32
        <Rows>, i32 <Cols>)

<a id="id1029"></a>

##### Overview:

The ‘`llvm.matrix.column.major.store.*`’ intrinsics store the `<Rows> x <Cols>` matrix in `%In` to memory using a stride of `%Stride` between columns. Independent of `%Stride`’s bitwidth, the offset is computed using the target daya layout’s pointer index type. If `<IsVolatile>` is true, the intrinsic is considered a [volatile memory access](high-level-structure.md#volatile).

If the `%Ptr` argument is known to be aligned to some boundary, this can be specified as an attribute on the argument.

<a id="id1030"></a>

##### Arguments:

The first argument `%In` is a vector that corresponds to a `<Rows> x <Cols>` matrix to be stored to memory. The second argument `%Ptr` is a pointer to the vector type of `%In`, and is the start address of the matrix in memory. The third argument `%Stride` is a positive integer for which `%Stride >= <Rows>`. `%Stride` is used to compute the column memory addresses. I.e., for a column `C`, its start memory addresses is calculated with `%Ptr + C * %Stride`. The fourth argument `<IsVolatile>` is a boolean value. The arguments `<Rows>` and `<Cols>` correspond to the number of rows and columns, respectively, and must be positive, constant integers.

The [align](high-level-structure.md#attr-align) parameter attribute can be provided for the `%Ptr` arguments.

<a id="vector-predication-intrinsics"></a>

<a id="int-vp"></a>

### Vector Predication Intrinsics

VP intrinsics are intended for predicated SIMD/vector code. A typical VP operation takes a vector mask and an explicit vector length parameter as in:

    <W x T> llvm.vp.<opcode>.*(<W x T> %x, <W x T> %y, <W x i1> %mask, i32 %evl)

The vector mask parameter (%mask) always has a vector of `i1` type, for example `<32 x i1>`. The explicit vector length parameter always has the type `i32` and is an unsigned integer value. The explicit vector length parameter (%evl) is in the range:

    0 <= %evl <= W,  where W is the number of vector elements

Note that for [scalable vector types](type-system.md#t-vector) `W` is the runtime length of the vector.

The VP intrinsic has undefined behavior if `%evl > W`. The explicit vector length (%evl) creates a mask, %EVLmask, with all elements `0 <= i < %evl` set to True, and all other lanes `%evl <= i < W` to False. A new mask %M is calculated with an element-wise AND from %mask and %EVLmask:

    M = %mask AND %EVLmask

A vector operation `<opcode>` on vectors `A` and `B` calculates:

    A <opcode> B =  {  A[i] <opcode> B[i]   M[i] = True, and
                    {  undef otherwise

<a id="optimization-hint"></a>

#### Optimization Hint

Some targets, such as AVX512, do not support the %evl parameter in hardware. The use of an effective %evl is discouraged for those targets. The function `TargetTransformInfo::hasActiveVectorLength()` returns true when the target has native support for %evl.

<a id="llvm-vp-select-intrinsics"></a>

<a id="int-vp-select"></a>

#### ‘`llvm.vp.select.*`’ Intrinsics

<a id="id1063"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.select.v16i32 (<16 x i1> <condition>, <16 x i32> <on_true>, <16 x i32> <on_false>, i32 <evl>)
    declare <vscale x 4 x i64>  @llvm.vp.select.nxv4i64 (<vscale x 4 x i1> <condition>, <vscale x 4 x i64> <on_true>, <vscale x 4 x i64> <on_false>, i32 <evl>)

<a id="id1064"></a>

##### Overview:

The ‘`llvm.vp.select`’ intrinsic is used to choose one value based on a condition vector, without IR-level branching.

<a id="id1065"></a>

##### Arguments:

The first argument is a vector of `i1` and indicates the condition. The second argument is the value that is selected where the condition vector is true. The third argument is the value that is selected where the condition vector is false. The vectors must be of the same size. The fourth argument is the explicit vector length.

1.  The optional `fast-math flags` marker indicates that the select has one or more [fast-math flags](high-level-structure.md#fastmath). These are optimization hints to enable otherwise unsafe floating-point optimizations. Fast-math flags are only valid for selects that return [supported floating-point types](#fastmath-return-types).

<a id="id1066"></a>

##### Semantics:

The intrinsic selects lanes from the second and third argument depending on a condition vector.

All result lanes at positions greater or equal than `%evl` are undefined. For all lanes below `%evl` where the condition vector is true the lane is taken from the second argument. Otherwise, the lane is taken from the third argument.

<a id="id1067"></a>

##### Example:

    %r = call <4 x i32> @llvm.vp.select.v4i32(<4 x i1> %cond, <4 x i32> %on_true, <4 x i32> %on_false, i32 %evl)

    ;;; Expansion.
    ;; Any result is legal on lanes at and above %evl.
    %also.r = select <4 x i1> %cond, <4 x i32> %on_true, <4 x i32> %on_false

<a id="llvm-vp-merge-intrinsics"></a>

<a id="int-vp-merge"></a>

#### ‘`llvm.vp.merge.*`’ Intrinsics

<a id="id1068"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.merge.v16i32 (<16 x i1> <condition>, <16 x i32> <on_true>, <16 x i32> <on_false>, i32 <pivot>)
    declare <vscale x 4 x i64>  @llvm.vp.merge.nxv4i64 (<vscale x 4 x i1> <condition>, <vscale x 4 x i64> <on_true>, <vscale x 4 x i64> <on_false>, i32 <pivot>)

<a id="id1069"></a>

##### Overview:

The ‘`llvm.vp.merge`’ intrinsic is used to choose one value based on a condition vector and an index argument, without IR-level branching.

<a id="id1070"></a>

##### Arguments:

The first argument is a vector of `i1` and indicates the condition. The second argument is the value that is merged where the condition vector is true. The third argument is the value that is selected where the condition vector is false or the lane position is greater equal than the pivot. The fourth argument is the pivot.

1.  The optional `fast-math flags` marker indicates that the merge has one or more [fast-math flags](high-level-structure.md#fastmath). These are optimization hints to enable otherwise unsafe floating-point optimizations. Fast-math flags are only valid for merges that return [supported floating-point types](#fastmath-return-types).

<a id="id1071"></a>

##### Semantics:

The intrinsic selects lanes from the second and third argument depending on a condition vector and pivot value.

For all lanes where the condition vector is true and the lane position is less than `%pivot` the lane is taken from the second argument. Otherwise, the lane is taken from the third argument.

<a id="id1072"></a>

##### Example:

    %r = call <4 x i32> @llvm.vp.merge.v4i32(<4 x i1> %cond, <4 x i32> %on_true, <4 x i32> %on_false, i32 %pivot)

    ;;; Expansion.
    ;; Lanes at and above %pivot are taken from %on_false
    %atfirst = insertelement <4 x i32> poison, i32 %pivot, i64 0
    %splat = shufflevector <4 x i32> %atfirst, <4 x i32> poison, <4 x i32> zeroinitializer
    %pivotmask = icmp ult <4 x i32> <i32 0, i32 1, i32 2, i32 3>, <4 x i32> %splat
    %mergemask = and <4 x i1> %cond, <4 x i1> %pivotmask
    %also.r = select <4 x i1> %mergemask, <4 x i32> %on_true, <4 x i32> %on_false

<a id="llvm-vp-add-intrinsics"></a>

<a id="int-vp-add"></a>

#### ‘`llvm.vp.add.*`’ Intrinsics

<a id="id1073"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.add.v16i32 (<16 x i32> <left_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.add.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.add.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1074"></a>

##### Overview:

Predicated integer addition of two vectors of integers.

<a id="id1075"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1076"></a>

##### Semantics:

The ‘`llvm.vp.add`’ intrinsic performs integer addition ([add](instructions-arithmetic.md#i-add)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1077"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.add.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = add <4 x i32> %a, %b
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-sub-intrinsics"></a>

<a id="int-vp-sub"></a>

#### ‘`llvm.vp.sub.*`’ Intrinsics

<a id="id1078"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.sub.v16i32 (<16 x i32> <left_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.sub.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.sub.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1079"></a>

##### Overview:

Predicated integer subtraction of two vectors of integers.

<a id="id1080"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1081"></a>

##### Semantics:

The ‘`llvm.vp.sub`’ intrinsic performs integer subtraction ([sub](instructions-arithmetic.md#i-sub)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1082"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.sub.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = sub <4 x i32> %a, %b
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-mul-intrinsics"></a>

<a id="int-vp-mul"></a>

#### ‘`llvm.vp.mul.*`’ Intrinsics

<a id="id1083"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.mul.v16i32 (<16 x i32> <left_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.mul.nxv46i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.mul.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1084"></a>

##### Overview:

Predicated integer multiplication of two vectors of integers.

<a id="id1085"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1086"></a>

##### Semantics:

The ‘`llvm.vp.mul`’ intrinsic performs integer multiplication ([mul](instructions-arithmetic.md#i-mul)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1087"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.mul.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = mul <4 x i32> %a, %b
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-sdiv-intrinsics"></a>

<a id="int-vp-sdiv"></a>

#### ‘`llvm.vp.sdiv.*`’ Intrinsics

<a id="id1088"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.sdiv.v16i32 (<16 x i32> <left_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.sdiv.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.sdiv.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1089"></a>

##### Overview:

Predicated, signed division of two vectors of integers.

<a id="id1090"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1091"></a>

##### Semantics:

The ‘`llvm.vp.sdiv`’ intrinsic performs signed division ([sdiv](instructions-arithmetic.md#i-sdiv)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1092"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.sdiv.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = sdiv <4 x i32> %a, %b
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-udiv-intrinsics"></a>

<a id="int-vp-udiv"></a>

#### ‘`llvm.vp.udiv.*`’ Intrinsics

<a id="id1093"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.udiv.v16i32 (<16 x i32> <left_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.udiv.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.udiv.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1094"></a>

##### Overview:

Predicated, unsigned division of two vectors of integers.

<a id="id1095"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1096"></a>

##### Semantics:

The ‘`llvm.vp.udiv`’ intrinsic performs unsigned division ([udiv](instructions-arithmetic.md#i-udiv)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1097"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.udiv.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = udiv <4 x i32> %a, %b
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-srem-intrinsics"></a>

<a id="int-vp-srem"></a>

#### ‘`llvm.vp.srem.*`’ Intrinsics

<a id="id1098"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.srem.v16i32 (<16 x i32> <left_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.srem.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.srem.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1099"></a>

##### Overview:

Predicated computations of the signed remainder of two integer vectors.

<a id="id1100"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1101"></a>

##### Semantics:

The ‘`llvm.vp.srem`’ intrinsic computes the remainder of the signed division ([srem](instructions-arithmetic.md#i-srem)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1102"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.srem.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = srem <4 x i32> %a, %b
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-urem-intrinsics"></a>

<a id="int-vp-urem"></a>

#### ‘`llvm.vp.urem.*`’ Intrinsics

<a id="id1103"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.urem.v16i32 (<16 x i32> <left_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.urem.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.urem.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1104"></a>

##### Overview:

Predicated computation of the unsigned remainder of two integer vectors.

<a id="id1105"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1106"></a>

##### Semantics:

The ‘`llvm.vp.urem`’ intrinsic computes the remainder of the unsigned division ([urem](instructions-arithmetic.md#i-urem)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1107"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.urem.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = urem <4 x i32> %a, %b
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-ashr-intrinsics"></a>

<a id="int-vp-ashr"></a>

#### ‘`llvm.vp.ashr.*`’ Intrinsics

<a id="id1108"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.ashr.v16i32 (<16 x i32> <left_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.ashr.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.ashr.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1109"></a>

##### Overview:

Vector-predicated arithmetic right-shift.

<a id="id1110"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1111"></a>

##### Semantics:

The ‘`llvm.vp.ashr`’ intrinsic computes the arithmetic right shift ([ashr](instructions-arithmetic.md#i-ashr)) of the first argument by the second argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1112"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.ashr.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = ashr <4 x i32> %a, %b
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-lshr-intrinsics"></a>

<a id="int-vp-lshr"></a>

#### ‘`llvm.vp.lshr.*`’ Intrinsics

<a id="id1113"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.lshr.v16i32 (<16 x i32> <left_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.lshr.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.lshr.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1114"></a>

##### Overview:

Vector-predicated logical right-shift.

<a id="id1115"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1116"></a>

##### Semantics:

The ‘`llvm.vp.lshr`’ intrinsic computes the logical right shift ([lshr](instructions-arithmetic.md#i-lshr)) of the first argument by the second argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1117"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.lshr.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = lshr <4 x i32> %a, %b
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-shl-intrinsics"></a>

<a id="int-vp-shl"></a>

#### ‘`llvm.vp.shl.*`’ Intrinsics

<a id="id1118"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.shl.v16i32 (<16 x i32> <left_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.shl.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.shl.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1119"></a>

##### Overview:

Vector-predicated left shift.

<a id="id1120"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1121"></a>

##### Semantics:

The ‘`llvm.vp.shl`’ intrinsic computes the left shift ([shl](instructions-arithmetic.md#i-shl)) of the first argument by the second argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1122"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.shl.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = shl <4 x i32> %a, %b
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-or-intrinsics"></a>

<a id="int-vp-or"></a>

#### ‘`llvm.vp.or.*`’ Intrinsics

<a id="id1123"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.or.v16i32 (<16 x i32> <left_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.or.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.or.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1124"></a>

##### Overview:

Vector-predicated or.

<a id="id1125"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1126"></a>

##### Semantics:

The ‘`llvm.vp.or`’ intrinsic performs a bitwise or ([or](instructions-arithmetic.md#i-or)) of the first two arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1127"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.or.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = or <4 x i32> %a, %b
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-and-intrinsics"></a>

<a id="int-vp-and"></a>

#### ‘`llvm.vp.and.*`’ Intrinsics

<a id="id1128"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.and.v16i32 (<16 x i32> <left_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.and.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.and.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1129"></a>

##### Overview:

Vector-predicated and.

<a id="id1130"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1131"></a>

##### Semantics:

The ‘`llvm.vp.and`’ intrinsic performs a bitwise and ([and](instructions-arithmetic.md#i-or)) of the first two arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1132"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.and.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = and <4 x i32> %a, %b
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-xor-intrinsics"></a>

<a id="int-vp-xor"></a>

#### ‘`llvm.vp.xor.*`’ Intrinsics

<a id="id1133"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.xor.v16i32 (<16 x i32> <left_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.xor.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.xor.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1134"></a>

##### Overview:

Vector-predicated, bitwise xor.

<a id="id1135"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1136"></a>

##### Semantics:

The ‘`llvm.vp.xor`’ intrinsic performs a bitwise xor ([xor](instructions-arithmetic.md#i-xor)) of the first two arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1137"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.xor.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = xor <4 x i32> %a, %b
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-abs-intrinsics"></a>

<a id="int-vp-abs"></a>

#### ‘`llvm.vp.abs.*`’ Intrinsics

<a id="id1138"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.abs.v16i32 (<16 x i32> <op>, i1 <is_int_min_poison>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.abs.nxv4i32 (<vscale x 4 x i32> <op>, i1 <is_int_min_poison>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.abs.v256i64 (<256 x i64> <op>, i1 <is_int_min_poison>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1139"></a>

##### Overview:

Predicated abs of a vector of integers.

<a id="id1140"></a>

##### Arguments:

The first argument and the result have the same vector of integer type. The second argument must be a constant and is a flag to indicate whether the result value of the ‘`llvm.vp.abs`’ intrinsic is a [poison value](constants.md#poisonvalues) if the first argument is statically or dynamically an `INT_MIN` value. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1141"></a>

##### Semantics:

The ‘`llvm.vp.abs`’ intrinsic performs abs ([abs](intrinsics-libc-and-arithmetic.md#int-abs)) of the first argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1142"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.abs.v4i32(<4 x i32> %a, i1 false, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.abs.v4i32(<4 x i32> %a, i1 false)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-smax-intrinsics"></a>

<a id="int-vp-smax"></a>

#### ‘`llvm.vp.smax.*`’ Intrinsics

<a id="id1143"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.smax.v16i32 (<16 x i32> <left_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.smax.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.smax.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1144"></a>

##### Overview:

Predicated integer signed maximum of two vectors of integers.

<a id="id1145"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1146"></a>

##### Semantics:

The ‘`llvm.vp.smax`’ intrinsic performs integer signed maximum ([smax](intrinsics-libc-and-arithmetic.md#int-smax)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1147"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.smax.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.smax.v4i32(<4 x i32> %a, <4 x i32> %b)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-smin-intrinsics"></a>

<a id="int-vp-smin"></a>

#### ‘`llvm.vp.smin.*`’ Intrinsics

<a id="id1148"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.smin.v16i32 (<16 x i32> <left_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.smin.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.smin.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1149"></a>

##### Overview:

Predicated integer signed minimum of two vectors of integers.

<a id="id1150"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1151"></a>

##### Semantics:

The ‘`llvm.vp.smin`’ intrinsic performs integer signed minimum ([smin](intrinsics-libc-and-arithmetic.md#int-smin)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1152"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.smin.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.smin.v4i32(<4 x i32> %a, <4 x i32> %b)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-umax-intrinsics"></a>

<a id="int-vp-umax"></a>

#### ‘`llvm.vp.umax.*`’ Intrinsics

<a id="id1153"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.umax.v16i32 (<16 x i32> <left_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.umax.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.umax.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1154"></a>

##### Overview:

Predicated integer unsigned maximum of two vectors of integers.

<a id="id1155"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1156"></a>

##### Semantics:

The ‘`llvm.vp.umax`’ intrinsic performs integer unsigned maximum ([umax](intrinsics-libc-and-arithmetic.md#int-umax)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1157"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.umax.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.umax.v4i32(<4 x i32> %a, <4 x i32> %b)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-umin-intrinsics"></a>

<a id="int-vp-umin"></a>

#### ‘`llvm.vp.umin.*`’ Intrinsics

<a id="id1158"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.umin.v16i32 (<16 x i32> <left_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.umin.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.umin.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1159"></a>

##### Overview:

Predicated integer unsigned minimum of two vectors of integers.

<a id="id1160"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1161"></a>

##### Semantics:

The ‘`llvm.vp.umin`’ intrinsic performs integer unsigned minimum ([umin](intrinsics-libc-and-arithmetic.md#int-umin)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1162"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.umin.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.umin.v4i32(<4 x i32> %a, <4 x i32> %b)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-copysign-intrinsics"></a>

<a id="int-vp-copysign"></a>

#### ‘`llvm.vp.copysign.*`’ Intrinsics

<a id="id1163"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.copysign.v16f32 (<16 x float> <mag_op>, <16 x float> <sign_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.copysign.nxv4f32 (<vscale x 4 x float> <mag_op>, <vscale x 4 x float> <sign_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.copysign.v256f64 (<256 x double> <mag_op>, <256 x double> <sign_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1164"></a>

##### Overview:

Predicated floating-point copysign of two vectors of floating-point values.

<a id="id1165"></a>

##### Arguments:

The first two arguments and the result have the same vector of floating-point type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1166"></a>

##### Semantics:

The ‘`llvm.vp.copysign`’ intrinsic performs floating-point copysign ([copysign](intrinsics-libc-and-arithmetic.md#int-copysign)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues). The operation is performed in the default floating-point environment.

<a id="id1167"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.copysign.v4f32(<4 x float> %mag, <4 x float> %sign, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x float> @llvm.copysign.v4f32(<4 x float> %mag, <4 x float> %sign)
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-minnum-intrinsics"></a>

<a id="int-vp-minnum"></a>

#### ‘`llvm.vp.minnum.*`’ Intrinsics

<a id="id1168"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.minnum.v16f32 (<16 x float> <left_op>, <16 x float> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.minnum.nxv4f32 (<vscale x 4 x float> <left_op>, <vscale x 4 x float> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.minnum.v256f64 (<256 x double> <left_op>, <256 x double> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1169"></a>

##### Overview:

Predicated floating-point IEEE 754-2008 minNum of two vectors of floating-point values.

<a id="id1170"></a>

##### Arguments:

The first two arguments and the result have the same vector of floating-point type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1171"></a>

##### Semantics:

The ‘`llvm.vp.minnum`’ intrinsic performs floating-point minimum ([minnum](intrinsics-libc-and-arithmetic.md#i-minnum)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues). The operation is performed in the default floating-point environment.

<a id="id1172"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.minnum.v4f32(<4 x float> %a, <4 x float> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x float> @llvm.minnum.v4f32(<4 x float> %a, <4 x float> %b)
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-maxnum-intrinsics"></a>

<a id="int-vp-maxnum"></a>

#### ‘`llvm.vp.maxnum.*`’ Intrinsics

<a id="id1173"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.maxnum.v16f32 (<16 x float> <left_op>, <16 x float> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.maxnum.nxv4f32 (<vscale x 4 x float> <left_op>, <vscale x 4 x float> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.maxnum.v256f64 (<256 x double> <left_op>, <256 x double> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1174"></a>

##### Overview:

Predicated floating-point IEEE 754-2008 maxNum of two vectors of floating-point values.

<a id="id1175"></a>

##### Arguments:

The first two arguments and the result have the same vector of floating-point type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1176"></a>

##### Semantics:

The ‘`llvm.vp.maxnum`’ intrinsic performs floating-point maximum ([maxnum](intrinsics-libc-and-arithmetic.md#i-maxnum)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues). The operation is performed in the default floating-point environment.

<a id="id1177"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.maxnum.v4f32(<4 x float> %a, <4 x float> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x float> @llvm.maxnum.v4f32(<4 x float> %a, <4 x float> %b, <4 x i1> %mask, i32 %evl)
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-minimum-intrinsics"></a>

<a id="int-vp-minimum"></a>

#### ‘`llvm.vp.minimum.*`’ Intrinsics

<a id="id1178"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.minimum.v16f32 (<16 x float> <left_op>, <16 x float> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.minimum.nxv4f32 (<vscale x 4 x float> <left_op>, <vscale x 4 x float> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.minimum.v256f64 (<256 x double> <left_op>, <256 x double> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1179"></a>

##### Overview:

Predicated floating-point minimum of two vectors of floating-point values, propagating NaNs and treating -0.0 as less than +0.0.

<a id="id1180"></a>

##### Arguments:

The first two arguments and the result have the same vector of floating-point type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1181"></a>

##### Semantics:

The ‘`llvm.vp.minimum`’ intrinsic performs floating-point minimum ([minimum](intrinsics-libc-and-arithmetic.md#i-minimum)) of the first and second vector arguments on each enabled lane, the result being NaN if either argument is a NaN. -0.0 is considered to be less than +0.0 for this intrinsic. The result on disabled lanes is a [poison value](constants.md#poisonvalues). The operation is performed in the default floating-point environment.

<a id="id1182"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.minimum.v4f32(<4 x float> %a, <4 x float> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x float> @llvm.minimum.v4f32(<4 x float> %a, <4 x float> %b)
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-maximum-intrinsics"></a>

<a id="int-vp-maximum"></a>

#### ‘`llvm.vp.maximum.*`’ Intrinsics

<a id="id1183"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.maximum.v16f32 (<16 x float> <left_op>, <16 x float> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.maximum.nxv4f32 (<vscale x 4 x float> <left_op>, <vscale x 4 x float> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.maximum.v256f64 (<256 x double> <left_op>, <256 x double> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1184"></a>

##### Overview:

Predicated floating-point maximum of two vectors of floating-point values, propagating NaNs and treating -0.0 as less than +0.0.

<a id="id1185"></a>

##### Arguments:

The first two arguments and the result have the same vector of floating-point type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1186"></a>

##### Semantics:

The ‘`llvm.vp.maximum`’ intrinsic performs floating-point maximum ([maximum](intrinsics-libc-and-arithmetic.md#i-maximum)) of the first and second vector arguments on each enabled lane, the result being NaN if either argument is a NaN. -0.0 is considered to be less than +0.0 for this intrinsic. The result on disabled lanes is a [poison value](constants.md#poisonvalues). The operation is performed in the default floating-point environment.

<a id="id1187"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.maximum.v4f32(<4 x float> %a, <4 x float> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x float> @llvm.maximum.v4f32(<4 x float> %a, <4 x float> %b, <4 x i1> %mask, i32 %evl)
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-fadd-intrinsics"></a>

<a id="int-vp-fadd"></a>

#### ‘`llvm.vp.fadd.*`’ Intrinsics

<a id="id1188"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.fadd.v16f32 (<16 x float> <left_op>, <16 x float> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.fadd.nxv4f32 (<vscale x 4 x float> <left_op>, <vscale x 4 x float> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.fadd.v256f64 (<256 x double> <left_op>, <256 x double> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1189"></a>

##### Overview:

Predicated floating-point addition of two vectors of floating-point values.

<a id="id1190"></a>

##### Arguments:

The first two arguments and the result have the same vector of floating-point type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1191"></a>

##### Semantics:

The ‘`llvm.vp.fadd`’ intrinsic performs floating-point addition ([fadd](instructions-arithmetic.md#i-fadd)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues). The operation is performed in the default floating-point environment.

<a id="id1192"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.fadd.v4f32(<4 x float> %a, <4 x float> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = fadd <4 x float> %a, %b
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-fsub-intrinsics"></a>

<a id="int-vp-fsub"></a>

#### ‘`llvm.vp.fsub.*`’ Intrinsics

<a id="id1193"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.fsub.v16f32 (<16 x float> <left_op>, <16 x float> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.fsub.nxv4f32 (<vscale x 4 x float> <left_op>, <vscale x 4 x float> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.fsub.v256f64 (<256 x double> <left_op>, <256 x double> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1194"></a>

##### Overview:

Predicated floating-point subtraction of two vectors of floating-point values.

<a id="id1195"></a>

##### Arguments:

The first two arguments and the result have the same vector of floating-point type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1196"></a>

##### Semantics:

The ‘`llvm.vp.fsub`’ intrinsic performs floating-point subtraction ([fsub](instructions-arithmetic.md#i-fsub)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues). The operation is performed in the default floating-point environment.

<a id="id1197"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.fsub.v4f32(<4 x float> %a, <4 x float> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = fsub <4 x float> %a, %b
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-fmul-intrinsics"></a>

<a id="int-vp-fmul"></a>

#### ‘`llvm.vp.fmul.*`’ Intrinsics

<a id="id1198"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.fmul.v16f32 (<16 x float> <left_op>, <16 x float> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.fmul.nxv4f32 (<vscale x 4 x float> <left_op>, <vscale x 4 x float> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.fmul.v256f64 (<256 x double> <left_op>, <256 x double> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1199"></a>

##### Overview:

Predicated floating-point multiplication of two vectors of floating-point values.

<a id="id1200"></a>

##### Arguments:

The first two arguments and the result have the same vector of floating-point type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1201"></a>

##### Semantics:

The ‘`llvm.vp.fmul`’ intrinsic performs floating-point multiplication ([fmul](instructions-arithmetic.md#i-fmul)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues). The operation is performed in the default floating-point environment.

<a id="id1202"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.fmul.v4f32(<4 x float> %a, <4 x float> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = fmul <4 x float> %a, %b
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-fdiv-intrinsics"></a>

<a id="int-vp-fdiv"></a>

#### ‘`llvm.vp.fdiv.*`’ Intrinsics

<a id="id1203"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.fdiv.v16f32 (<16 x float> <left_op>, <16 x float> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.fdiv.nxv4f32 (<vscale x 4 x float> <left_op>, <vscale x 4 x float> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.fdiv.v256f64 (<256 x double> <left_op>, <256 x double> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1204"></a>

##### Overview:

Predicated floating-point division of two vectors of floating-point values.

<a id="id1205"></a>

##### Arguments:

The first two arguments and the result have the same vector of floating-point type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1206"></a>

##### Semantics:

The ‘`llvm.vp.fdiv`’ intrinsic performs floating-point division ([fdiv](instructions-arithmetic.md#i-fdiv)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues). The operation is performed in the default floating-point environment.

<a id="id1207"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.fdiv.v4f32(<4 x float> %a, <4 x float> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = fdiv <4 x float> %a, %b
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-frem-intrinsics"></a>

<a id="int-vp-frem"></a>

#### ‘`llvm.vp.frem.*`’ Intrinsics

<a id="id1208"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.frem.v16f32 (<16 x float> <left_op>, <16 x float> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.frem.nxv4f32 (<vscale x 4 x float> <left_op>, <vscale x 4 x float> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.frem.v256f64 (<256 x double> <left_op>, <256 x double> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1209"></a>

##### Overview:

Predicated floating-point remainder of two vectors of floating-point values.

<a id="id1210"></a>

##### Arguments:

The first two arguments and the result have the same vector of floating-point type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1211"></a>

##### Semantics:

The ‘`llvm.vp.frem`’ intrinsic performs floating-point remainder ([frem](instructions-arithmetic.md#i-frem)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues). The operation is performed in the default floating-point environment.

<a id="id1212"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.frem.v4f32(<4 x float> %a, <4 x float> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = frem <4 x float> %a, %b
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-fneg-intrinsics"></a>

<a id="int-vp-fneg"></a>

#### ‘`llvm.vp.fneg.*`’ Intrinsics

<a id="id1213"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.fneg.v16f32 (<16 x float> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.fneg.nxv4f32 (<vscale x 4 x float> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.fneg.v256f64 (<256 x double> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1214"></a>

##### Overview:

Predicated floating-point negation of a vector of floating-point values.

<a id="id1215"></a>

##### Arguments:

The first argument and the result have the same vector of floating-point type. The second argument is the vector mask and has the same number of elements as the result vector type. The third argument is the explicit vector length of the operation.

<a id="id1216"></a>

##### Semantics:

The ‘`llvm.vp.fneg`’ intrinsic performs floating-point negation ([fneg](instructions-arithmetic.md#i-fneg)) of the first vector argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1217"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.fneg.v4f32(<4 x float> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = fneg <4 x float> %a
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-fabs-intrinsics"></a>

<a id="int-vp-fabs"></a>

#### ‘`llvm.vp.fabs.*`’ Intrinsics

<a id="id1218"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.fabs.v16f32 (<16 x float> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.fabs.nxv4f32 (<vscale x 4 x float> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.fabs.v256f64 (<256 x double> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1219"></a>

##### Overview:

Predicated floating-point absolute value of a vector of floating-point values.

<a id="id1220"></a>

##### Arguments:

The first argument and the result have the same vector of floating-point type. The second argument is the vector mask and has the same number of elements as the result vector type. The third argument is the explicit vector length of the operation.

<a id="id1221"></a>

##### Semantics:

The ‘`llvm.vp.fabs`’ intrinsic performs floating-point absolute value ([fabs](intrinsics-libc-and-arithmetic.md#int-fabs)) of the first vector argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1222"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.fabs.v4f32(<4 x float> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x float> @llvm.fabs.v4f32(<4 x float> %a)
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-sqrt-intrinsics"></a>

<a id="int-vp-sqrt"></a>

#### ‘`llvm.vp.sqrt.*`’ Intrinsics

<a id="id1223"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.sqrt.v16f32 (<16 x float> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.sqrt.nxv4f32 (<vscale x 4 x float> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.sqrt.v256f64 (<256 x double> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1224"></a>

##### Overview:

Predicated floating-point square root of a vector of floating-point values.

<a id="id1225"></a>

##### Arguments:

The first argument and the result have the same vector of floating-point type. The second argument is the vector mask and has the same number of elements as the result vector type. The third argument is the explicit vector length of the operation.

<a id="id1226"></a>

##### Semantics:

The ‘`llvm.vp.sqrt`’ intrinsic performs floating-point square root ([sqrt](intrinsics-libc-and-arithmetic.md#int-sqrt)) of the first vector argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues). The operation is performed in the default floating-point environment.

<a id="id1227"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.sqrt.v4f32(<4 x float> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x float> @llvm.sqrt.v4f32(<4 x float> %a)
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-fma-intrinsics"></a>

<a id="int-vp-fma"></a>

#### ‘`llvm.vp.fma.*`’ Intrinsics

<a id="id1228"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.fma.v16f32 (<16 x float> <left_op>, <16 x float> <middle_op>, <16 x float> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.fma.nxv4f32 (<vscale x 4 x float> <left_op>, <vscale x 4 x float> <middle_op>, <vscale x 4 x float> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.fma.v256f64 (<256 x double> <left_op>, <256 x double> <middle_op>, <256 x double> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1229"></a>

##### Overview:

Predicated floating-point fused multiply-add of two vectors of floating-point values.

<a id="id1230"></a>

##### Arguments:

The first three arguments and the result have the same vector of floating-point type. The fourth argument is the vector mask and has the same number of elements as the result vector type. The fifth argument is the explicit vector length of the operation.

<a id="id1231"></a>

##### Semantics:

The ‘`llvm.vp.fma`’ intrinsic performs floating-point fused multiply-add ([llvm.fma](intrinsics-libc-and-arithmetic.md#int-fma)) of the first, second, and third vector argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues). The operation is performed in the default floating-point environment.

<a id="id1232"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.fma.v4f32(<4 x float> %a, <4 x float> %b, <4 x float> %c, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x float> @llvm.fma(<4 x float> %a, <4 x float> %b, <4 x float> %c)
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-fmuladd-intrinsics"></a>

<a id="int-vp-fmuladd"></a>

#### ‘`llvm.vp.fmuladd.*`’ Intrinsics

<a id="id1233"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.fmuladd.v16f32 (<16 x float> <left_op>, <16 x float> <middle_op>, <16 x float> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.fmuladd.nxv4f32 (<vscale x 4 x float> <left_op>, <vscale x 4 x float> <middle_op>, <vscale x 4 x float> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.fmuladd.v256f64 (<256 x double> <left_op>, <256 x double> <middle_op>, <256 x double> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1234"></a>

##### Overview:

Predicated floating-point multiply-add of two vectors of floating-point values that can be fused if code generator determines that (a) the target instruction set has support for a fused operation, and (b) that the fused operation is more efficient than the equivalent, separate pair of mul and add instructions.

<a id="id1235"></a>

##### Arguments:

The first three arguments and the result have the same vector of floating-point type. The fourth argument is the vector mask and has the same number of elements as the result vector type. The fifth argument is the explicit vector length of the operation.

<a id="id1236"></a>

##### Semantics:

The ‘`llvm.vp.fmuladd`’ intrinsic performs floating-point multiply-add ([llvm.fuladd](intrinsics-libc-and-arithmetic.md#int-fmuladd)) of the first, second, and third vector argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues). The operation is performed in the default floating-point environment.

<a id="id1237"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.fmuladd.v4f32(<4 x float> %a, <4 x float> %b, <4 x float> %c, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x float> @llvm.fmuladd(<4 x float> %a, <4 x float> %b, <4 x float> %c)
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-reduce-add-intrinsics"></a>

<a id="int-vp-reduce-add"></a>

#### ‘`llvm.vp.reduce.add.*`’ Intrinsics

<a id="id1238"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare i32 @llvm.vp.reduce.add.v4i32(i32 <start_value>, <4 x i32> <val>, <4 x i1> <mask>, i32 <vector_length>)
    declare i16 @llvm.vp.reduce.add.nxv8i16(i16 <start_value>, <vscale x 8 x i16> <val>, <vscale x 8 x i1> <mask>, i32 <vector_length>)

<a id="id1239"></a>

##### Overview:

Predicated integer `ADD` reduction of a vector and a scalar starting value, returning the result as a scalar.

<a id="id1240"></a>

##### Arguments:

The first argument is the start value of the reduction, which must be a scalar integer type equal to the result type. The second argument is the vector on which the reduction is performed and must be a vector of integer values whose element type is the result/start type. The third argument is the vector mask and is a vector of boolean values with the same number of elements as the vector argument. The fourth argument is the explicit vector length of the operation.

<a id="id1241"></a>

##### Semantics:

The ‘`llvm.vp.reduce.add`’ intrinsic performs the integer `ADD` reduction ([llvm.vector.reduce.add](#int-vector-reduce-add)) of the vector argument `val` on each enabled lane, adding it to the scalar `start_value`. Disabled lanes are treated as containing the neutral value `0` (i.e., having no effect on the reduction operation). If the vector length is zero, the result is equal to `start_value`.

To ignore the start value, the neutral value can be used.

<a id="id1242"></a>

##### Examples:

    %r = call i32 @llvm.vp.reduce.add.v4i32(i32 %start, <4 x i32> %a, <4 x i1> %mask, i32 %evl)
    ; %r is equivalent to %also.r, where lanes greater than or equal to %evl
    ; are treated as though %mask were false for those lanes.

    %masked.a = select <4 x i1> %mask, <4 x i32> %a, <4 x i32> zeroinitializer
    %reduction = call i32 @llvm.vector.reduce.add.v4i32(<4 x i32> %masked.a)
    %also.r = add i32 %reduction, %start

<a id="llvm-vp-reduce-fadd-intrinsics"></a>

<a id="int-vp-reduce-fadd"></a>

#### ‘`llvm.vp.reduce.fadd.*`’ Intrinsics

<a id="id1243"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare float @llvm.vp.reduce.fadd.v4f32(float <start_value>, <4 x float> <val>, <4 x i1> <mask>, i32 <vector_length>)
    declare double @llvm.vp.reduce.fadd.nxv8f64(double <start_value>, <vscale x 8 x double> <val>, <vscale x 8 x i1> <mask>, i32 <vector_length>)

<a id="id1244"></a>

##### Overview:

Predicated floating-point `ADD` reduction of a vector and a scalar starting value, returning the result as a scalar.

<a id="id1245"></a>

##### Arguments:

The first argument is the start value of the reduction, which must be a scalar floating-point type equal to the result type. The second argument is the vector on which the reduction is performed and must be a vector of floating-point values whose element type is the result/start type. The third argument is the vector mask and is a vector of boolean values with the same number of elements as the vector argument. The fourth argument is the explicit vector length of the operation.

<a id="id1246"></a>

##### Semantics:

The ‘`llvm.vp.reduce.fadd`’ intrinsic performs the floating-point `ADD` reduction ([llvm.vector.reduce.fadd](#int-vector-reduce-fadd)) of the vector argument `val` on each enabled lane, adding it to the scalar `start_value`. Disabled lanes are treated as containing the neutral value `-0.0` (i.e., having no effect on the reduction operation). If no lanes are enabled, the resulting value will be equal to `start_value`.

To ignore the start value, the neutral value can be used.

See the unpredicated version ([llvm.vector.reduce.fadd](#int-vector-reduce-fadd)) for more detail on the semantics of the reduction.

<a id="id1247"></a>

##### Examples:

    %r = call float @llvm.vp.reduce.fadd.v4f32(float %start, <4 x float> %a, <4 x i1> %mask, i32 %evl)
    ; %r is equivalent to %also.r, where lanes greater than or equal to %evl
    ; are treated as though %mask were false for those lanes.

    %masked.a = select <4 x i1> %mask, <4 x float> %a, <4 x float> <float -0.0, float -0.0, float -0.0, float -0.0>
    %also.r = call float @llvm.vector.reduce.fadd.v4f32(float %start, <4 x float> %masked.a)

<a id="llvm-vp-reduce-mul-intrinsics"></a>

<a id="int-vp-reduce-mul"></a>

#### ‘`llvm.vp.reduce.mul.*`’ Intrinsics

<a id="id1248"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare i32 @llvm.vp.reduce.mul.v4i32(i32 <start_value>, <4 x i32> <val>, <4 x i1> <mask>, i32 <vector_length>)
    declare i16 @llvm.vp.reduce.mul.nxv8i16(i16 <start_value>, <vscale x 8 x i16> <val>, <vscale x 8 x i1> <mask>, i32 <vector_length>)

<a id="id1249"></a>

##### Overview:

Predicated integer `MUL` reduction of a vector and a scalar starting value, returning the result as a scalar.

<a id="id1250"></a>

##### Arguments:

The first argument is the start value of the reduction, which must be a scalar integer type equal to the result type. The second argument is the vector on which the reduction is performed and must be a vector of integer values whose element type is the result/start type. The third argument is the vector mask and is a vector of boolean values with the same number of elements as the vector argument. The fourth argument is the explicit vector length of the operation.

<a id="id1251"></a>

##### Semantics:

The ‘`llvm.vp.reduce.mul`’ intrinsic performs the integer `MUL` reduction ([llvm.vector.reduce.mul](#int-vector-reduce-mul)) of the vector argument `val` on each enabled lane, multiplying it by the scalar `start_value`. Disabled lanes are treated as containing the neutral value `1` (i.e., having no effect on the reduction operation). If the vector length is zero, the result is the start value.

To ignore the start value, the neutral value can be used.

<a id="id1252"></a>

##### Examples:

    %r = call i32 @llvm.vp.reduce.mul.v4i32(i32 %start, <4 x i32> %a, <4 x i1> %mask, i32 %evl)
    ; %r is equivalent to %also.r, where lanes greater than or equal to %evl
    ; are treated as though %mask were false for those lanes.

    %masked.a = select <4 x i1> %mask, <4 x i32> %a, <4 x i32> <i32 1, i32 1, i32 1, i32 1>
    %reduction = call i32 @llvm.vector.reduce.mul.v4i32(<4 x i32> %masked.a)
    %also.r = mul i32 %reduction, %start

<a id="llvm-vp-reduce-fmul-intrinsics"></a>

<a id="int-vp-reduce-fmul"></a>

#### ‘`llvm.vp.reduce.fmul.*`’ Intrinsics

<a id="id1253"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare float @llvm.vp.reduce.fmul.v4f32(float <start_value>, <4 x float> <val>, <4 x i1> <mask>, i32 <vector_length>)
    declare double @llvm.vp.reduce.fmul.nxv8f64(double <start_value>, <vscale x 8 x double> <val>, <vscale x 8 x i1> <mask>, i32 <vector_length>)

<a id="id1254"></a>

##### Overview:

Predicated floating-point `MUL` reduction of a vector and a scalar starting value, returning the result as a scalar.

<a id="id1255"></a>

##### Arguments:

The first argument is the start value of the reduction, which must be a scalar floating-point type equal to the result type. The second argument is the vector on which the reduction is performed and must be a vector of floating-point values whose element type is the result/start type. The third argument is the vector mask and is a vector of boolean values with the same number of elements as the vector argument. The fourth argument is the explicit vector length of the operation.

<a id="id1256"></a>

##### Semantics:

The ‘`llvm.vp.reduce.fmul`’ intrinsic performs the floating-point `MUL` reduction ([llvm.vector.reduce.fmul](#int-vector-reduce-fmul)) of the vector argument `val` on each enabled lane, multiplying it by the scalar `start_value`. Disabled lanes are treated as containing the neutral value `1.0` (i.e., having no effect on the reduction operation). If no lanes are enabled, the resulting value will be equal to the starting value.

To ignore the start value, the neutral value can be used.

See the unpredicated version ([llvm.vector.reduce.fmul](#int-vector-reduce-fmul)) for more detail on the semantics.

<a id="id1257"></a>

##### Examples:

    %r = call float @llvm.vp.reduce.fmul.v4f32(float %start, <4 x float> %a, <4 x i1> %mask, i32 %evl)
    ; %r is equivalent to %also.r, where lanes greater than or equal to %evl
    ; are treated as though %mask were false for those lanes.

    %masked.a = select <4 x i1> %mask, <4 x float> %a, <4 x float> <float 1.0, float 1.0, float 1.0, float 1.0>
    %also.r = call float @llvm.vector.reduce.fmul.v4f32(float %start, <4 x float> %masked.a)

<a id="llvm-vp-reduce-and-intrinsics"></a>

<a id="int-vp-reduce-and"></a>

#### ‘`llvm.vp.reduce.and.*`’ Intrinsics

<a id="id1258"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare i32 @llvm.vp.reduce.and.v4i32(i32 <start_value>, <4 x i32> <val>, <4 x i1> <mask>, i32 <vector_length>)
    declare i16 @llvm.vp.reduce.and.nxv8i16(i16 <start_value>, <vscale x 8 x i16> <val>, <vscale x 8 x i1> <mask>, i32 <vector_length>)

<a id="id1259"></a>

##### Overview:

Predicated integer `AND` reduction of a vector and a scalar starting value, returning the result as a scalar.

<a id="id1260"></a>

##### Arguments:

The first argument is the start value of the reduction, which must be a scalar integer type equal to the result type. The second argument is the vector on which the reduction is performed and must be a vector of integer values whose element type is the result/start type. The third argument is the vector mask and is a vector of boolean values with the same number of elements as the vector argument. The fourth argument is the explicit vector length of the operation.

<a id="id1261"></a>

##### Semantics:

The ‘`llvm.vp.reduce.and`’ intrinsic performs the integer `AND` reduction ([llvm.vector.reduce.and](#int-vector-reduce-and)) of the vector argument `val` on each enabled lane, performing an ‘`and`’ of that with with the scalar `start_value`. Disabled lanes are treated as containing the neutral value `UINT_MAX`, or `-1` (i.e., having no effect on the reduction operation). If the vector length is zero, the result is the start value.

To ignore the start value, the neutral value can be used.

<a id="id1262"></a>

##### Examples:

    %r = call i32 @llvm.vp.reduce.and.v4i32(i32 %start, <4 x i32> %a, <4 x i1> %mask, i32 %evl)
    ; %r is equivalent to %also.r, where lanes greater than or equal to %evl
    ; are treated as though %mask were false for those lanes.

    %masked.a = select <4 x i1> %mask, <4 x i32> %a, <4 x i32> <i32 -1, i32 -1, i32 -1, i32 -1>
    %reduction = call i32 @llvm.vector.reduce.and.v4i32(<4 x i32> %masked.a)
    %also.r = and i32 %reduction, %start

<a id="llvm-vp-reduce-or-intrinsics"></a>

<a id="int-vp-reduce-or"></a>

#### ‘`llvm.vp.reduce.or.*`’ Intrinsics

<a id="id1263"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare i32 @llvm.vp.reduce.or.v4i32(i32 <start_value>, <4 x i32> <val>, <4 x i1> <mask>, i32 <vector_length>)
    declare i16 @llvm.vp.reduce.or.nxv8i16(i16 <start_value>, <vscale x 8 x i16> <val>, <vscale x 8 x i1> <mask>, i32 <vector_length>)

<a id="id1264"></a>

##### Overview:

Predicated integer `OR` reduction of a vector and a scalar starting value, returning the result as a scalar.

<a id="id1265"></a>

##### Arguments:

The first argument is the start value of the reduction, which must be a scalar integer type equal to the result type. The second argument is the vector on which the reduction is performed and must be a vector of integer values whose element type is the result/start type. The third argument is the vector mask and is a vector of boolean values with the same number of elements as the vector argument. The fourth argument is the explicit vector length of the operation.

<a id="id1266"></a>

##### Semantics:

The ‘`llvm.vp.reduce.or`’ intrinsic performs the integer `OR` reduction ([llvm.vector.reduce.or](#int-vector-reduce-or)) of the vector argument `val` on each enabled lane, performing an ‘`or`’ of that with the scalar `start_value`. Disabled lanes are treated as containing the neutral value `0` (i.e., having no effect on the reduction operation). If the vector length is zero, the result is the start value.

To ignore the start value, the neutral value can be used.

<a id="id1267"></a>

##### Examples:

    %r = call i32 @llvm.vp.reduce.or.v4i32(i32 %start, <4 x i32> %a, <4 x i1> %mask, i32 %evl)
    ; %r is equivalent to %also.r, where lanes greater than or equal to %evl
    ; are treated as though %mask were false for those lanes.

    %masked.a = select <4 x i1> %mask, <4 x i32> %a, <4 x i32> <i32 0, i32 0, i32 0, i32 0>
    %reduction = call i32 @llvm.vector.reduce.or.v4i32(<4 x i32> %masked.a)
    %also.r = or i32 %reduction, %start

<a id="llvm-vp-reduce-xor-intrinsics"></a>

<a id="int-vp-reduce-xor"></a>

#### ‘`llvm.vp.reduce.xor.*`’ Intrinsics

<a id="id1268"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare i32 @llvm.vp.reduce.xor.v4i32(i32 <start_value>, <4 x i32> <val>, <4 x i1> <mask>, i32 <vector_length>)
    declare i16 @llvm.vp.reduce.xor.nxv8i16(i16 <start_value>, <vscale x 8 x i16> <val>, <vscale x 8 x i1> <mask>, i32 <vector_length>)

<a id="id1269"></a>

##### Overview:

Predicated integer `XOR` reduction of a vector and a scalar starting value, returning the result as a scalar.

<a id="id1270"></a>

##### Arguments:

The first argument is the start value of the reduction, which must be a scalar integer type equal to the result type. The second argument is the vector on which the reduction is performed and must be a vector of integer values whose element type is the result/start type. The third argument is the vector mask and is a vector of boolean values with the same number of elements as the vector argument. The fourth argument is the explicit vector length of the operation.

<a id="id1271"></a>

##### Semantics:

The ‘`llvm.vp.reduce.xor`’ intrinsic performs the integer `XOR` reduction ([llvm.vector.reduce.xor](#int-vector-reduce-xor)) of the vector argument `val` on each enabled lane, performing an ‘`xor`’ of that with the scalar `start_value`. Disabled lanes are treated as containing the neutral value `0` (i.e., having no effect on the reduction operation). If the vector length is zero, the result is the start value.

To ignore the start value, the neutral value can be used.

<a id="id1272"></a>

##### Examples:

    %r = call i32 @llvm.vp.reduce.xor.v4i32(i32 %start, <4 x i32> %a, <4 x i1> %mask, i32 %evl)
    ; %r is equivalent to %also.r, where lanes greater than or equal to %evl
    ; are treated as though %mask were false for those lanes.

    %masked.a = select <4 x i1> %mask, <4 x i32> %a, <4 x i32> <i32 0, i32 0, i32 0, i32 0>
    %reduction = call i32 @llvm.vector.reduce.xor.v4i32(<4 x i32> %masked.a)
    %also.r = xor i32 %reduction, %start

<a id="llvm-vp-reduce-smax-intrinsics"></a>

<a id="int-vp-reduce-smax"></a>

#### ‘`llvm.vp.reduce.smax.*`’ Intrinsics

<a id="id1273"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare i32 @llvm.vp.reduce.smax.v4i32(i32 <start_value>, <4 x i32> <val>, <4 x i1> <mask>, i32 <vector_length>)
    declare i16 @llvm.vp.reduce.smax.nxv8i16(i16 <start_value>, <vscale x 8 x i16> <val>, <vscale x 8 x i1> <mask>, i32 <vector_length>)

<a id="id1274"></a>

##### Overview:

Predicated signed-integer `MAX` reduction of a vector and a scalar starting value, returning the result as a scalar.

<a id="id1275"></a>

##### Arguments:

The first argument is the start value of the reduction, which must be a scalar integer type equal to the result type. The second argument is the vector on which the reduction is performed and must be a vector of integer values whose element type is the result/start type. The third argument is the vector mask and is a vector of boolean values with the same number of elements as the vector argument. The fourth argument is the explicit vector length of the operation.

<a id="id1276"></a>

##### Semantics:

The ‘`llvm.vp.reduce.smax`’ intrinsic performs the signed-integer `MAX` reduction ([llvm.vector.reduce.smax](#int-vector-reduce-smax)) of the vector argument `val` on each enabled lane, and taking the maximum of that and the scalar `start_value`. Disabled lanes are treated as containing the neutral value `INT_MIN` (i.e., having no effect on the reduction operation). If the vector length is zero, the result is the start value.

To ignore the start value, the neutral value can be used.

<a id="id1277"></a>

##### Examples:

    %r = call i8 @llvm.vp.reduce.smax.v4i8(i8 %start, <4 x i8> %a, <4 x i1> %mask, i32 %evl)
    ; %r is equivalent to %also.r, where lanes greater than or equal to %evl
    ; are treated as though %mask were false for those lanes.

    %masked.a = select <4 x i1> %mask, <4 x i8> %a, <4 x i8> <i8 -128, i8 -128, i8 -128, i8 -128>
    %reduction = call i8 @llvm.vector.reduce.smax.v4i8(<4 x i8> %masked.a)
    %also.r = call i8 @llvm.smax.i8(i8 %reduction, i8 %start)

<a id="llvm-vp-reduce-smin-intrinsics"></a>

<a id="int-vp-reduce-smin"></a>

#### ‘`llvm.vp.reduce.smin.*`’ Intrinsics

<a id="id1278"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare i32 @llvm.vp.reduce.smin.v4i32(i32 <start_value>, <4 x i32> <val>, <4 x i1> <mask>, i32 <vector_length>)
    declare i16 @llvm.vp.reduce.smin.nxv8i16(i16 <start_value>, <vscale x 8 x i16> <val>, <vscale x 8 x i1> <mask>, i32 <vector_length>)

<a id="id1279"></a>

##### Overview:

Predicated signed-integer `MIN` reduction of a vector and a scalar starting value, returning the result as a scalar.

<a id="id1280"></a>

##### Arguments:

The first argument is the start value of the reduction, which must be a scalar integer type equal to the result type. The second argument is the vector on which the reduction is performed and must be a vector of integer values whose element type is the result/start type. The third argument is the vector mask and is a vector of boolean values with the same number of elements as the vector argument. The fourth argument is the explicit vector length of the operation.

<a id="id1281"></a>

##### Semantics:

The ‘`llvm.vp.reduce.smin`’ intrinsic performs the signed-integer `MIN` reduction ([llvm.vector.reduce.smin](#int-vector-reduce-smin)) of the vector argument `val` on each enabled lane, and taking the minimum of that and the scalar `start_value`. Disabled lanes are treated as containing the neutral value `INT_MAX` (i.e., having no effect on the reduction operation). If the vector length is zero, the result is the start value.

To ignore the start value, the neutral value can be used.

<a id="id1282"></a>

##### Examples:

    %r = call i8 @llvm.vp.reduce.smin.v4i8(i8 %start, <4 x i8> %a, <4 x i1> %mask, i32 %evl)
    ; %r is equivalent to %also.r, where lanes greater than or equal to %evl
    ; are treated as though %mask were false for those lanes.

    %masked.a = select <4 x i1> %mask, <4 x i8> %a, <4 x i8> <i8 127, i8 127, i8 127, i8 127>
    %reduction = call i8 @llvm.vector.reduce.smin.v4i8(<4 x i8> %masked.a)
    %also.r = call i8 @llvm.smin.i8(i8 %reduction, i8 %start)

<a id="llvm-vp-reduce-umax-intrinsics"></a>

<a id="int-vp-reduce-umax"></a>

#### ‘`llvm.vp.reduce.umax.*`’ Intrinsics

<a id="id1283"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare i32 @llvm.vp.reduce.umax.v4i32(i32 <start_value>, <4 x i32> <val>, <4 x i1> <mask>, i32 <vector_length>)
    declare i16 @llvm.vp.reduce.umax.nxv8i16(i16 <start_value>, <vscale x 8 x i16> <val>, <vscale x 8 x i1> <mask>, i32 <vector_length>)

<a id="id1284"></a>

##### Overview:

Predicated unsigned-integer `MAX` reduction of a vector and a scalar starting value, returning the result as a scalar.

<a id="id1285"></a>

##### Arguments:

The first argument is the start value of the reduction, which must be a scalar integer type equal to the result type. The second argument is the vector on which the reduction is performed and must be a vector of integer values whose element type is the result/start type. The third argument is the vector mask and is a vector of boolean values with the same number of elements as the vector argument. The fourth argument is the explicit vector length of the operation.

<a id="id1286"></a>

##### Semantics:

The ‘`llvm.vp.reduce.umax`’ intrinsic performs the unsigned-integer `MAX` reduction ([llvm.vector.reduce.umax](#int-vector-reduce-umax)) of the vector argument `val` on each enabled lane, and taking the maximum of that and the scalar `start_value`. Disabled lanes are treated as containing the neutral value `0` (i.e., having no effect on the reduction operation). If the vector length is zero, the result is the start value.

To ignore the start value, the neutral value can be used.

<a id="id1287"></a>

##### Examples:

    %r = call i32 @llvm.vp.reduce.umax.v4i32(i32 %start, <4 x i32> %a, <4 x i1> %mask, i32 %evl)
    ; %r is equivalent to %also.r, where lanes greater than or equal to %evl
    ; are treated as though %mask were false for those lanes.

    %masked.a = select <4 x i1> %mask, <4 x i32> %a, <4 x i32> <i32 0, i32 0, i32 0, i32 0>
    %reduction = call i32 @llvm.vector.reduce.umax.v4i32(<4 x i32> %masked.a)
    %also.r = call i32 @llvm.umax.i32(i32 %reduction, i32 %start)

<a id="llvm-vp-reduce-umin-intrinsics"></a>

<a id="int-vp-reduce-umin"></a>

#### ‘`llvm.vp.reduce.umin.*`’ Intrinsics

<a id="id1288"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare i32 @llvm.vp.reduce.umin.v4i32(i32 <start_value>, <4 x i32> <val>, <4 x i1> <mask>, i32 <vector_length>)
    declare i16 @llvm.vp.reduce.umin.nxv8i16(i16 <start_value>, <vscale x 8 x i16> <val>, <vscale x 8 x i1> <mask>, i32 <vector_length>)

<a id="id1289"></a>

##### Overview:

Predicated unsigned-integer `MIN` reduction of a vector and a scalar starting value, returning the result as a scalar.

<a id="id1290"></a>

##### Arguments:

The first argument is the start value of the reduction, which must be a scalar integer type equal to the result type. The second argument is the vector on which the reduction is performed and must be a vector of integer values whose element type is the result/start type. The third argument is the vector mask and is a vector of boolean values with the same number of elements as the vector argument. The fourth argument is the explicit vector length of the operation.

<a id="id1291"></a>

##### Semantics:

The ‘`llvm.vp.reduce.umin`’ intrinsic performs the unsigned-integer `MIN` reduction ([llvm.vector.reduce.umin](#int-vector-reduce-umin)) of the vector argument `val` on each enabled lane, taking the minimum of that and the scalar `start_value`. Disabled lanes are treated as containing the neutral value `UINT_MAX`, or `-1` (i.e., having no effect on the reduction operation). If the vector length is zero, the result is the start value.

To ignore the start value, the neutral value can be used.

<a id="id1292"></a>

##### Examples:

    %r = call i32 @llvm.vp.reduce.umin.v4i32(i32 %start, <4 x i32> %a, <4 x i1> %mask, i32 %evl)
    ; %r is equivalent to %also.r, where lanes greater than or equal to %evl
    ; are treated as though %mask were false for those lanes.

    %masked.a = select <4 x i1> %mask, <4 x i32> %a, <4 x i32> <i32 -1, i32 -1, i32 -1, i32 -1>
    %reduction = call i32 @llvm.vector.reduce.umin.v4i32(<4 x i32> %masked.a)
    %also.r = call i32 @llvm.umin.i32(i32 %reduction, i32 %start)

<a id="llvm-vp-reduce-fmax-intrinsics"></a>

<a id="int-vp-reduce-fmax"></a>

#### ‘`llvm.vp.reduce.fmax.*`’ Intrinsics

<a id="id1293"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare float @llvm.vp.reduce.fmax.v4f32(float <start_value>, <4 x float> <val>, <4 x i1> <mask>, i32 <vector_length>)
    declare double @llvm.vp.reduce.fmax.nxv8f64(double <start_value>, <vscale x 8 x double> <val>, <vscale x 8 x i1> <mask>, i32 <vector_length>)

<a id="id1294"></a>

##### Overview:

Predicated floating-point `MAX` reduction of a vector and a scalar starting value, returning the result as a scalar.

<a id="id1295"></a>

##### Arguments:

The first argument is the start value of the reduction, which must be a scalar floating-point type equal to the result type. The second argument is the vector on which the reduction is performed and must be a vector of floating-point values whose element type is the result/start type. The third argument is the vector mask and is a vector of boolean values with the same number of elements as the vector argument. The fourth argument is the explicit vector length of the operation.

<a id="id1296"></a>

##### Semantics:

The ‘`llvm.vp.reduce.fmax`’ intrinsic performs the floating-point `MAX` reduction ([llvm.vector.reduce.fmax](#int-vector-reduce-fmax)) of the vector argument `val` on each enabled lane, taking the maximum of that and the scalar `start_value`. Disabled lanes are treated as containing the neutral value (i.e., having no effect on the reduction operation). If the vector length is zero, the result is the start value.

The neutral value is dependent on the [fast-math flags](high-level-structure.md#fastmath). If no flags are set, the neutral value is `-QNAN`. If `nnan` and `ninf` are both set, then the neutral value is the smallest floating-point value for the result type. If only `nnan` is set then the neutral value is `-Infinity`.

This instruction has the same comparison semantics as the [llvm.vector.reduce.fmax](#int-vector-reduce-fmax) intrinsic (and thus the ‘`llvm.maxnum.*`’ intrinsic).

To ignore the start value, the neutral value can be used.

<a id="id1297"></a>

##### Examples:

    %r = call float @llvm.vp.reduce.fmax.v4f32(float %float, <4 x float> %a, <4 x i1> %mask, i32 %evl)
    ; %r is equivalent to %also.r, where lanes greater than or equal to %evl
    ; are treated as though %mask were false for those lanes.

    %masked.a = select <4 x i1> %mask, <4 x float> %a, <4 x float> <float QNAN, float QNAN, float QNAN, float QNAN>
    %reduction = call float @llvm.vector.reduce.fmax.v4f32(<4 x float> %masked.a)
    %also.r = call float @llvm.maxnum.f32(float %reduction, float %start)

<a id="llvm-vp-reduce-fmin-intrinsics"></a>

<a id="int-vp-reduce-fmin"></a>

#### ‘`llvm.vp.reduce.fmin.*`’ Intrinsics

<a id="id1298"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare float @llvm.vp.reduce.fmin.v4f32(float <start_value>, <4 x float> <val>, <4 x i1> <mask>, i32 <vector_length>)
    declare double @llvm.vp.reduce.fmin.nxv8f64(double <start_value>, <vscale x 8 x double> <val>, <vscale x 8 x i1> <mask>, i32 <vector_length>)

<a id="id1299"></a>

##### Overview:

Predicated floating-point `MIN` reduction of a vector and a scalar starting value, returning the result as a scalar.

<a id="id1300"></a>

##### Arguments:

The first argument is the start value of the reduction, which must be a scalar floating-point type equal to the result type. The second argument is the vector on which the reduction is performed and must be a vector of floating-point values whose element type is the result/start type. The third argument is the vector mask and is a vector of boolean values with the same number of elements as the vector argument. The fourth argument is the explicit vector length of the operation.

<a id="id1301"></a>

##### Semantics:

The ‘`llvm.vp.reduce.fmin`’ intrinsic performs the floating-point `MIN` reduction ([llvm.vector.reduce.fmin](#int-vector-reduce-fmin)) of the vector argument `val` on each enabled lane, taking the minimum of that and the scalar `start_value`. Disabled lanes are treated as containing the neutral value (i.e., having no effect on the reduction operation). If the vector length is zero, the result is the start value.

The neutral value is dependent on the [fast-math flags](high-level-structure.md#fastmath). If no flags are set, the neutral value is `+QNAN`. If `nnan` and `ninf` are both set, then the neutral value is the largest floating-point value for the result type. If only `nnan` is set then the neutral value is `+Infinity`.

This instruction has the same comparison semantics as the [llvm.vector.reduce.fmin](#int-vector-reduce-fmin) intrinsic (and thus the ‘`llvm.minnum.*`’ intrinsic).

To ignore the start value, the neutral value can be used.

<a id="id1302"></a>

##### Examples:

    %r = call float @llvm.vp.reduce.fmin.v4f32(float %start, <4 x float> %a, <4 x i1> %mask, i32 %evl)
    ; %r is equivalent to %also.r, where lanes greater than or equal to %evl
    ; are treated as though %mask were false for those lanes.

    %masked.a = select <4 x i1> %mask, <4 x float> %a, <4 x float> <float QNAN, float QNAN, float QNAN, float QNAN>
    %reduction = call float @llvm.vector.reduce.fmin.v4f32(<4 x float> %masked.a)
    %also.r = call float @llvm.minnum.f32(float %reduction, float %start)

<a id="llvm-vp-reduce-fmaximum-intrinsics"></a>

<a id="int-vp-reduce-fmaximum"></a>

#### ‘`llvm.vp.reduce.fmaximum.*`’ Intrinsics

<a id="id1303"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare float @llvm.vp.reduce.fmaximum.v4f32(float <start_value>, <4 x float> <val>, <4 x i1> <mask>, i32 <vector_length>)
    declare double @llvm.vp.reduce.fmaximum.nxv8f64(double <start_value>, <vscale x 8 x double> <val>, <vscale x 8 x i1> <mask>, i32 <vector_length>)

<a id="id1304"></a>

##### Overview:

Predicated floating-point `MAX` reduction of a vector and a scalar starting value, returning the result as a scalar.

<a id="id1305"></a>

##### Arguments:

The first argument is the start value of the reduction, which must be a scalar floating-point type equal to the result type. The second argument is the vector on which the reduction is performed and must be a vector of floating-point values whose element type is the result/start type. The third argument is the vector mask and is a vector of boolean values with the same number of elements as the vector argument. The fourth argument is the explicit vector length of the operation.

<a id="id1306"></a>

##### Semantics:

The ‘`llvm.vp.reduce.fmaximum`’ intrinsic performs the floating-point `MAX` reduction ([llvm.vector.reduce.fmaximum](#int-vector-reduce-fmaximum)) of the vector argument `val` on each enabled lane, taking the maximum of that and the scalar `start_value`. Disabled lanes are treated as containing the neutral value (i.e., having no effect on the reduction operation). If the vector length is zero, the result is the start value.

The neutral value is dependent on the [fast-math flags](high-level-structure.md#fastmath). If no flags are set or only the `nnan` is set, the neutral value is `-Infinity`. If `ninf` is set, then the neutral value is the smallest floating-point value for the result type.

This instruction has the same comparison semantics as the [llvm.vector.reduce.fmaximum](#int-vector-reduce-fmaximum) intrinsic (and thus the ‘`llvm.maximum.*`’ intrinsic). That is, the result will always be a number unless any of the elements in the vector or the starting value is `NaN`. Namely, this intrinsic propagates `NaN`. Also, -0.0 is considered less than +0.0.

To ignore the start value, the neutral value can be used.

<a id="id1307"></a>

##### Examples:

    %r = call float @llvm.vp.reduce.fmaximum.v4f32(float %float, <4 x float> %a, <4 x i1> %mask, i32 %evl)
    ; %r is equivalent to %also.r, where lanes greater than or equal to %evl
    ; are treated as though %mask were false for those lanes.

    %masked.a = select <4 x i1> %mask, <4 x float> %a, <4 x float> <float -infinity, float -infinity, float -infinity, float -infinity>
    %reduction = call float @llvm.vector.reduce.fmaximum.v4f32(<4 x float> %masked.a)
    %also.r = call float @llvm.maximum.f32(float %reduction, float %start)

<a id="llvm-vp-reduce-fminimum-intrinsics"></a>

<a id="int-vp-reduce-fminimum"></a>

#### ‘`llvm.vp.reduce.fminimum.*`’ Intrinsics

<a id="id1308"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare float @llvm.vp.reduce.fminimum.v4f32(float <start_value>, <4 x float> <val>, <4 x i1> <mask>, i32 <vector_length>)
    declare double @llvm.vp.reduce.fminimum.nxv8f64(double <start_value>, <vscale x 8 x double> <val>, <vscale x 8 x i1> <mask>, i32 <vector_length>)

<a id="id1309"></a>

##### Overview:

Predicated floating-point `MIN` reduction of a vector and a scalar starting value, returning the result as a scalar.

<a id="id1310"></a>

##### Arguments:

The first argument is the start value of the reduction, which must be a scalar floating-point type equal to the result type. The second argument is the vector on which the reduction is performed and must be a vector of floating-point values whose element type is the result/start type. The third argument is the vector mask and is a vector of boolean values with the same number of elements as the vector argument. The fourth argument is the explicit vector length of the operation.

<a id="id1311"></a>

##### Semantics:

The ‘`llvm.vp.reduce.fminimum`’ intrinsic performs the floating-point `MIN` reduction ([llvm.vector.reduce.fminimum](#int-vector-reduce-fminimum)) of the vector argument `val` on each enabled lane, taking the minimum of that and the scalar `start_value`. Disabled lanes are treated as containing the neutral value (i.e., having no effect on the reduction operation). If the vector length is zero, the result is the start value.

The neutral value is dependent on the [fast-math flags](high-level-structure.md#fastmath). If no flags are set or only the `nnan` is set, the neutral value is `+Infinity`. If `ninf` is set, then the neutral value is the largest floating-point value for the result type.

This instruction has the same comparison semantics as the [llvm.vector.reduce.fminimum](#int-vector-reduce-fminimum) intrinsic (and thus the ‘`llvm.minimum.*`’ intrinsic). That is, the result will always be a number unless any of the elements in the vector or the starting value is `NaN`. Namely, this intrinsic propagates `NaN`. Also, -0.0 is considered less than +0.0.

To ignore the start value, the neutral value can be used.

<a id="id1312"></a>

##### Examples:

    %r = call float @llvm.vp.reduce.fminimum.v4f32(float %start, <4 x float> %a, <4 x i1> %mask, i32 %evl)
    ; %r is equivalent to %also.r, where lanes greater than or equal to %evl
    ; are treated as though %mask were false for those lanes.

    %masked.a = select <4 x i1> %mask, <4 x float> %a, <4 x float> <float infinity, float infinity, float infinity, float infinity>
    %reduction = call float @llvm.vector.reduce.fminimum.v4f32(<4 x float> %masked.a)
    %also.r = call float @llvm.minimum.f32(float %reduction, float %start)

<a id="llvm-experimental-vp-splice-intrinsic"></a>

<a id="int-experimental-vp-splice"></a>

#### ‘`llvm.experimental.vp.splice`’ Intrinsic

<a id="id1313"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <2 x double> @llvm.experimental.vp.splice.v2f64(<2 x double> %vec1, <2 x double> %vec2, i32 %imm, <2 x i1> %mask, i32 %evl1, i32 %evl2)
    declare <vscale x 4 x i32> @llvm.experimental.vp.splice.nxv4i32(<vscale x 4 x i32> %vec1, <vscale x 4 x i32> %vec2, i32 %imm, <vscale x 4 x i1> %mask, i32 %evl1, i32 %evl2)

<a id="id1314"></a>

##### Overview:

The ‘`llvm.experimental.vp.splice.*`’ intrinsic is the vector length predicated version of the ‘`llvm.vector.splice.*`’ intrinsic.

<a id="id1315"></a>

##### Arguments:

The result and the first two arguments `vec1` and `vec2` are vectors with the same type. The third argument `imm` is an immediate signed integer that indicates the offset index. The fourth argument `mask` is a vector mask and has the same number of elements as the result. The last two arguments `evl1` and `evl2` are unsigned integers indicating the explicit vector lengths of `vec1` and `vec2` respectively. `imm`, `evl1` and `evl2` should respect the following constraints: `-evl1 <= imm < evl1`, `0 <= evl1 <= VL` and `0 <= evl2 <= VL`, where `VL` is the runtime vector factor. If these constraints are not satisfied the intrinsic has undefined behavior.

<a id="id1316"></a>

##### Semantics:

Effectively, this intrinsic concatenates `vec1[0..evl1-1]` and `vec2[0..evl2-1]` and creates the result vector by selecting the elements in a window of size `evl2`, starting at index `imm` (for a positive immediate) of the concatenated vector. Elements in the result vector beyond `evl2` are `undef`. If `imm` is negative the starting index is `evl1 + imm`. The result vector of active vector length `evl2` contains `evl1 - imm` (`-imm` for negative `imm`) elements from indices `[imm..evl1 - 1]` (`[evl1 + imm..evl1 -1]` for negative `imm`) of `vec1` followed by the first `evl2 - (evl1 - imm)` (`evl2 + imm` for negative `imm`) elements of `vec2`. If `evl1 - imm` (`-imm`) \>= `evl2`, only the first `evl2` elements are considered and the remaining are `undef`. The lanes in the result vector disabled by `mask` are `poison`.

<a id="id1317"></a>

##### Examples:

    llvm.experimental.vp.splice(<A,B,C,D>, <E,F,G,H>, 1, 2, 3);  ==> <B, E, F, poison> index
    llvm.experimental.vp.splice(<A,B,C,D>, <E,F,G,H>, -2, 3, 2); ==> <B, C, poison, poison> trailing elements

<a id="llvm-experimental-vp-reverse-intrinsic"></a>

<a id="int-experimental-vp-reverse"></a>

#### ‘`llvm.experimental.vp.reverse`’ Intrinsic

<a id="id1318"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <2 x double> @llvm.experimental.vp.reverse.v2f64(<2 x double> %vec, <2 x i1> %mask, i32 %evl)
    declare <vscale x 4 x i32> @llvm.experimental.vp.reverse.nxv4i32(<vscale x 4 x i32> %vec, <vscale x 4 x i1> %mask, i32 %evl)

<a id="id1319"></a>

##### Overview:

The ‘`llvm.experimental.vp.reverse.*`’ intrinsic is the vector length predicated version of the ‘`llvm.vector.reverse.*`’ intrinsic.

<a id="id1320"></a>

##### Arguments:

The result and the first argument `vec` are vectors with the same type. The second argument `mask` is a vector mask and has the same number of elements as the result. The third argument is the explicit vector length of the operation.

<a id="id1321"></a>

##### Semantics:

This intrinsic reverses the order of the first `evl` elements in a vector. The lanes in the result vector disabled by `mask` are `poison`. The elements past `evl` are poison.

<a id="llvm-vp-load-intrinsic"></a>

<a id="int-vp-load"></a>

#### ‘`llvm.vp.load`’ Intrinsic

<a id="id1322"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <4 x float> @llvm.vp.load.v4f32.p0(ptr %ptr, <4 x i1> %mask, i32 %evl)
    declare <vscale x 2 x i16> @llvm.vp.load.nxv2i16.p0(ptr %ptr, <vscale x 2 x i1> %mask, i32 %evl)
    declare <8 x float> @llvm.vp.load.v8f32.p1(ptr addrspace(1) %ptr, <8 x i1> %mask, i32 %evl)
    declare <vscale x 1 x i64> @llvm.vp.load.nxv1i64.p6(ptr addrspace(6) %ptr, <vscale x 1 x i1> %mask, i32 %evl)

<a id="id1323"></a>

##### Overview:

The ‘`llvm.vp.load.*`’ intrinsic is the vector length predicated version of the [llvm.masked.load](#int-mload) intrinsic.

<a id="id1324"></a>

##### Arguments:

The first argument is the base pointer for the load. The second argument is a vector of boolean values with the same number of elements as the return type. The third is the explicit vector length of the operation. The return type and underlying type of the base pointer are the same vector types.

The [align](high-level-structure.md#attr-align) parameter attribute can be provided for the first argument.

<a id="id1325"></a>

##### Semantics:

The ‘`llvm.vp.load`’ intrinsic reads a vector from memory in the same way as the ‘`llvm.masked.load`’ intrinsic, where the mask is taken from the combination of the ‘`mask`’ and ‘`evl`’ arguments in the usual VP way. Certain ‘`llvm.masked.load`’ arguments do not have corresponding arguments in ‘`llvm.vp.load`’: the ‘`passthru`’ argument is implicitly `poison`; the ‘`alignment`’ argument is taken as the `align` parameter attribute, if provided. The default alignment is taken as the ABI alignment of the return type as specified by the [datalayout string](high-level-structure.md#langref-datalayout).

<a id="id1326"></a>

##### Examples:

    %r = call <8 x i8> @llvm.vp.load.v8i8.p0(ptr align 2 %ptr, <8 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %also.r = call <8 x i8> @llvm.masked.load.v8i8.p0(ptr align 2 %ptr, <8 x i1> %mask, <8 x i8> poison)

<a id="llvm-vp-load-ff-intrinsic"></a>

<a id="int-vp-load-ff"></a>

#### ‘`llvm.vp.load.ff`’ Intrinsic

<a id="id1327"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare {<4 x float>, i32} @llvm.vp.load.ff.v4f32.p0(ptr %ptr, <4 x i1> %mask, i32 %evl)
    declare {<vscale x 2 x i16>, i32} @llvm.vp.load.ff.nxv2i16.p0(ptr %ptr, <vscale x 2 x i1> %mask, i32 %evl)
    declare {<8 x float>, i32} @llvm.vp.load.ff.v8f32.p1(ptr addrspace(1) %ptr, <8 x i1> %mask, i32 %evl)
    declare {<vscale x 1 x i64>, i32} @llvm.vp.load.ff.nxv1i64.p6(ptr addrspace(6) %ptr, <vscale x 1 x i1> %mask, i32 %evl)

<a id="id1328"></a>

##### Overview:

The ‘`llvm.vp.load.ff.*`’ intrinsic is similar to ‘`llvm.vp.load.*`’, but will not trap if there are not `evl` readable lanes at the pointer. ‘`ff`’ stands for first-fault or fault-only-first.

<a id="id1329"></a>

##### Arguments:

The first argument is the base pointer for the load. The second argument is a vector of boolean values with the same number of elements as the first return type. The third is the explicit vector length of the operation. The first return type and underlying type of the base pointer are the same vector types.

The [align](high-level-structure.md#attr-align) parameter attribute can be provided for the first argument.

<a id="id1330"></a>

##### Semantics:

The ‘`llvm.vp.load.ff`’ is designed for reading vector lanes in a single IR operation where the number of lanes that can be read is not known and can only be determined by looking at the data. This is useful for vectorizing strcmp or strlen like loops where the data contains a null terminator. Some targets have a fault-only-first load instruction that this intrinsic can be lowered to. Other targets may support this intrinsic differently, for example by lowering to a single scalar load guarded by `evl!=0` and `mask[0]==1` and indicating only 1 lane could be read.

Like ‘`llvm.vp.load`’, this intrinsic reads memory based on a `mask` and an `evl`. If `evl` is non-zero and the first lane is masked-on, then the first lane of the vector needs to be inbounds of an allocation. The remaining masked-on lanes with index less than `evl` do not need to be inbounds of an the same allocation or any allocation.

The second return value from the intrinsic indicates the index of the first lane that could not be read for some reason or `evl` if all lanes could be be read. Lanes at this index or higher in the first return value are [poison value](constants.md#poisonvalues). If `evl` is non-zero, the result in the second return value must be at least 1, even if the first lane is masked-off.

The second result is usually less than `evl` when an exception would occur for reading that lane, but it can be reduced for any reason. This facilitates emulating this intrinsic when the hardware only supports narrower vector types natively or when when hardware does not support fault-only-first loads.

Masked-on lanes that are not inbounds of the allocation that contains the first lane are [poison value](constants.md#poisonvalues). There should be a marker in the allocation that indicates where valid data stops such as a null terminator. The terminator should be checked for after calling this intrinsic to prevent using any lanes past the terminator. Even if second return value is less than `evl`, the terminator value may not have been read.

This intrinsic will typically be called in a loop until a terminator is found. The second result should be used to indicates how many elements are valid to look for the null terminator. If the terminator is not found, the pointer should be advanced by the number of elements in the second result and the intrinsic called again.

The default alignment is taken as the ABI alignment of the first return type as specified by the [datalayout string](high-level-structure.md#langref-datalayout).

<a id="id1331"></a>

##### Examples:

    %r = call {<8 x i8>, i32} @llvm.vp.load.ff.v8i8.p0(ptr align 2 %ptr, <8 x i1> %mask, i32 %evl)

<a id="llvm-vp-store-intrinsic"></a>

<a id="int-vp-store"></a>

#### ‘`llvm.vp.store`’ Intrinsic

<a id="id1332"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare void @llvm.vp.store.v4f32.p0(<4 x float> %val, ptr %ptr, <4 x i1> %mask, i32 %evl)
    declare void @llvm.vp.store.nxv2i16.p0(<vscale x 2 x i16> %val, ptr %ptr, <vscale x 2 x i1> %mask, i32 %evl)
    declare void @llvm.vp.store.v8f32.p1(<8 x float> %val, ptr addrspace(1) %ptr, <8 x i1> %mask, i32 %evl)
    declare void @llvm.vp.store.nxv1i64.p6(<vscale x 1 x i64> %val, ptr addrspace(6) %ptr, <vscale x 1 x i1> %mask, i32 %evl)

<a id="id1333"></a>

##### Overview:

The ‘`llvm.vp.store.*`’ intrinsic is the vector length predicated version of the [llvm.masked.store](#int-mstore) intrinsic.

<a id="id1334"></a>

##### Arguments:

The first argument is the vector value to be written to memory. The second argument is the base pointer for the store. It has the same underlying type as the value argument. The third argument is a vector of boolean values with the same number of elements as the return type. The fourth is the explicit vector length of the operation.

The [align](high-level-structure.md#attr-align) parameter attribute can be provided for the second argument.

<a id="id1335"></a>

##### Semantics:

The ‘`llvm.vp.store`’ intrinsic reads a vector from memory in the same way as the ‘`llvm.masked.store`’ intrinsic, where the mask is taken from the combination of the ‘`mask`’ and ‘`evl`’ arguments in the usual VP way. The alignment of the operation (corresponding to the ‘`alignment`’ argument of ‘`llvm.masked.store`’) is specified by the `align` parameter attribute (see above). If it is not provided then the ABI alignment of the type of the ‘`value`’ argument as specified by the [datalayout string](high-level-structure.md#langref-datalayout) is used instead.

<a id="id1336"></a>

##### Examples:

    call void @llvm.vp.store.v8i8.p0(<8 x i8> %val, ptr align 4 %ptr, <8 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, the call above is lane-wise equivalent to the call below.

    call void @llvm.masked.store.v8i8.p0(<8 x i8> %val, ptr %ptr, i32 4, <8 x i1> %mask)

<a id="llvm-experimental-vp-strided-load-intrinsic"></a>

<a id="int-experimental-vp-strided-load"></a>

#### ‘`llvm.experimental.vp.strided.load`’ Intrinsic

<a id="id1337"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <4 x float> @llvm.experimental.vp.strided.load.v4f32.i64(ptr %ptr, i64 %stride, <4 x i1> %mask, i32 %evl)
    declare <vscale x 2 x i16> @llvm.experimental.vp.strided.load.nxv2i16.i64(ptr %ptr, i64 %stride, <vscale x 2 x i1> %mask, i32 %evl)

<a id="id1338"></a>

##### Overview:

The ‘`llvm.experimental.vp.strided.load`’ intrinsic loads, into a vector, scalar values from memory locations evenly spaced apart by ‘`stride`’ number of bytes, starting from ‘`ptr`’.

<a id="id1339"></a>

##### Arguments:

The first argument is the base pointer for the load. The second argument is the stride value expressed in bytes. The third argument is a vector of boolean values with the same number of elements as the return type. The fourth is the explicit vector length of the operation. The base pointer underlying type matches the type of the scalar elements of the return argument.

The [align](high-level-structure.md#attr-align) parameter attribute can be provided for the first argument.

<a id="id1340"></a>

##### Semantics:

The ‘`llvm.experimental.vp.strided.load`’ intrinsic loads, into a vector, multiple scalar values from memory in the same way as the [llvm.vp.gather](#int-vp-gather) intrinsic, where the vector of pointers is in the form:

`%ptrs = <%ptr, %ptr + %stride, %ptr + 2 * %stride, ... >`,

with ‘`ptr`’ previously casted to a pointer ‘`i8`’, ‘`stride`’ always interpreted as a signed integer and all arithmetic occurring in the pointer type.

<a id="id1341"></a>

##### Examples:

    %r = call <8 x i64> @llvm.experimental.vp.strided.load.v8i64.i64(i64* %ptr, i64 %stride, <8 x i64> %mask, i32 %evl)
    ;; The operation can also be expressed like this:

    %addr = bitcast i64* %ptr to i8*
    ;; Create a vector of pointers %addrs in the form:
    ;; %addrs = <%addr, %addr + %stride, %addr + 2 * %stride, ...>
    %ptrs = bitcast <8 x i8* > %addrs to <8 x i64* >
    %also.r = call <8 x i64> @llvm.vp.gather.v8i64.v8p0i64(<8 x i64* > %ptrs, <8 x i64> %mask, i32 %evl)

<a id="llvm-experimental-vp-strided-store-intrinsic"></a>

<a id="int-experimental-vp-strided-store"></a>

#### ‘`llvm.experimental.vp.strided.store`’ Intrinsic

<a id="id1342"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare void @llvm.experimental.vp.strided.store.v4f32.i64(<4 x float> %val, ptr %ptr, i64 %stride, <4 x i1> %mask, i32 %evl)
    declare void @llvm.experimental.vp.strided.store.nxv2i16.i64(<vscale x 2 x i16> %val, ptr %ptr, i64 %stride, <vscale x 2 x i1> %mask, i32 %evl)

<a id="id1343"></a>

##### Overview:

The ‘`@llvm.experimental.vp.strided.store`’ intrinsic stores the elements of ‘`val`’ into memory locations evenly spaced apart by ‘`stride`’ number of bytes, starting from ‘`ptr`’.

<a id="id1344"></a>

##### Arguments:

The first argument is the vector value to be written to memory. The second argument is the base pointer for the store. Its underlying type matches the scalar element type of the value argument. The third argument is the stride value expressed in bytes. The fourth argument is a vector of boolean values with the same number of elements as the return type. The fifth is the explicit vector length of the operation.

The [align](high-level-structure.md#attr-align) parameter attribute can be provided for the second argument.

<a id="id1345"></a>

##### Semantics:

The ‘`llvm.experimental.vp.strided.store`’ intrinsic stores the elements of ‘`val`’ in the same way as the [llvm.vp.scatter](#int-vp-scatter) intrinsic, where the vector of pointers is in the form:

`%ptrs = <%ptr, %ptr + %stride, %ptr + 2 * %stride, ... >`,

with ‘`ptr`’ previously casted to a pointer ‘`i8`’, ‘`stride`’ always interpreted as a signed integer and all arithmetic occurring in the pointer type.

<a id="id1346"></a>

##### Examples:

    call void @llvm.experimental.vp.strided.store.v8i64.i64(<8 x i64> %val, i64* %ptr, i64 %stride, <8 x i1> %mask, i32 %evl)
    ;; The operation can also be expressed like this:

    %addr = bitcast i64* %ptr to i8*
    ;; Create a vector of pointers %addrs in the form:
    ;; %addrs = <%addr, %addr + %stride, %addr + 2 * %stride, ...>
    %ptrs = bitcast <8 x i8* > %addrs to <8 x i64* >
    call void @llvm.vp.scatter.v8i64.v8p0i64(<8 x i64> %val, <8 x i64*> %ptrs, <8 x i1> %mask, i32 %evl)

<a id="llvm-vp-gather-intrinsic"></a>

<a id="int-vp-gather"></a>

#### ‘`llvm.vp.gather`’ Intrinsic

<a id="id1347"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <4 x double> @llvm.vp.gather.v4f64.v4p0(<4 x ptr> %ptrs, <4 x i1> %mask, i32 %evl)
    declare <vscale x 2 x i8> @llvm.vp.gather.nxv2i8.nxv2p0(<vscale x 2 x ptr> %ptrs, <vscale x 2 x i1> %mask, i32 %evl)
    declare <2 x float> @llvm.vp.gather.v2f32.v2p2(<2 x ptr addrspace(2)> %ptrs, <2 x i1> %mask, i32 %evl)
    declare <vscale x 4 x i32> @llvm.vp.gather.nxv4i32.nxv4p4(<vscale x 4 x ptr addrspace(4)> %ptrs, <vscale x 4 x i1> %mask, i32 %evl)

<a id="id1348"></a>

##### Overview:

The ‘`llvm.vp.gather.*`’ intrinsic is the vector length predicated version of the [llvm.masked.gather](#int-mgather) intrinsic.

<a id="id1349"></a>

##### Arguments:

The first argument is a vector of pointers which holds all memory addresses to read. The second argument is a vector of boolean values with the same number of elements as the return type. The third is the explicit vector length of the operation. The return type and underlying type of the vector of pointers are the same vector types.

The [align](high-level-structure.md#attr-align) parameter attribute can be provided for the first argument.

<a id="id1350"></a>

##### Semantics:

The ‘`llvm.vp.gather`’ intrinsic reads multiple scalar values from memory in the same way as the ‘`llvm.masked.gather`’ intrinsic, where the mask is taken from the combination of the ‘`mask`’ and ‘`evl`’ arguments in the usual VP way. Certain ‘`llvm.masked.gather`’ arguments do not have corresponding arguments in ‘`llvm.vp.gather`’: the ‘`passthru`’ argument is implicitly `poison`; the ‘`alignment`’ argument is taken as the `align` parameter, if provided. The default alignment is taken as the ABI alignment of the source addresses as specified by the [datalayout string](high-level-structure.md#langref-datalayout).

<a id="id1351"></a>

##### Examples:

    %r = call <8 x i8> @llvm.vp.gather.v8i8.v8p0(<8 x ptr>  align 8 %ptrs, <8 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %also.r = call <8 x i8> @llvm.masked.gather.v8i8.v8p0(<8 x ptr> align 8 %ptrs, <8 x i1> %mask, <8 x i8> poison)

<a id="llvm-vp-scatter-intrinsic"></a>

<a id="int-vp-scatter"></a>

#### ‘`llvm.vp.scatter`’ Intrinsic

<a id="id1352"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare void @llvm.vp.scatter.v4f64.v4p0(<4 x double> %val, <4 x ptr> %ptrs, <4 x i1> %mask, i32 %evl)
    declare void @llvm.vp.scatter.nxv2i8.nxv2p0(<vscale x 2 x i8> %val, <vscale x 2 x ptr> %ptrs, <vscale x 2 x i1> %mask, i32 %evl)
    declare void @llvm.vp.scatter.v2f32.v2p2(<2 x float> %val, <2 x ptr addrspace(2)> %ptrs, <2 x i1> %mask, i32 %evl)
    declare void @llvm.vp.scatter.nxv4i32.nxv4p4(<vscale x 4 x i32> %val, <vscale x 4 x ptr addrspace(4)> %ptrs, <vscale x 4 x i1> %mask, i32 %evl)

<a id="id1353"></a>

##### Overview:

The ‘`llvm.vp.scatter.*`’ intrinsic is the vector length predicated version of the [llvm.masked.scatter](#int-mscatter) intrinsic.

<a id="id1354"></a>

##### Arguments:

The first argument is a vector value to be written to memory. The second argument is a vector of pointers, pointing to where the value elements should be stored. The third argument is a vector of boolean values with the same number of elements as the return type. The fourth is the explicit vector length of the operation.

The [align](high-level-structure.md#attr-align) parameter attribute can be provided for the second argument.

<a id="id1355"></a>

##### Semantics:

The ‘`llvm.vp.scatter`’ intrinsic writes multiple scalar values to memory in the same way as the ‘`llvm.masked.scatter`’ intrinsic, where the mask is taken from the combination of the ‘`mask`’ and ‘`evl`’ arguments in the usual VP way. The ‘`alignment`’ argument of the ‘`llvm.masked.scatter`’ does not have a corresponding argument in ‘`llvm.vp.scatter`’: it is instead provided via the optional `align` parameter attribute on the vector-of-pointers argument. Otherwise it is taken as the ABI alignment of the destination addresses as specified by the [datalayout string](high-level-structure.md#langref-datalayout).

<a id="id1356"></a>

##### Examples:

    call void @llvm.vp.scatter.v8i8.v8p0(<8 x i8> %val, <8 x ptr> align 1 %ptrs, <8 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, the call above is lane-wise equivalent to the call below.

    call void @llvm.masked.scatter.v8i8.v8p0(<8 x i8> %val, <8 x ptr> align 1 %ptrs, <8 x i1> %mask)

<a id="llvm-vp-trunc-intrinsics"></a>

<a id="int-vp-trunc"></a>

#### ‘`llvm.vp.trunc.*`’ Intrinsics

<a id="id1357"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i16>  @llvm.vp.trunc.v16i16.v16i32 (<16 x i32> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i16>  @llvm.vp.trunc.nxv4i16.nxv4i32 (<vscale x 4 x i32> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)

<a id="id1358"></a>

##### Overview:

The ‘`llvm.vp.trunc`’ intrinsic truncates its first argument to the return type. The operation has a mask and an explicit vector length parameter.

<a id="id1359"></a>

##### Arguments:

The ‘`llvm.vp.trunc`’ intrinsic takes a value to cast as its first argument. The return type is the type to cast the value to. Both types must be vector of [integer](type-system.md#t-integer) type. The bit size of the value must be larger than the bit size of the return type. The second argument is the vector mask. The return type, the value to cast, and the vector mask have the same number of elements. The third argument is the explicit vector length of the operation.

<a id="id1360"></a>

##### Semantics:

The ‘`llvm.vp.trunc`’ intrinsic truncates the high order bits in value and converts the remaining bits to return type. Since the source size must be larger than the destination size, ‘`llvm.vp.trunc`’ cannot be a *no-op cast*. It will always truncate bits. The conversion is performed on lane positions below the explicit vector length and where the vector mask is true. Masked-off lanes are `poison`.

<a id="id1361"></a>

##### Examples:

    %r = call <4 x i16> @llvm.vp.trunc.v4i16.v4i32(<4 x i32> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = trunc <4 x i32> %a to <4 x i16>
    %also.r = select <4 x i1> %mask, <4 x i16> %t, <4 x i16> poison

<a id="llvm-vp-zext-intrinsics"></a>

<a id="int-vp-zext"></a>

#### ‘`llvm.vp.zext.*`’ Intrinsics

<a id="id1362"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.zext.v16i32.v16i16 (<16 x i16> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.zext.nxv4i32.nxv4i16 (<vscale x 4 x i16> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)

<a id="id1363"></a>

##### Overview:

The ‘`llvm.vp.zext`’ intrinsic zero extends its first argument to the return type. The operation has a mask and an explicit vector length parameter.

<a id="id1364"></a>

##### Arguments:

The ‘`llvm.vp.zext`’ intrinsic takes a value to cast as its first argument. The return type is the type to cast the value to. Both types must be vectors of [integer](type-system.md#t-integer) type. The bit size of the value must be smaller than the bit size of the return type. The second argument is the vector mask. The return type, the value to cast, and the vector mask have the same number of elements. The third argument is the explicit vector length of the operation.

<a id="id1365"></a>

##### Semantics:

The ‘`llvm.vp.zext`’ intrinsic fill the high order bits of the value with zero bits until it reaches the size of the return type. When zero extending from i1, the result will always be either 0 or 1. The conversion is performed on lane positions below the explicit vector length and where the vector mask is true. Masked-off lanes are `poison`.

<a id="id1366"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.zext.v4i32.v4i16(<4 x i16> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = zext <4 x i16> %a to <4 x i32>
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-sext-intrinsics"></a>

<a id="int-vp-sext"></a>

#### ‘`llvm.vp.sext.*`’ Intrinsics

<a id="id1367"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.sext.v16i32.v16i16 (<16 x i16> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.sext.nxv4i32.nxv4i16 (<vscale x 4 x i16> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)

<a id="id1368"></a>

##### Overview:

The ‘`llvm.vp.sext`’ intrinsic sign extends its first argument to the return type. The operation has a mask and an explicit vector length parameter.

<a id="id1369"></a>

##### Arguments:

The ‘`llvm.vp.sext`’ intrinsic takes a value to cast as its first argument. The return type is the type to cast the value to. Both types must be vectors of [integer](type-system.md#t-integer) type. The bit size of the value must be smaller than the bit size of the return type. The second argument is the vector mask. The return type, the value to cast, and the vector mask have the same number of elements. The third argument is the explicit vector length of the operation.

<a id="id1370"></a>

##### Semantics:

The ‘`llvm.vp.sext`’ intrinsic performs a sign extension by copying the sign bit (highest order bit) of the value until it reaches the size of the return type. When sign extending from i1, the result will always be either -1 or 0. The conversion is performed on lane positions below the explicit vector length and where the vector mask is true. Masked-off lanes are `poison`.

<a id="id1371"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.sext.v4i32.v4i16(<4 x i16> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = sext <4 x i16> %a to <4 x i32>
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-fptrunc-intrinsics"></a>

<a id="int-vp-fptrunc"></a>

#### ‘`llvm.vp.fptrunc.*`’ Intrinsics

<a id="id1372"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.fptrunc.v16f32.v16f64 (<16 x double> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.trunc.nxv4f32.nxv4f64 (<vscale x 4 x double> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)

<a id="id1373"></a>

##### Overview:

The ‘`llvm.vp.fptrunc`’ intrinsic truncates its first argument to the return type. The operation has a mask and an explicit vector length parameter.

<a id="id1374"></a>

##### Arguments:

The ‘`llvm.vp.fptrunc`’ intrinsic takes a value to cast as its first argument. The return type is the type to cast the value to. Both types must be vector of [floating-point](type-system.md#t-floating) type. The bit size of the value must be larger than the bit size of the return type. This implies that ‘`llvm.vp.fptrunc`’ cannot be used to make a *no-op cast*. The second argument is the vector mask. The return type, the value to cast, and the vector mask have the same number of elements. The third argument is the explicit vector length of the operation.

<a id="id1375"></a>

##### Semantics:

The ‘`llvm.vp.fptrunc`’ intrinsic casts a `value` from a larger [floating-point](type-system.md#t-floating) type to a smaller [floating-point](type-system.md#t-floating) type. This instruction is assumed to execute in the default [floating-point environment](high-level-structure.md#floatenv). The conversion is performed on lane positions below the explicit vector length and where the vector mask is true. Masked-off lanes are `poison`.

<a id="id1376"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.fptrunc.v4f32.v4f64(<4 x double> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = fptrunc <4 x double> %a to <4 x float>
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-fpext-intrinsics"></a>

<a id="int-vp-fpext"></a>

#### ‘`llvm.vp.fpext.*`’ Intrinsics

<a id="id1377"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x double>  @llvm.vp.fpext.v16f64.v16f32 (<16 x float> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x double>  @llvm.vp.fpext.nxv4f64.nxv4f32 (<vscale x 4 x float> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)

<a id="id1378"></a>

##### Overview:

The ‘`llvm.vp.fpext`’ intrinsic extends its first argument to the return type. The operation has a mask and an explicit vector length parameter.

<a id="id1379"></a>

##### Arguments:

The ‘`llvm.vp.fpext`’ intrinsic takes a value to cast as its first argument. The return type is the type to cast the value to. Both types must be vector of [floating-point](type-system.md#t-floating) type. The bit size of the value must be smaller than the bit size of the return type. This implies that ‘`llvm.vp.fpext`’ cannot be used to make a *no-op cast*. The second argument is the vector mask. The return type, the value to cast, and the vector mask have the same number of elements. The third argument is the explicit vector length of the operation.

<a id="id1380"></a>

##### Semantics:

The ‘`llvm.vp.fpext`’ intrinsic extends the `value` from a smaller [floating-point](type-system.md#t-floating) type to a larger [floating-point](type-system.md#t-floating) type. The ‘`llvm.vp.fpext`’ cannot be used to make a *no-op cast* because it always changes bits. Use `bitcast` to make a *no-op cast* for a floating-point cast. The conversion is performed on lane positions below the explicit vector length and where the vector mask is true. Masked-off lanes are `poison`.

<a id="id1381"></a>

##### Examples:

    %r = call <4 x double> @llvm.vp.fpext.v4f64.v4f32(<4 x float> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = fpext <4 x float> %a to <4 x double>
    %also.r = select <4 x i1> %mask, <4 x double> %t, <4 x double> poison

<a id="llvm-vp-fptoui-intrinsics"></a>

<a id="int-vp-fptoui"></a>

#### ‘`llvm.vp.fptoui.*`’ Intrinsics

<a id="id1382"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.fptoui.v16i32.v16f32 (<16 x float> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.fptoui.nxv4i32.nxv4f32 (<vscale x 4 x float> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.fptoui.v256i64.v256f64 (<256 x double> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1383"></a>

##### Overview:

The ‘`llvm.vp.fptoui`’ intrinsic converts the [floating-point](type-system.md#t-floating) argument to the unsigned integer return type. The operation has a mask and an explicit vector length parameter.

<a id="id1384"></a>

##### Arguments:

The ‘`llvm.vp.fptoui`’ intrinsic takes a value to cast as its first argument. The value to cast must be a vector of [floating-point](type-system.md#t-floating) type. The return type is the type to cast the value to. The return type must be vector of [integer](type-system.md#t-integer) type. The second argument is the vector mask. The return type, the value to cast, and the vector mask have the same number of elements. The third argument is the explicit vector length of the operation.

<a id="id1385"></a>

##### Semantics:

The ‘`llvm.vp.fptoui`’ intrinsic converts its [floating-point](type-system.md#t-floating) argument into the nearest (rounding towards zero) unsigned integer value where the lane position is below the explicit vector length and the vector mask is true. Masked-off lanes are `poison`. On enabled lanes where conversion takes place and the value cannot fit in the return type, the result on that lane is a [poison value](constants.md#poisonvalues).

<a id="id1386"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.fptoui.v4i32.v4f32(<4 x float> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = fptoui <4 x float> %a to <4 x i32>
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-fptosi-intrinsics"></a>

<a id="int-vp-fptosi"></a>

#### ‘`llvm.vp.fptosi.*`’ Intrinsics

<a id="id1387"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.fptosi.v16i32.v16f32 (<16 x float> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.fptosi.nxv4i32.nxv4f32 (<vscale x 4 x float> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.fptosi.v256i64.v256f64 (<256 x double> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1388"></a>

##### Overview:

The ‘`llvm.vp.fptosi`’ intrinsic converts the [floating-point](type-system.md#t-floating) argument to the signed integer return type. The operation has a mask and an explicit vector length parameter.

<a id="id1389"></a>

##### Arguments:

The ‘`llvm.vp.fptosi`’ intrinsic takes a value to cast as its first argument. The value to cast must be a vector of [floating-point](type-system.md#t-floating) type. The return type is the type to cast the value to. The return type must be vector of [integer](type-system.md#t-integer) type. The second argument is the vector mask. The return type, the value to cast, and the vector mask have the same number of elements. The third argument is the explicit vector length of the operation.

<a id="id1390"></a>

##### Semantics:

The ‘`llvm.vp.fptosi`’ intrinsic converts its [floating-point](type-system.md#t-floating) argument into the nearest (rounding towards zero) signed integer value where the lane position is below the explicit vector length and the vector mask is true. Masked-off lanes are `poison`. On enabled lanes where conversion takes place and the value cannot fit in the return type, the result on that lane is a [poison value](constants.md#poisonvalues).

<a id="id1391"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.fptosi.v4i32.v4f32(<4 x float> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = fptosi <4 x float> %a to <4 x i32>
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-uitofp-intrinsics"></a>

<a id="int-vp-uitofp"></a>

#### ‘`llvm.vp.uitofp.*`’ Intrinsics

<a id="id1392"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.uitofp.v16f32.v16i32 (<16 x i32> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.uitofp.nxv4f32.nxv4i32 (<vscale x 4 x i32> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.uitofp.v256f64.v256i64 (<256 x i64> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1393"></a>

##### Overview:

The ‘`llvm.vp.uitofp`’ intrinsic converts its unsigned integer argument to the [floating-point](type-system.md#t-floating) return type. The operation has a mask and an explicit vector length parameter.

<a id="id1394"></a>

##### Arguments:

The ‘`llvm.vp.uitofp`’ intrinsic takes a value to cast as its first argument. The value to cast must be vector of [integer](type-system.md#t-integer) type. The return type is the type to cast the value to. The return type must be a vector of [floating-point](type-system.md#t-floating) type. The second argument is the vector mask. The return type, the value to cast, and the vector mask have the same number of elements. The third argument is the explicit vector length of the operation.

<a id="id1395"></a>

##### Semantics:

The ‘`llvm.vp.uitofp`’ intrinsic interprets its first argument as an unsigned integer quantity and converts it to the corresponding floating-point value. If the value cannot be exactly represented, it is rounded using the default rounding mode. The conversion is performed on lane positions below the explicit vector length and where the vector mask is true. Masked-off lanes are `poison`.

<a id="id1396"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.uitofp.v4f32.v4i32(<4 x i32> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = uitofp <4 x i32> %a to <4 x float>
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-sitofp-intrinsics"></a>

<a id="int-vp-sitofp"></a>

#### ‘`llvm.vp.sitofp.*`’ Intrinsics

<a id="id1397"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.sitofp.v16f32.v16i32 (<16 x i32> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.sitofp.nxv4f32.nxv4i32 (<vscale x 4 x i32> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.sitofp.v256f64.v256i64 (<256 x i64> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1398"></a>

##### Overview:

The ‘`llvm.vp.sitofp`’ intrinsic converts its signed integer argument to the [floating-point](type-system.md#t-floating) return type. The operation has a mask and an explicit vector length parameter.

<a id="id1399"></a>

##### Arguments:

The ‘`llvm.vp.sitofp`’ intrinsic takes a value to cast as its first argument. The value to cast must be vector of [integer](type-system.md#t-integer) type. The return type is the type to cast the value to. The return type must be a vector of [floating-point](type-system.md#t-floating) type. The second argument is the vector mask. The return type, the value to cast, and the vector mask have the same number of elements. The third argument is the explicit vector length of the operation.

<a id="id1400"></a>

##### Semantics:

The ‘`llvm.vp.sitofp`’ intrinsic interprets its first argument as a signed integer quantity and converts it to the corresponding floating-point value. If the value cannot be exactly represented, it is rounded using the default rounding mode. The conversion is performed on lane positions below the explicit vector length and where the vector mask is true. Masked-off lanes are `poison`.

<a id="id1401"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.sitofp.v4f32.v4i32(<4 x i32> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = sitofp <4 x i32> %a to <4 x float>
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-ptrtoint-intrinsics"></a>

<a id="int-vp-ptrtoint"></a>

#### ‘`llvm.vp.ptrtoint.*`’ Intrinsics

<a id="id1402"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i8>  @llvm.vp.ptrtoint.v16i8.v16p0(<16 x ptr> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i8>  @llvm.vp.ptrtoint.nxv4i8.nxv4p0(<vscale x 4 x ptr> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.ptrtoint.v16i64.v16p0(<256 x ptr> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1403"></a>

##### Overview:

The ‘`llvm.vp.ptrtoint`’ intrinsic converts its pointer to the integer return type. The operation has a mask and an explicit vector length parameter.

<a id="id1404"></a>

##### Arguments:

The ‘`llvm.vp.ptrtoint`’ intrinsic takes a value to cast as its first argument , which must be a vector of pointers, and a type to cast it to return type, which must be a vector of [integer](type-system.md#t-integer) type. The second argument is the vector mask. The return type, the value to cast, and the vector mask have the same number of elements. The third argument is the explicit vector length of the operation.

<a id="id1405"></a>

##### Semantics:

The ‘`llvm.vp.ptrtoint`’ intrinsic converts value to return type by interpreting the pointer value as an integer and either truncating or zero extending that value to the size of the integer type. If `value` is smaller than return type, then a zero extension is done. If `value` is larger than return type, then a truncation is done. If they are the same size, then nothing is done (*no-op cast*) other than a type change. The conversion is performed on lane positions below the explicit vector length and where the vector mask is true. Masked-off lanes are `poison`.

<a id="id1406"></a>

##### Examples:

    %r = call <4 x i8> @llvm.vp.ptrtoint.v4i8.v4p0i32(<4 x ptr> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = ptrtoint <4 x ptr> %a to <4 x i8>
    %also.r = select <4 x i1> %mask, <4 x i8> %t, <4 x i8> poison

<a id="llvm-vp-inttoptr-intrinsics"></a>

<a id="int-vp-inttoptr"></a>

#### ‘`llvm.vp.inttoptr.*`’ Intrinsics

<a id="id1407"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x ptr>  @llvm.vp.inttoptr.v16p0.v16i32 (<16 x i32> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x ptr>  @llvm.vp.inttoptr.nxv4p0.nxv4i32 (<vscale x 4 x i32> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x ptr>  @llvm.vp.inttoptr.v256p0.v256i32 (<256 x i32> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1408"></a>

##### Overview:

The ‘`llvm.vp.inttoptr`’ intrinsic converts its integer value to the point return type. The operation has a mask and an explicit vector length parameter.

<a id="id1409"></a>

##### Arguments:

The ‘`llvm.vp.inttoptr`’ intrinsic takes a value to cast as its first argument , which must be a vector of [integer](type-system.md#t-integer) type, and a type to cast it to return type, which must be a vector of pointers type. The second argument is the vector mask. The return type, the value to cast, and the vector mask have the same number of elements. The third argument is the explicit vector length of the operation.

<a id="id1410"></a>

##### Semantics:

The ‘`llvm.vp.inttoptr`’ intrinsic converts `value` to return type by applying either a zero extension or a truncation depending on the size of the integer `value`. If `value` is larger than the size of a pointer, then a truncation is done. If `value` is smaller than the size of a pointer, then a zero extension is done. If they are the same size, nothing is done (*no-op cast*). The conversion is performed on lane positions below the explicit vector length and where the vector mask is true. Masked-off lanes are `poison`.

<a id="id1411"></a>

##### Examples:

    %r = call <4 x ptr> @llvm.vp.inttoptr.v4p0i32.v4i32(<4 x i32> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = inttoptr <4 x i32> %a to <4 x ptr>
    %also.r = select <4 x i1> %mask, <4 x ptr> %t, <4 x ptr> poison

<a id="llvm-vp-fcmp-intrinsics"></a>

<a id="int-vp-fcmp"></a>

#### ‘`llvm.vp.fcmp.*`’ Intrinsics

<a id="id1412"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i1> @llvm.vp.fcmp.v16f32(<16 x float> <left_op>, <16 x float> <right_op>, metadata <condition code>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i1> @llvm.vp.fcmp.nxv4f32(<vscale x 4 x float> <left_op>, <vscale x 4 x float> <right_op>, metadata <condition code>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i1> @llvm.vp.fcmp.v256f64(<256 x double> <left_op>, <256 x double> <right_op>, metadata <condition code>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1413"></a>

##### Overview:

The ‘`llvm.vp.fcmp`’ intrinsic returns a vector of boolean values based on the comparison of its arguments. The operation has a mask and an explicit vector length parameter.

<a id="id1414"></a>

##### Arguments:

The ‘`llvm.vp.fcmp`’ intrinsic takes the two values to compare as its first and second arguments. These two values must be vectors of [floating-point](type-system.md#t-floating) types. The return type is the result of the comparison. The return type must be a vector of [i1](type-system.md#t-integer) type. The fourth argument is the vector mask. The return type, the values to compare, and the vector mask have the same number of elements. The third argument is the condition code indicating the kind of comparison to perform. It must be a metadata string with [one of the supported floating-point condition code values](#fcmp-md-cc). The fifth argument is the explicit vector length of the operation.

<a id="id1415"></a>

##### Semantics:

The ‘`llvm.vp.fcmp`’ compares its first two arguments according to the condition code given as the third argument. The arguments are compared element by element on each enabled lane, where the semantics of the comparison are defined [according to the condition code](#fcmp-md-cc-sem). Masked-off lanes are `poison`.

<a id="id1416"></a>

##### Examples:

    %r = call <4 x i1> @llvm.vp.fcmp.v4f32(<4 x float> %a, <4 x float> %b, metadata !"oeq", <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = fcmp oeq <4 x float> %a, %b
    %also.r = select <4 x i1> %mask, <4 x i1> %t, <4 x i1> poison

<a id="llvm-vp-icmp-intrinsics"></a>

<a id="int-vp-icmp"></a>

#### ‘`llvm.vp.icmp.*`’ Intrinsics

<a id="id1417"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <32 x i1> @llvm.vp.icmp.v32i32(<32 x i32> <left_op>, <32 x i32> <right_op>, metadata <condition code>, <32 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 2 x i1> @llvm.vp.icmp.nxv2i32(<vscale x 2 x i32> <left_op>, <vscale x 2 x i32> <right_op>, metadata <condition code>, <vscale x 2 x i1> <mask>, i32 <vector_length>)
    declare <128 x i1> @llvm.vp.icmp.v128i8(<128 x i8> <left_op>, <128 x i8> <right_op>, metadata <condition code>, <128 x i1> <mask>, i32 <vector_length>)

<a id="id1418"></a>

##### Overview:

The ‘`llvm.vp.icmp`’ intrinsic returns a vector of boolean values based on the comparison of its arguments. The operation has a mask and an explicit vector length parameter.

<a id="id1419"></a>

##### Arguments:

The ‘`llvm.vp.icmp`’ intrinsic takes the two values to compare as its first and second arguments. These two values must be vectors of [integer](type-system.md#t-integer) types. The return type is the result of the comparison. The return type must be a vector of [i1](type-system.md#t-integer) type. The fourth argument is the vector mask. The return type, the values to compare, and the vector mask have the same number of elements. The third argument is the condition code indicating the kind of comparison to perform. It must be a metadata string with [one of the supported integer condition code values](#icmp-md-cc). The fifth argument is the explicit vector length of the operation.

<a id="id1420"></a>

##### Semantics:

The ‘`llvm.vp.icmp`’ compares its first two arguments according to the condition code given as the third argument. The arguments are compared element by element on each enabled lane, where the semantics of the comparison are defined [according to the condition code](#icmp-md-cc-sem). Masked-off lanes are `poison`.

<a id="id1421"></a>

##### Examples:

    %r = call <4 x i1> @llvm.vp.icmp.v4i32(<4 x i32> %a, <4 x i32> %b, metadata !"ne", <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = icmp ne <4 x i32> %a, %b
    %also.r = select <4 x i1> %mask, <4 x i1> %t, <4 x i1> poison

<a id="llvm-vp-ceil-intrinsics"></a>

<a id="int-vp-ceil"></a>

#### ‘`llvm.vp.ceil.*`’ Intrinsics

<a id="id1422"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.ceil.v16f32 (<16 x float> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.ceil.nxv4f32 (<vscale x 4 x float> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.ceil.v256f64 (<256 x double> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1423"></a>

##### Overview:

Predicated floating-point ceiling of a vector of floating-point values.

<a id="id1424"></a>

##### Arguments:

The first argument and the result have the same vector of floating-point type. The second argument is the vector mask and has the same number of elements as the result vector type. The third argument is the explicit vector length of the operation.

<a id="id1425"></a>

##### Semantics:

The ‘`llvm.vp.ceil`’ intrinsic performs floating-point ceiling ([ceil](intrinsics-libc-and-arithmetic.md#int-ceil)) of the first vector argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1426"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.ceil.v4f32(<4 x float> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x float> @llvm.ceil.v4f32(<4 x float> %a)
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-floor-intrinsics"></a>

<a id="int-vp-floor"></a>

#### ‘`llvm.vp.floor.*`’ Intrinsics

<a id="id1427"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.floor.v16f32 (<16 x float> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.floor.nxv4f32 (<vscale x 4 x float> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.floor.v256f64 (<256 x double> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1428"></a>

##### Overview:

Predicated floating-point floor of a vector of floating-point values.

<a id="id1429"></a>

##### Arguments:

The first argument and the result have the same vector of floating-point type. The second argument is the vector mask and has the same number of elements as the result vector type. The third argument is the explicit vector length of the operation.

<a id="id1430"></a>

##### Semantics:

The ‘`llvm.vp.floor`’ intrinsic performs floating-point floor ([floor](intrinsics-libc-and-arithmetic.md#int-floor)) of the first vector argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1431"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.floor.v4f32(<4 x float> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x float> @llvm.floor.v4f32(<4 x float> %a)
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-rint-intrinsics"></a>

<a id="int-vp-rint"></a>

#### ‘`llvm.vp.rint.*`’ Intrinsics

<a id="id1432"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.rint.v16f32 (<16 x float> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.rint.nxv4f32 (<vscale x 4 x float> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.rint.v256f64 (<256 x double> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1433"></a>

##### Overview:

Predicated floating-point rint of a vector of floating-point values.

<a id="id1434"></a>

##### Arguments:

The first argument and the result have the same vector of floating-point type. The second argument is the vector mask and has the same number of elements as the result vector type. The third argument is the explicit vector length of the operation.

<a id="id1435"></a>

##### Semantics:

The ‘`llvm.vp.rint`’ intrinsic performs floating-point rint ([rint](intrinsics-libc-and-arithmetic.md#int-rint)) of the first vector argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1436"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.rint.v4f32(<4 x float> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x float> @llvm.rint.v4f32(<4 x float> %a)
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-nearbyint-intrinsics"></a>

<a id="int-vp-nearbyint"></a>

#### ‘`llvm.vp.nearbyint.*`’ Intrinsics

<a id="id1437"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.nearbyint.v16f32 (<16 x float> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.nearbyint.nxv4f32 (<vscale x 4 x float> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.nearbyint.v256f64 (<256 x double> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1438"></a>

##### Overview:

Predicated floating-point nearbyint of a vector of floating-point values.

<a id="id1439"></a>

##### Arguments:

The first argument and the result have the same vector of floating-point type. The second argument is the vector mask and has the same number of elements as the result vector type. The third argument is the explicit vector length of the operation.

<a id="id1440"></a>

##### Semantics:

The ‘`llvm.vp.nearbyint`’ intrinsic performs floating-point nearbyint ([nearbyint](intrinsics-libc-and-arithmetic.md#int-nearbyint)) of the first vector argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1441"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.nearbyint.v4f32(<4 x float> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x float> @llvm.nearbyint.v4f32(<4 x float> %a)
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-round-intrinsics"></a>

<a id="int-vp-round"></a>

#### ‘`llvm.vp.round.*`’ Intrinsics

<a id="id1442"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.round.v16f32 (<16 x float> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.round.nxv4f32 (<vscale x 4 x float> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.round.v256f64 (<256 x double> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1443"></a>

##### Overview:

Predicated floating-point round of a vector of floating-point values.

<a id="id1444"></a>

##### Arguments:

The first argument and the result have the same vector of floating-point type. The second argument is the vector mask and has the same number of elements as the result vector type. The third argument is the explicit vector length of the operation.

<a id="id1445"></a>

##### Semantics:

The ‘`llvm.vp.round`’ intrinsic performs floating-point round ([round](intrinsics-libc-and-arithmetic.md#int-round)) of the first vector argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1446"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.round.v4f32(<4 x float> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x float> @llvm.round.v4f32(<4 x float> %a)
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-roundeven-intrinsics"></a>

<a id="int-vp-roundeven"></a>

#### ‘`llvm.vp.roundeven.*`’ Intrinsics

<a id="id1447"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.roundeven.v16f32 (<16 x float> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.roundeven.nxv4f32 (<vscale x 4 x float> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.roundeven.v256f64 (<256 x double> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1448"></a>

##### Overview:

Predicated floating-point roundeven of a vector of floating-point values.

<a id="id1449"></a>

##### Arguments:

The first argument and the result have the same vector of floating-point type. The second argument is the vector mask and has the same number of elements as the result vector type. The third argument is the explicit vector length of the operation.

<a id="id1450"></a>

##### Semantics:

The ‘`llvm.vp.roundeven`’ intrinsic performs floating-point roundeven ([roundeven](intrinsics-libc-and-arithmetic.md#int-roundeven)) of the first vector argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1451"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.roundeven.v4f32(<4 x float> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x float> @llvm.roundeven.v4f32(<4 x float> %a)
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-roundtozero-intrinsics"></a>

<a id="int-vp-roundtozero"></a>

#### ‘`llvm.vp.roundtozero.*`’ Intrinsics

<a id="id1452"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x float>  @llvm.vp.roundtozero.v16f32 (<16 x float> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x float>  @llvm.vp.roundtozero.nxv4f32 (<vscale x 4 x float> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x double>  @llvm.vp.roundtozero.v256f64 (<256 x double> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1453"></a>

##### Overview:

Predicated floating-point round-to-zero of a vector of floating-point values.

<a id="id1454"></a>

##### Arguments:

The first argument and the result have the same vector of floating-point type. The second argument is the vector mask and has the same number of elements as the result vector type. The third argument is the explicit vector length of the operation.

<a id="id1455"></a>

##### Semantics:

The ‘`llvm.vp.roundtozero`’ intrinsic performs floating-point roundeven ([llvm.trunc](intrinsics-libc-and-arithmetic.md#int-llvm-trunc)) of the first vector argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1456"></a>

##### Examples:

    %r = call <4 x float> @llvm.vp.roundtozero.v4f32(<4 x float> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x float> @llvm.trunc.v4f32(<4 x float> %a)
    %also.r = select <4 x i1> %mask, <4 x float> %t, <4 x float> poison

<a id="llvm-vp-lrint-intrinsics"></a>

<a id="int-vp-lrint"></a>

#### ‘`llvm.vp.lrint.*`’ Intrinsics

<a id="id1457"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32> @llvm.vp.lrint.v16i32.v16f32(<16 x float> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32> @llvm.vp.lrint.nxv4i32.nxv4f32(<vscale x 4 x float> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64> @llvm.vp.lrint.v256i64.v256f64(<256 x double> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1458"></a>

##### Overview:

Predicated lrint of a vector of floating-point values.

<a id="id1459"></a>

##### Arguments:

The result is an integer vector and the first argument is a vector of [floating-point](type-system.md#t-floating) type with the same number of elements as the result vector type. The second argument is the vector mask and has the same number of elements as the result vector type. The third argument is the explicit vector length of the operation.

<a id="id1460"></a>

##### Semantics:

The ‘`llvm.vp.lrint`’ intrinsic performs lrint ([lrint](intrinsics-libc-and-arithmetic.md#int-lrint)) of the first vector argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1461"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.lrint.v4i32.v4f32(<4 x float> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.lrint.v4f32(<4 x float> %a)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-llrint-intrinsics"></a>

<a id="int-vp-llrint"></a>

#### ‘`llvm.vp.llrint.*`’ Intrinsics

<a id="id1462"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32> @llvm.vp.llrint.v16i32.v16f32(<16 x float> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32> @llvm.vp.llrint.nxv4i32.nxv4f32(<vscale x 4 x float> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64> @llvm.vp.llrint.v256i64.v256f64(<256 x double> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1463"></a>

##### Overview:

Predicated llrint of a vector of floating-point values.

<a id="id1464"></a>

##### Arguments:

The result is an integer vector and the first argument is a vector of [floating-point](type-system.md#t-floating) type with the same number of elements as the result vector type. The second argument is the vector mask and has the same number of elements as the result vector type. The third argument is the explicit vector length of the operation.

<a id="id1465"></a>

##### Semantics:

The ‘`llvm.vp.llrint`’ intrinsic performs lrint ([llrint](intrinsics-libc-and-arithmetic.md#int-llrint)) of the first vector argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1466"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.llrint.v4i32.v4f32(<4 x float> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.llrint.v4f32(<4 x float> %a)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-bitreverse-intrinsics"></a>

<a id="int-vp-bitreverse"></a>

#### ‘`llvm.vp.bitreverse.*`’ Intrinsics

<a id="id1467"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.bitreverse.v16i32 (<16 x i32> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.bitreverse.nxv4i32 (<vscale x 4 x i32> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.bitreverse.v256i64 (<256 x i64> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1468"></a>

##### Overview:

Predicated bitreverse of a vector of integers.

<a id="id1469"></a>

##### Arguments:

The first argument and the result have the same vector of integer type. The second argument is the vector mask and has the same number of elements as the result vector type. The third argument is the explicit vector length of the operation.

<a id="id1470"></a>

##### Semantics:

The ‘`llvm.vp.bitreverse`’ intrinsic performs bitreverse ([bitreverse](intrinsics-libc-and-arithmetic.md#int-bitreverse)) of the first argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1471"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.bitreverse.v4i32(<4 x i32> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.bitreverse.v4i32(<4 x i32> %a)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-bswap-intrinsics"></a>

<a id="int-vp-bswap"></a>

#### ‘`llvm.vp.bswap.*`’ Intrinsics

<a id="id1472"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.bswap.v16i32 (<16 x i32> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.bswap.nxv4i32 (<vscale x 4 x i32> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.bswap.v256i64 (<256 x i64> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1473"></a>

##### Overview:

Predicated bswap of a vector of integers.

<a id="id1474"></a>

##### Arguments:

The first argument and the result have the same vector of integer type. The second argument is the vector mask and has the same number of elements as the result vector type. The third argument is the explicit vector length of the operation.

<a id="id1475"></a>

##### Semantics:

The ‘`llvm.vp.bswap`’ intrinsic performs bswap ([bswap](intrinsics-libc-and-arithmetic.md#int-bswap)) of the first argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1476"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.bswap.v4i32(<4 x i32> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.bswap.v4i32(<4 x i32> %a)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-ctpop-intrinsics"></a>

<a id="int-vp-ctpop"></a>

#### ‘`llvm.vp.ctpop.*`’ Intrinsics

<a id="id1477"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.ctpop.v16i32 (<16 x i32> <op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.ctpop.nxv4i32 (<vscale x 4 x i32> <op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.ctpop.v256i64 (<256 x i64> <op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1478"></a>

##### Overview:

Predicated ctpop of a vector of integers.

<a id="id1479"></a>

##### Arguments:

The first argument and the result have the same vector of integer type. The second argument is the vector mask and has the same number of elements as the result vector type. The third argument is the explicit vector length of the operation.

<a id="id1480"></a>

##### Semantics:

The ‘`llvm.vp.ctpop`’ intrinsic performs ctpop ([ctpop](intrinsics-libc-and-arithmetic.md#int-ctpop)) of the first argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1481"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.ctpop.v4i32(<4 x i32> %a, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.ctpop.v4i32(<4 x i32> %a)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-ctlz-intrinsics"></a>

<a id="int-vp-ctlz"></a>

#### ‘`llvm.vp.ctlz.*`’ Intrinsics

<a id="id1482"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.ctlz.v16i32 (<16 x i32> <op>, i1 <is_zero_poison>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.ctlz.nxv4i32 (<vscale x 4 x i32> <op>, i1 <is_zero_poison>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.ctlz.v256i64 (<256 x i64> <op>, i1 <is_zero_poison>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1483"></a>

##### Overview:

Predicated ctlz of a vector of integers.

<a id="id1484"></a>

##### Arguments:

The first argument and the result have the same vector of integer type. The second argument is a constant flag that indicates whether the intrinsic returns a valid result if the first argument is zero. The third argument is the vector mask and has the same number of elements as the result vector type. the fourth argument is the explicit vector length of the operation. If the first argument is zero and the second argument is true, the result is poison.

<a id="id1485"></a>

##### Semantics:

The ‘`llvm.vp.ctlz`’ intrinsic performs ctlz ([ctlz](intrinsics-libc-and-arithmetic.md#int-ctlz)) of the first argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1486"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.ctlz.v4i32(<4 x i32> %a, i1 false, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.ctlz.v4i32(<4 x i32> %a, i1 false)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-cttz-intrinsics"></a>

<a id="int-vp-cttz"></a>

#### ‘`llvm.vp.cttz.*`’ Intrinsics

<a id="id1487"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.cttz.v16i32 (<16 x i32> <op>, i1 <is_zero_poison>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.cttz.nxv4i32 (<vscale x 4 x i32> <op>, i1 <is_zero_poison>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.cttz.v256i64 (<256 x i64> <op>, i1 <is_zero_poison>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1488"></a>

##### Overview:

Predicated cttz of a vector of integers.

<a id="id1489"></a>

##### Arguments:

The first argument and the result have the same vector of integer type. The second argument is a constant flag that indicates whether the intrinsic returns a valid result if the first argument is zero. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation. If the first argument is zero and the second argument is true, the result is poison.

<a id="id1490"></a>

##### Semantics:

The ‘`llvm.vp.cttz`’ intrinsic performs cttz ([cttz](intrinsics-libc-and-arithmetic.md#int-cttz)) of the first argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1491"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.cttz.v4i32(<4 x i32> %a, i1 false, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.cttz.v4i32(<4 x i32> %a, i1 false)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-cttz-elts-intrinsics"></a>

<a id="int-vp-cttz-elts"></a>

#### ‘`llvm.vp.cttz.elts.*`’ Intrinsics

<a id="id1492"></a>

##### Syntax:

This is an overloaded intrinsic. You can use `llvm.vp.cttz.elts` on any vector of integer elements, both fixed width and scalable.

    declare i32  @llvm.vp.cttz.elts.i32.v16i32 (<16 x i32> <op>, i1 <is_zero_poison>, <16 x i1> <mask>, i32 <vector_length>)
    declare i64  @llvm.vp.cttz.elts.i64.nxv4i32 (<vscale x 4 x i32> <op>, i1 <is_zero_poison>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare i64  @llvm.vp.cttz.elts.i64.v256i1 (<256 x i1> <op>, i1 <is_zero_poison>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1493"></a>

##### Overview:

This ‘`llvm.vp.cttz.elts`’ intrinsic counts the number of trailing zero elements of a vector. This is basically the vector-predicated version of ‘`llvm.experimental.cttz.elts`’.

<a id="id1494"></a>

##### Arguments:

The first argument is the vector to be counted. This argument must be a vector with integer element type. The return type must also be an integer type which is wide enough to hold the maximum number of elements of the source vector. The result is a [poison value](constants.md#poisonvalues) if the return type is not wide enough for the number of elements in the input vector.

The second argument is a constant flag that indicates whether the intrinsic returns a valid result if the first argument is all zero.

The third argument is the vector mask and has the same number of elements as the input vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1495"></a>

##### Semantics:

The ‘`llvm.vp.cttz.elts`’ intrinsic counts the trailing (least significant / lowest-numbered) zero elements in the first argument on each enabled lane. If the first argument is all zero and the second argument is true, the result is poison. Otherwise, it returns the explicit vector length (i.e., the fourth argument).

<a id="llvm-vp-sadd-sat-intrinsics"></a>

<a id="int-vp-sadd-sat"></a>

#### ‘`llvm.vp.sadd.sat.*`’ Intrinsics

<a id="id1496"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.sadd.sat.v16i32 (<16 x i32> <left_op> <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.sadd.sat.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.sadd.sat.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1497"></a>

##### Overview:

Predicated signed saturating addition of two vectors of integers.

<a id="id1498"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1499"></a>

##### Semantics:

The ‘`llvm.vp.sadd.sat`’ intrinsic performs sadd.sat ([sadd.sat](intrinsics-libc-and-arithmetic.md#int-sadd-sat)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1500"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.sadd.sat.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.sadd.sat.v4i32(<4 x i32> %a, <4 x i32> %b)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-uadd-sat-intrinsics"></a>

<a id="int-vp-uadd-sat"></a>

#### ‘`llvm.vp.uadd.sat.*`’ Intrinsics

<a id="id1501"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.uadd.sat.v16i32 (<16 x i32> <left_op> <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.uadd.sat.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.uadd.sat.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1502"></a>

##### Overview:

Predicated unsigned saturating addition of two vectors of integers.

<a id="id1503"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1504"></a>

##### Semantics:

The ‘`llvm.vp.uadd.sat`’ intrinsic performs uadd.sat ([uadd.sat](intrinsics-libc-and-arithmetic.md#int-uadd-sat)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1505"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.uadd.sat.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.uadd.sat.v4i32(<4 x i32> %a, <4 x i32> %b)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-ssub-sat-intrinsics"></a>

<a id="int-vp-ssub-sat"></a>

#### ‘`llvm.vp.ssub.sat.*`’ Intrinsics

<a id="id1506"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.ssub.sat.v16i32 (<16 x i32> <left_op> <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.ssub.sat.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.ssub.sat.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1507"></a>

##### Overview:

Predicated signed saturating subtraction of two vectors of integers.

<a id="id1508"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1509"></a>

##### Semantics:

The ‘`llvm.vp.ssub.sat`’ intrinsic performs ssub.sat ([ssub.sat](intrinsics-libc-and-arithmetic.md#int-ssub-sat)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1510"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.ssub.sat.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.ssub.sat.v4i32(<4 x i32> %a, <4 x i32> %b)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-usub-sat-intrinsics"></a>

<a id="int-vp-usub-sat"></a>

#### ‘`llvm.vp.usub.sat.*`’ Intrinsics

<a id="id1511"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.usub.sat.v16i32 (<16 x i32> <left_op> <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.usub.sat.nxv4i32 (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.usub.sat.v256i64 (<256 x i64> <left_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1512"></a>

##### Overview:

Predicated unsigned saturating subtraction of two vectors of integers.

<a id="id1513"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1514"></a>

##### Semantics:

The ‘`llvm.vp.usub.sat`’ intrinsic performs usub.sat ([usub.sat](intrinsics-libc-and-arithmetic.md#int-usub-sat)) of the first and second vector arguments on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1515"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.usub.sat.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.usub.sat.v4i32(<4 x i32> %a, <4 x i32> %b)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-fshl-intrinsics"></a>

<a id="int-vp-fshl"></a>

#### ‘`llvm.vp.fshl.*`’ Intrinsics

<a id="id1516"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.fshl.v16i32 (<16 x i32> <left_op>, <16 x i32> <middle_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.fshl.nxv4i32  (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <middle_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.fshl.v256i64 (<256 x i64> <left_op>, <256 x i64> <middle_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1517"></a>

##### Overview:

Predicated fshl of three vectors of integers.

<a id="id1518"></a>

##### Arguments:

The first three arguments and the result have the same vector of integer type. The fourth argument is the vector mask and has the same number of elements as the result vector type. The fifth argument is the explicit vector length of the operation.

<a id="id1519"></a>

##### Semantics:

The ‘`llvm.vp.fshl`’ intrinsic performs fshl ([fshl](intrinsics-libc-and-arithmetic.md#int-fshl)) of the first, second, and third vector argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1520"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.fshl.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i32> %c, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.fshl.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i32> %c)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-fshr-intrinsics"></a>

#### ‘`llvm.vp.fshr.*`’ Intrinsics

<a id="id1521"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <16 x i32>  @llvm.vp.fshr.v16i32 (<16 x i32> <left_op>, <16 x i32> <middle_op>, <16 x i32> <right_op>, <16 x i1> <mask>, i32 <vector_length>)
    declare <vscale x 4 x i32>  @llvm.vp.fshr.nxv4i32  (<vscale x 4 x i32> <left_op>, <vscale x 4 x i32> <middle_op>, <vscale x 4 x i32> <right_op>, <vscale x 4 x i1> <mask>, i32 <vector_length>)
    declare <256 x i64>  @llvm.vp.fshr.v256i64 (<256 x i64> <left_op>, <256 x i64> <middle_op>, <256 x i64> <right_op>, <256 x i1> <mask>, i32 <vector_length>)

<a id="id1522"></a>

##### Overview:

Predicated fshr of three vectors of integers.

<a id="id1523"></a>

##### Arguments:

The first three arguments and the result have the same vector of integer type. The fourth argument is the vector mask and has the same number of elements as the result vector type. The fifth argument is the explicit vector length of the operation.

<a id="id1524"></a>

##### Semantics:

The ‘`llvm.vp.fshr`’ intrinsic performs fshr ([fshr](intrinsics-libc-and-arithmetic.md#int-fshr)) of the first, second, and third vector argument on each enabled lane. The result on disabled lanes is a [poison value](constants.md#poisonvalues).

<a id="id1525"></a>

##### Examples:

    %r = call <4 x i32> @llvm.vp.fshr.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i32> %c, <4 x i1> %mask, i32 %evl)
    ;; For all lanes below %evl, %r is lane-wise equivalent to %also.r

    %t = call <4 x i32> @llvm.fshr.v4i32(<4 x i32> %a, <4 x i32> %b, <4 x i32> %c)
    %also.r = select <4 x i1> %mask, <4 x i32> %t, <4 x i32> poison

<a id="llvm-vp-is-fpclass-intrinsics"></a>

#### ‘`llvm.vp.is.fpclass.*`’ Intrinsics

<a id="id1526"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <vscale x 2 x i1> @llvm.vp.is.fpclass.nxv2f32(<vscale x 2 x float> <op>, i32 <test>, <vscale x 2 x i1> <mask>, i32 <vector_length>)
    declare <2 x i1> @llvm.vp.is.fpclass.v2f16(<2 x half> <op>, i32 <test>, <2 x i1> <mask>, i32 <vector_length>)

<a id="id1527"></a>

##### Overview:

Predicated `llvm.is.fpclass` [llvm.is.fpclass](intrinsics-floating-point.md#llvm-is-fpclass)

<a id="id1528"></a>

##### Arguments:

The first argument is a floating-point vector, the result type is a vector of boolean with the same number of elements as the first argument. The second argument specifies, which tests to perform [llvm.is.fpclass](intrinsics-floating-point.md#llvm-is-fpclass). The third argument is the vector mask and has the same number of elements as the result vector type. The fourth argument is the explicit vector length of the operation.

<a id="id1529"></a>

##### Semantics:

The ‘`llvm.vp.is.fpclass`’ intrinsic performs `llvm.is.fpclass` ([llvm.is.fpclass](intrinsics-floating-point.md#llvm-is-fpclass)).

<a id="id1530"></a>

##### Examples:

    %r = call <2 x i1> @llvm.vp.is.fpclass.v2f16(<2 x half> %x, i32 3, <2 x i1> %m, i32 %evl)
    %t = call <vscale x 2 x i1> @llvm.vp.is.fpclass.nxv2f16(<vscale x 2 x half> %x, i32 3, <vscale x 2 x i1> %m, i32 %evl)

<a id="masked-vector-load-and-store-intrinsics"></a>

<a id="int-mload-mstore"></a>

### Masked Vector Load and Store Intrinsics

LLVM provides intrinsics for predicated vector load and store operations. The predicate is specified by a mask argument, which holds one bit per vector element, switching the associated vector lane on or off. The memory addresses corresponding to the “off” lanes are not accessed. When all bits of the mask are on, the intrinsic is identical to a regular vector load or store. When all bits are off, no memory is accessed.

<a id="llvm-masked-load-intrinsics"></a>

<a id="int-mload"></a>

#### ‘`llvm.masked.load.*`’ Intrinsics

<a id="id1531"></a>

##### Syntax:

This is an overloaded intrinsic. The loaded data is a vector of any integer, floating-point or pointer data type.

    declare <16 x float>  @llvm.masked.load.v16f32.p0(ptr <ptr>, <16 x i1> <mask>, <16 x float> <passthru>)
    declare <2 x double>  @llvm.masked.load.v2f64.p0(ptr <ptr>, <2 x i1>  <mask>, <2 x double> <passthru>)
    ;; The data is a vector of pointers
    declare <8 x ptr> @llvm.masked.load.v8p0.p0(ptr <ptr>, <8 x i1> <mask>, <8 x ptr> <passthru>)

<a id="id1532"></a>

##### Overview:

Reads a vector from memory according to the provided mask. The mask holds a bit for each vector lane, and is used to prevent memory accesses to the masked-off lanes. The masked-off lanes in the result vector are taken from the corresponding lanes of the ‘`passthru`’ argument.

<a id="id1533"></a>

##### Arguments:

The first argument is the base pointer for the load. The second argument, mask, is a vector of boolean values with the same number of elements as the return type. The third is a pass-through value that is used to fill the masked-off lanes of the result. The return type, underlying type of the base pointer and the type of the ‘`passthru`’ argument are the same vector types.

The alignment of the base pointer can be specified using the `align` attribute on the first argument.

<a id="id1534"></a>

##### Semantics:

The ‘`llvm.masked.load`’ intrinsic is designed for conditional reading of selected vector elements in a single IR operation. It is useful for targets that support vector masked loads and allows vectorizing predicated basic blocks on these targets. Other targets may support this intrinsic differently, for example by lowering it into a sequence of branches that guard scalar load operations. The result of this operation is equivalent to a regular vector load instruction followed by a ‘select’ between the loaded and the passthru values, predicated on the same mask, except that the masked-off lanes are not accessed. Only the masked-on lanes of the vector need to be inbounds of an allocation (but all these lanes need to be inbounds of the same allocation). In particular, using this intrinsic prevents exceptions on memory accesses to masked-off lanes. Masked-off lanes are also not considered accessed for the purpose of data races or `noalias` constraints.

    %res = call <16 x float> @llvm.masked.load.v16f32.p0(ptr align 4 %ptr, <16 x i1>%mask, <16 x float> %passthru)

    ;; The result of the two following instructions is identical aside from potential memory access exception
    %loadlal = load <16 x float>, ptr %ptr, align 4
    %res = select <16 x i1> %mask, <16 x float> %loadlal, <16 x float> %passthru

<a id="llvm-masked-store-intrinsics"></a>

<a id="int-mstore"></a>

#### ‘`llvm.masked.store.*`’ Intrinsics

<a id="id1535"></a>

##### Syntax:

This is an overloaded intrinsic. The data stored in memory is a vector of any integer, floating-point or pointer data type.

    declare void @llvm.masked.store.v8i32.p0 (<8  x i32>   <value>, ptr <ptr>, <8  x i1> <mask>)
    declare void @llvm.masked.store.v16f32.p0(<16 x float> <value>, ptr <ptr>, <16 x i1> <mask>)
    ;; The data is a vector of pointers
    declare void @llvm.masked.store.v8p0.p0  (<8 x ptr>    <value>, ptr <ptr>, <8 x i1> <mask>)

<a id="id1536"></a>

##### Overview:

Writes a vector to memory according to the provided mask. The mask holds a bit for each vector lane, and is used to prevent memory accesses to the masked-off lanes.

<a id="id1537"></a>

##### Arguments:

The first argument is the vector value to be written to memory. The second argument is the base pointer for the store, it has the same underlying type as the value argument. The third argument, mask, is a vector of boolean values. The types of the mask and the value argument must have the same number of vector elements.

The alignment of the base pointer can be specified using the `align` attribute on the second argument.

<a id="id1538"></a>

##### Semantics:

The ‘`llvm.masked.store`’ intrinsics is designed for conditional writing of selected vector elements in a single IR operation. It is useful for targets that support vector masked store and allows vectorizing predicated basic blocks on these targets. Other targets may support this intrinsic differently, for example by lowering it into a sequence of branches that guard scalar store operations. The result of this operation is equivalent to a load-modify-store sequence, except that the masked-off lanes are not accessed. Only the masked-on lanes of the vector need to be inbounds of an allocation (but all these lanes need to be inbounds of the same allocation). In particular, using this intrinsic prevents exceptions on memory accesses to masked-off lanes. Masked-off lanes are also not considered accessed for the purpose of data races or `noalias` constraints.

    call void @llvm.masked.store.v16f32.p0(<16 x float> %value, ptr align 4 %ptr, <16 x i1> %mask)

    ;; The result of the following instructions is identical aside from potential data races and memory access exceptions
    %oldval = load <16 x float>, ptr %ptr, align 4
    %res = select <16 x i1> %mask, <16 x float> %value, <16 x float> %oldval
    store <16 x float> %res, ptr %ptr, align 4

<a id="masked-vector-gather-and-scatter-intrinsics"></a>

### Masked Vector Gather and Scatter Intrinsics

LLVM provides intrinsics for vector gather and scatter operations. They are similar to [Masked Vector Load and Store](#int-mload-mstore), except they are designed for arbitrary memory accesses, rather than sequential memory accesses. Gather and scatter also employ a mask argument, which holds one bit per vector element, switching the associated vector lane on or off. The memory addresses corresponding to the “off” lanes are not accessed. When all bits are off, no memory is accessed.

<a id="llvm-masked-gather-intrinsics"></a>

<a id="int-mgather"></a>

#### ‘`llvm.masked.gather.*`’ Intrinsics

<a id="id1539"></a>

##### Syntax:

This is an overloaded intrinsic. The loaded data are multiple scalar values of any integer, floating-point or pointer data type gathered together into one vector.

    declare <16 x float> @llvm.masked.gather.v16f32.v16p0(<16 x ptr> <ptrs>, <16 x i1> <mask>, <16 x float> <passthru>)
    declare <2 x double> @llvm.masked.gather.v2f64.v2p1(<2 x ptr addrspace(1)> <ptrs>, <2 x i1>  <mask>, <2 x double> <passthru>)
    declare <8 x ptr> @llvm.masked.gather.v8p0.v8p0(<8 x ptr> <ptrs>, <8 x i1>  <mask>, <8 x ptr> <passthru>)

<a id="id1540"></a>

##### Overview:

Reads scalar values from arbitrary memory locations and gathers them into one vector. The memory locations are provided in the vector of pointers ‘`ptrs`’. The memory is accessed according to the provided mask. The mask holds a bit for each vector lane, and is used to prevent memory accesses to the masked-off lanes. The masked-off lanes in the result vector are taken from the corresponding lanes of the ‘`passthru`’ argument.

<a id="id1541"></a>

##### Arguments:

The first argument is a vector of pointers which holds all memory addresses to read. The second argument, mask, is a vector of boolean values with the same number of elements as the return type. The third is a pass-through value that is used to fill the masked-off lanes of the result. The return type, underlying type of the vector of pointers and the type of the ‘`passthru`’ argument are the same vector types.

The alignment of the pointers can be specified using the `align` attribute on the first argument.

<a id="id1542"></a>

##### Semantics:

The ‘`llvm.masked.gather`’ intrinsic is designed for conditional reading of multiple scalar values from arbitrary memory locations in a single IR operation. It is useful for targets that support vector masked gathers and allows vectorizing basic blocks with data and control divergence. Other targets may support this intrinsic differently, for example by lowering it into a sequence of scalar load operations. The semantics of this operation are equivalent to a sequence of conditional scalar loads with subsequent gathering all loaded values into a single vector. The mask restricts memory access to certain lanes and facilitates vectorization of predicated basic blocks.

    %res = call <4 x double> @llvm.masked.gather.v4f64.v4p0(<4 x ptr> align 8 %ptrs, <4 x i1> <i1 true, i1 true, i1 true, i1 true>, <4 x double> poison)

    ;; The gather with all-true mask is equivalent to the following instruction sequence
    %ptr0 = extractelement <4 x ptr> %ptrs, i64 0
    %ptr1 = extractelement <4 x ptr> %ptrs, i64 1
    %ptr2 = extractelement <4 x ptr> %ptrs, i64 2
    %ptr3 = extractelement <4 x ptr> %ptrs, i64 3

    %val0 = load double, ptr %ptr0, align 8
    %val1 = load double, ptr %ptr1, align 8
    %val2 = load double, ptr %ptr2, align 8
    %val3 = load double, ptr %ptr3, align 8

    %vec0    = insertelement <4 x double> poison, %val0, i64 0
    %vec01   = insertelement <4 x double> %vec0, %val1, i64 1
    %vec012  = insertelement <4 x double> %vec01, %val2, i64 2
    %vec0123 = insertelement <4 x double> %vec012, %val3, i64 3

<a id="llvm-masked-scatter-intrinsics"></a>

<a id="int-mscatter"></a>

#### ‘`llvm.masked.scatter.*`’ Intrinsics

<a id="id1543"></a>

##### Syntax:

This is an overloaded intrinsic. The data stored in memory is a vector of any integer, floating-point or pointer data type. Each vector element is stored in an arbitrary memory address. Scatter with overlapping addresses is guaranteed to be ordered from least-significant to most-significant element.

    declare void @llvm.masked.scatter.v8i32.v8p0  (<8 x i32>    <value>, <8 x ptr>               <ptrs>, <8 x i1>  <mask>)
    declare void @llvm.masked.scatter.v16f32.v16p1(<16 x float> <value>, <16 x ptr addrspace(1)> <ptrs>, <16 x i1> <mask>)
    declare void @llvm.masked.scatter.v4p0.v4p0   (<4 x ptr>    <value>, <4 x ptr>               <ptrs>, <4 x i1>  <mask>)

<a id="id1544"></a>

##### Overview:

Writes each element from the value vector to the corresponding memory address. The memory addresses are represented as a vector of pointers. Writing is done according to the provided mask. The mask holds a bit for each vector lane, and is used to prevent memory accesses to the masked-off lanes.

<a id="id1545"></a>

##### Arguments:

The first argument is a vector value to be written to memory. The second argument is a vector of pointers, pointing to where the value elements should be stored. It has the same underlying type as the value argument. The third argument, mask, is a vector of boolean values. The types of the mask and the value argument must have the same number of vector elements.

The alignment of the pointers can be specified using the `align` attribute on the second argument.

<a id="id1546"></a>

##### Semantics:

The ‘`llvm.masked.scatter`’ intrinsics is designed for writing selected vector elements to arbitrary memory addresses in a single IR operation. The operation may be conditional, when not all bits in the mask are switched on. It is useful for targets that support vector masked scatter and allows vectorizing basic blocks with data and control divergence. Other targets may support this intrinsic differently, for example by lowering it into a sequence of branches that guard scalar store operations.

    ;; This instruction unconditionally stores data vector in multiple addresses
    call @llvm.masked.scatter.v8i32.v8p0(<8 x i32> %value, <8 x ptr> align 4 %ptrs,  <8 x i1>  <true, true, .. true>)

    ;; It is equivalent to a list of scalar stores
    %val0 = extractelement <8 x i32> %value, i64 0
    %val1 = extractelement <8 x i32> %value, i64 1
    ..
    %val7 = extractelement <8 x i32> %value, i64 7
    %ptr0 = extractelement <8 x ptr> %ptrs, i64 0
    %ptr1 = extractelement <8 x ptr> %ptrs, i64 1
    ..
    %ptr7 = extractelement <8 x ptr> %ptrs, i64 7
    ;; Note: the order of the following stores is important when they overlap:
    store i32 %val0, ptr %ptr0, align 4
    store i32 %val1, ptr %ptr1, align 4
    ..
    store i32 %val7, ptr %ptr7, align 4

<a id="masked-vector-expanding-load-and-compressing-store-intrinsics"></a>

### Masked Vector Expanding Load and Compressing Store Intrinsics

LLVM provides intrinsics for expanding load and compressing store operations. Data selected from a vector according to a mask is stored in consecutive memory addresses (compressed store), and vice-versa (expanding load). These operations effective map to “if (cond.i) a\[j++\] = v.i” and “if (cond.i) v.i = a\[j++\]” patterns, respectively. Note that when the mask starts with ‘1’ bits followed by ‘0’ bits, these operations are identical to [llvm.masked.store](#int-mstore) and [llvm.masked.load](#int-mload).

<a id="llvm-masked-expandload-intrinsics"></a>

<a id="int-expandload"></a>

#### ‘`llvm.masked.expandload.*`’ Intrinsics

<a id="id1547"></a>

##### Syntax:

This is an overloaded intrinsic. Several values of integer, floating point or pointer data type are loaded from consecutive memory addresses and stored into the elements of a vector according to the mask.

    declare <16 x float>  @llvm.masked.expandload.v16f32 (ptr <ptr>, <16 x i1> <mask>, <16 x float> <passthru>)
    declare <2 x i64>     @llvm.masked.expandload.v2i64 (ptr <ptr>, <2 x i1>  <mask>, <2 x i64> <passthru>)

<a id="id1548"></a>

##### Overview:

Reads a number of scalar values sequentially from memory location provided in ‘`ptr`’ and spreads them in a vector. The ‘`mask`’ holds a bit for each vector lane. The number of elements read from memory is equal to the number of ‘1’ bits in the mask. The loaded elements are positioned in the destination vector according to the sequence of ‘1’ and ‘0’ bits in the mask. E.g., if the mask vector is ‘10010001’, “expandload” reads 3 values from memory addresses ptr, ptr+1, ptr+2 and places them in lanes 0, 3 and 7 accordingly. The masked-off lanes are filled by elements from the corresponding lanes of the ‘`passthru`’ argument.

<a id="id1549"></a>

##### Arguments:

The first argument is the base pointer for the load. It has the same underlying type as the element of the returned vector. The second argument, mask, is a vector of boolean values with the same number of elements as the return type. The third is a pass-through value that is used to fill the masked-off lanes of the result. The return type and the type of the ‘`passthru`’ argument have the same vector type.

The [align](high-level-structure.md#attr-align) parameter attribute can be provided for the first argument. The pointer alignment defaults to 1.

<a id="id1550"></a>

##### Semantics:

The ‘`llvm.masked.expandload`’ intrinsic is designed for reading multiple scalar values from adjacent memory addresses into possibly non-adjacent vector lanes. It is useful for targets that support vector expanding loads and allows vectorizing loop with cross-iteration dependency like in the following example:

    // In this loop we load from B and spread the elements into array A.
    double *A, B; int *C;
    for (int i = 0; i < size; ++i) {
      if (C[i] != 0)
        A[i] = B[j++];
    }

    ; Load several elements from array B and expand them in a vector.
    ; The number of loaded elements is equal to the number of '1' elements in the Mask.
    %Tmp = call <8 x double> @llvm.masked.expandload.v8f64(ptr %Bptr, <8 x i1> %Mask, <8 x double> poison)
    ; Store the result in A
    call void @llvm.masked.store.v8f64.p0(<8 x double> %Tmp, ptr %Aptr, i32 8, <8 x i1> %Mask)

    ; %Bptr should be increased on each iteration according to the number of '1' elements in the Mask.
    %MaskI = bitcast <8 x i1> %Mask to i8
    %MaskIPopcnt = call i8 @llvm.ctpop.i8(i8 %MaskI)
    %MaskI64 = zext i8 %MaskIPopcnt to i64
    %BNextInd = add i64 %BInd, %MaskI64

Other targets may support this intrinsic differently, for example, by lowering it into a sequence of conditional scalar load operations and shuffles. If all mask elements are ‘1’, the intrinsic behavior is equivalent to the regular unmasked vector load.

<a id="llvm-masked-compressstore-intrinsics"></a>

<a id="int-compressstore"></a>

#### ‘`llvm.masked.compressstore.*`’ Intrinsics

<a id="id1551"></a>

##### Syntax:

This is an overloaded intrinsic. A number of scalar values of integer, floating point or pointer data type are collected from an input vector and stored into adjacent memory addresses. A mask defines which elements to collect from the vector.

    declare void @llvm.masked.compressstore.v8i32  (<8  x i32>   <value>, ptr <ptr>, <8  x i1> <mask>)
    declare void @llvm.masked.compressstore.v16f32 (<16 x float> <value>, ptr <ptr>, <16 x i1> <mask>)

<a id="id1552"></a>

##### Overview:

Selects elements from input vector ‘`value`’ according to the ‘`mask`’. All selected elements are written into adjacent memory addresses starting at address ‘`ptr`’, from lower to higher. The mask holds a bit for each vector lane, and is used to select elements to be stored. The number of elements to be stored is equal to the number of active bits in the mask.

<a id="id1553"></a>

##### Arguments:

The first argument is the input vector, from which elements are collected and written to memory. The second argument is the base pointer for the store, it has the same underlying type as the element of the input vector argument. The third argument is the mask, a vector of boolean values. The mask and the input vector must have the same number of vector elements.

The [align](high-level-structure.md#attr-align) parameter attribute can be provided for the second argument. The pointer alignment defaults to 1.

<a id="id1554"></a>

##### Semantics:

The ‘`llvm.masked.compressstore`’ intrinsic is designed for compressing data in memory. It allows to collect elements from possibly non-adjacent lanes of a vector and store them contiguously in memory in one IR operation. It is useful for targets that support compressing store operations and allows vectorizing loops with cross-iteration dependencies like in the following example:

    // In this loop we load elements from A and store them consecutively in B
    double *A, B; int *C;
    for (int i = 0; i < size; ++i) {
      if (C[i] != 0)
        B[j++] = A[i]
    }

    ; Load elements from A.
    %Tmp = call <8 x double> @llvm.masked.load.v8f64.p0(ptr %Aptr, i32 8, <8 x i1> %Mask, <8 x double> poison)
    ; Store all selected elements consecutively in array B
    call <void> @llvm.masked.compressstore.v8f64(<8 x double> %Tmp, ptr %Bptr, <8 x i1> %Mask)

    ; %Bptr should be increased on each iteration according to the number of '1' elements in the Mask.
    %MaskI = bitcast <8 x i1> %Mask to i8
    %MaskIPopcnt = call i8 @llvm.ctpop.i8(i8 %MaskI)
    %MaskI64 = zext i8 %MaskIPopcnt to i64
    %BNextInd = add i64 %BInd, %MaskI64

Other targets may support this intrinsic differently, for example, by lowering it into a sequence of branches that guard scalar store operations.

<a id="masked-vector-arithmetic-intrinsics"></a>

### Masked Vector Arithmetic Intrinsics

<a id="llvm-masked-udiv-intrinsics"></a>

#### ‘`llvm.masked.udiv.*`’ Intrinsics

<a id="id1555"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <8 x i32> @llvm.masked.udiv.v8i32(<8 x i32> <op1>, <8 x i32> <op2>, <8 x i1> <mask>)
    declare <vscale x 2 x i64> @llvm.masked.udiv.nxv2i64(<vscale x 2 x i64> <op1>, <vscale x 2 x i64> <op2>, <vscale x 2 x i1> <mask>)

<a id="id1556"></a>

##### Overview:

Performs unsigned division ([udiv](instructions-arithmetic.md#i-udiv)) of two vectors of integers, but only on enabled lanes.

<a id="id1557"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type.

<a id="id1558"></a>

##### Semantics:

Follows the same semantics as [udiv](instructions-arithmetic.md#i-udiv) with the exception that disabled lanes cannot produce undefined behaviour and always result in poison.

<a id="llvm-masked-sdiv-intrinsics"></a>

#### ‘`llvm.masked.sdiv.*`’ Intrinsics

<a id="id1559"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <8 x i32> @llvm.masked.sdiv.v8i32(<8 x i32> <op1>, <8 x i32> <op2>, <8 x i1> <mask>)
    declare <vscale x 2 x i64> @llvm.masked.sdiv.nxv2i64(<vscale x 2 x i64> <op1>, <vscale x 2 x i64> <op2>, <vscale x 2 x i1> <mask>)

<a id="id1560"></a>

##### Overview:

Performs signed division ([sdiv](instructions-arithmetic.md#i-sdiv)) of two vectors of integers, but only on enabled lanes.

<a id="id1561"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type.

<a id="id1562"></a>

##### Semantics:

Follows the same semantics as [sdiv](instructions-arithmetic.md#i-sdiv) with the exception that disabled lanes cannot produce undefined behaviour and always result in poison.

<a id="llvm-masked-urem-intrinsics"></a>

#### ‘`llvm.masked.urem.*`’ Intrinsics

<a id="id1563"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <8 x i32> @llvm.masked.urem.v8i32(<8 x i32> <op1>, <8 x i32> <op2>, <8 x i1> <mask>)
    declare <vscale x 2 x i64> @llvm.masked.urem.nxv2i64(<vscale x 2 x i64> <op1>, <vscale x 2 x i64> <op2>, <vscale x 2 x i1> <mask>)

<a id="id1564"></a>

##### Overview:

Computes the remainder from the unsigned division ([urem](instructions-arithmetic.md#i-urem)) of two vectors of integers, but only on enabled lanes.

<a id="id1565"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type.

<a id="id1566"></a>

##### Semantics:

Follows the same semantics as [urem](instructions-arithmetic.md#i-urem) with the exception that disabled lanes cannot produce undefined behaviour and always result in poison.

<a id="llvm-masked-srem-intrinsics"></a>

#### ‘`llvm.masked.srem.*`’ Intrinsics

<a id="id1567"></a>

##### Syntax:

This is an overloaded intrinsic.

    declare <8 x i32> @llvm.masked.srem.v8i32(<8 x i32> <op1>, <8 x i32> <op2>, <8 x i1> <mask>)
    declare <vscale x 2 x i64> @llvm.masked.srem.nxv2i64(<vscale x 2 x i64> <op1>, <vscale x 2 x i64> <op2>, <vscale x 2 x i1> <mask>)

<a id="id1568"></a>

##### Overview:

Computes the remainder from the signed division ([srem](instructions-arithmetic.md#i-srem)) of two vectors of integers, but only on enabled lanes.

<a id="id1569"></a>

##### Arguments:

The first two arguments and the result have the same vector of integer type. The third argument is the vector mask and has the same number of elements as the result vector type.

<a id="id1570"></a>

##### Semantics:

Follows the same semantics as [srem](instructions-arithmetic.md#i-srem) with the exception that disabled lanes cannot produce undefined behaviour and always result in poison.
