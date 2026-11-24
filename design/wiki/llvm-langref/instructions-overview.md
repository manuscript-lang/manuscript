[Wiki](../index.md) › [LLVM LangRef](index.md)

# Instruction reference overview

LLVM 23.1.0 Language Reference, part of the [index](index.md). Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html>. License: Apache-2.0 with LLVM exception.

<a id="instruction-reference"></a>

## Instruction Reference

The LLVM instruction set consists of several different classifications of instructions: [terminator instructions](instructions-terminators.md#terminators), [binary instructions](instructions-arithmetic.md#binaryops), [bitwise binary instructions](instructions-arithmetic.md#bitwiseops), [memory instructions](instructions-memory.md#memoryops), and [other instructions](instructions-other.md#otherops). There are also [debug records](instructions-vector-aggregate.md#debugrecords), which are not instructions themselves but are printed interleaved with instructions to describe changes in the state of the program’s debug information at each position in the program’s execution.
