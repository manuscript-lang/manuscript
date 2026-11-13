[Wiki](../index.md) › [LLVM LangRef](index.md)

# Introduction and syntax

LLVM 23.1.0 Language Reference, part of the [index](index.md). Source: <https://releases.llvm.org/23.1.0/docs/LangRef.html>. License: Apache-2.0 with LLVM exception.

# LLVM Language Reference Manual

- [Abstract](#abstract)

- [Introduction](#introduction)

  - [Well-Formedness](#well-formedness)

- [Syntax](#syntax)

  - [Identifiers](#identifiers)

  - [String constants](#string-constants)

- [High Level Structure](high-level-structure.md#high-level-structure)

  - [Module Structure](high-level-structure.md#module-structure)

  - [Linkage Types](high-level-structure.md#linkage-types)

  - [Calling Conventions](high-level-structure.md#calling-conventions)

  - [Visibility Styles](high-level-structure.md#visibility-styles)

  - [DLL Storage Classes](high-level-structure.md#dll-storage-classes)

  - [Thread Local Storage Models](high-level-structure.md#thread-local-storage-models)

  - [Runtime Preemption Specifiers](high-level-structure.md#runtime-preemption-specifiers)

  - [Structure Types](high-level-structure.md#structure-types)

  - [Non-Integral Pointer Type](high-level-structure.md#non-integral-pointer-type)

    - [Pointers with non-address bits](high-level-structure.md#pointers-with-non-address-bits)

    - [Unstable pointer representation](high-level-structure.md#unstable-pointer-representation)

    - [Pointers with external state](high-level-structure.md#pointers-with-external-state)

  - [Global Variables](high-level-structure.md#global-variables)

  - [Functions](high-level-structure.md#functions)

  - [Aliases](high-level-structure.md#aliases)

  - [IFuncs](high-level-structure.md#ifuncs)

  - [Comdats](high-level-structure.md#comdats)

  - [Named Metadata](high-level-structure.md#named-metadata)

  - [Parameter Attributes](high-level-structure.md#parameter-attributes)

  - [Garbage Collector Strategy Names](high-level-structure.md#garbage-collector-strategy-names)

  - [Prefix Data](high-level-structure.md#prefix-data)

  - [Prologue Data](high-level-structure.md#prologue-data)

  - [Personality Function](high-level-structure.md#personality-function)

  - [Attribute Groups](high-level-structure.md#attribute-groups)

  - [Function Attributes](high-level-structure.md#function-attributes)

  - [Call Site Attributes](high-level-structure.md#call-site-attributes)

  - [Global Attributes](high-level-structure.md#global-attributes)

  - [Operand Bundles](high-level-structure.md#operand-bundles)

    - [Deoptimization Operand Bundles](high-level-structure.md#deoptimization-operand-bundles)

    - [Funclet Operand Bundles](high-level-structure.md#funclet-operand-bundles)

    - [GC Transition Operand Bundles](high-level-structure.md#gc-transition-operand-bundles)

    - [Assume Operand Bundles](high-level-structure.md#assume-operand-bundles)

    - [Preallocated Operand Bundles](high-level-structure.md#preallocated-operand-bundles)

    - [GC Live Operand Bundles](high-level-structure.md#gc-live-operand-bundles)

    - [ObjC ARC Attached Call Operand Bundles](high-level-structure.md#objc-arc-attached-call-operand-bundles)

    - [Pointer Authentication Operand Bundles](high-level-structure.md#pointer-authentication-operand-bundles)

    - [KCFI Operand Bundles](high-level-structure.md#kcfi-operand-bundles)

    - [Convergence Control Operand Bundles](high-level-structure.md#convergence-control-operand-bundles)

    - [Deactivation Symbol Operand Bundles](high-level-structure.md#deactivation-symbol-operand-bundles)

  - [Module-Level Inline Assembly](high-level-structure.md#module-level-inline-assembly)

  - [Data Layout](high-level-structure.md#data-layout)

  - [Target Triple](high-level-structure.md#target-triple)

  - [Allocated Objects](high-level-structure.md#allocated-objects)

  - [Object Lifetime](high-level-structure.md#object-lifetime)

  - [Pointer Aliasing Rules](high-level-structure.md#pointer-aliasing-rules)

  - [Pointer Capture](high-level-structure.md#pointer-capture)

    - [Provenance capture](high-level-structure.md#provenance-capture)

    - [Address capture](high-level-structure.md#address-capture)

    - [Location specific capture](high-level-structure.md#location-specific-capture)

    - [Inference](high-level-structure.md#inference)

  - [Volatile Memory Accesses](high-level-structure.md#volatile-memory-accesses)

  - [Memory Model for Concurrent Operations](high-level-structure.md#memory-model-for-concurrent-operations)

  - [Atomic Memory Ordering Constraints](high-level-structure.md#atomic-memory-ordering-constraints)

  - [Elementwise Atomic Operations](high-level-structure.md#elementwise-atomic-operations)

  - [Floating-Point Environment](high-level-structure.md#floating-point-environment)

  - [Behavior of Floating-Point NaN values](high-level-structure.md#behavior-of-floating-point-nan-values)

  - [Floating-Point Semantics](high-level-structure.md#floating-point-semantics)

  - [Fast-Math Flags](high-level-structure.md#fast-math-flags)

    - [Rewrite-based flags](high-level-structure.md#rewrite-based-flags)

  - [Use-list Order Directives](high-level-structure.md#use-list-order-directives)

  - [Source Filename](high-level-structure.md#source-filename)

- [Type System](type-system.md#type-system)

  - [Void Type](type-system.md#void-type)

  - [Function Type](type-system.md#function-type)

  - [Opaque Structure Types](type-system.md#opaque-structure-types)

  - [First Class Types](type-system.md#first-class-types)

    - [Single Value Types](type-system.md#single-value-types)

    - [Label Type](type-system.md#label-type)

    - [Token Type](type-system.md#token-type)

    - [Metadata Type](type-system.md#metadata-type)

    - [Aggregate Types](type-system.md#aggregate-types)

- [Constants](constants.md#constants)

  - [Simple Constants](constants.md#simple-constants)

  - [Complex Constants](constants.md#complex-constants)

  - [Global Variable and Function Addresses](constants.md#global-variable-and-function-addresses)

  - [Undefined Values](constants.md#undefined-values)

  - [Poison Values](constants.md#poison-values)

  - [Well-Defined Values](constants.md#well-defined-values)

  - [Addresses of Basic Blocks](constants.md#addresses-of-basic-blocks)

  - [DSO Local Equivalent](constants.md#dso-local-equivalent)

  - [No CFI](constants.md#no-cfi)

  - [Pointer Authentication Constants](constants.md#pointer-authentication-constants)

  - [Constant Expressions](constants.md#constant-expressions)

- [Other Values](constants.md#other-values)

  - [Inline Assembler Expressions](constants.md#inline-assembler-expressions)

    - [Inline Asm Constraint String](constants.md#inline-asm-constraint-string)

    - [Asm template argument modifiers](constants.md#asm-template-argument-modifiers)

    - [Inline Asm Metadata](constants.md#inline-asm-metadata)

- [Metadata](metadata.md#metadata)

  - [Metadata Strings (`MDString`)](metadata.md#metadata-strings-mdstring)

  - [Metadata Nodes (`MDNode`)](metadata.md#metadata-nodes-mdnode)

    - [Specialized Metadata Nodes](metadata.md#specialized-metadata-nodes)

    - [‘`tbaa`’ Metadata](metadata.md#tbaa-metadata)

    - [‘`tbaa.struct`’ Metadata](metadata.md#tbaa-struct-metadata)

    - [‘`noalias`’ and ‘`alias.scope`’ Metadata](metadata.md#noalias-and-alias-scope-metadata)

    - [‘`fpmath`’ Metadata](metadata.md#fpmath-metadata)

    - [‘`range`’ Metadata](metadata.md#range-metadata)

    - [‘`nofpclass`’ Metadata](metadata.md#nofpclass-metadata)

    - [‘`absolute_symbol`’ Metadata](metadata.md#absolute-symbol-metadata)

    - [‘`callees`’ Metadata](metadata.md#callees-metadata)

    - [‘`callback`’ Metadata](metadata.md#callback-metadata)

    - [‘`exclude`’ Metadata](metadata.md#exclude-metadata)

    - [‘`unpredictable`’ Metadata](metadata.md#unpredictable-metadata)

    - [‘`dereferenceable`’ Metadata](metadata.md#dereferenceable-metadata)

    - [‘`dereferenceable_or_null`’ Metadata](metadata.md#dereferenceable-or-null-metadata)

    - [‘`captures`’ Metadata](metadata.md#captures-metadata)

    - [‘`mem.cache_hint`’ Metadata](metadata.md#mem-cache-hint-metadata)

    - [‘`llvm.loop`’](metadata.md#llvm-loop)

    - [‘`llvm.loop.disable_nonforced`’](metadata.md#llvm-loop-disable-nonforced)

    - [‘`llvm.loop.vectorize`’ and ‘`llvm.loop.interleave`’](metadata.md#llvm-loop-vectorize-and-llvm-loop-interleave)

    - [‘`llvm.loop.interleave.count`’ Metadata](metadata.md#llvm-loop-interleave-count-metadata)

    - [‘`llvm.loop.vectorize.enable`’ Metadata](metadata.md#llvm-loop-vectorize-enable-metadata)

    - [‘`llvm.loop.vectorize.predicate.enable`’ Metadata](metadata.md#llvm-loop-vectorize-predicate-enable-metadata)

    - [‘`llvm.loop.vectorize.scalable.enable`’ Metadata](metadata.md#llvm-loop-vectorize-scalable-enable-metadata)

    - [‘`llvm.loop.vectorize.width`’ Metadata](metadata.md#llvm-loop-vectorize-width-metadata)

    - [‘`llvm.loop.vectorize.followup_vectorized`’ Metadata](metadata.md#llvm-loop-vectorize-followup-vectorized-metadata)

    - [‘`llvm.loop.vectorize.followup_epilogue`’ Metadata](metadata.md#llvm-loop-vectorize-followup-epilogue-metadata)

    - [‘`llvm.loop.vectorize.followup_all`’ Metadata](metadata.md#llvm-loop-vectorize-followup-all-metadata)

    - [‘`llvm.loop.vectorize.body`’ Metadata](metadata.md#llvm-loop-vectorize-body-metadata)

    - [‘`llvm.loop.vectorize.epilogue`’ Metadata](metadata.md#llvm-loop-vectorize-epilogue-metadata)

    - [‘`llvm.loop.unroll`’](metadata.md#llvm-loop-unroll)

    - [‘`llvm.loop.unroll.count`’ Metadata](metadata.md#llvm-loop-unroll-count-metadata)

    - [‘`llvm.loop.unroll.disable`’ Metadata](metadata.md#llvm-loop-unroll-disable-metadata)

    - [‘`llvm.loop.unroll.runtime.disable`’ Metadata](metadata.md#llvm-loop-unroll-runtime-disable-metadata)

    - [‘`llvm.loop.unroll.enable`’ Metadata](metadata.md#llvm-loop-unroll-enable-metadata)

    - [‘`llvm.loop.unroll.full`’ Metadata](metadata.md#llvm-loop-unroll-full-metadata)

    - [‘`llvm.loop.unroll.followup`’ Metadata](metadata.md#llvm-loop-unroll-followup-metadata)

    - [‘`llvm.loop.unroll.followup_remainder`’ Metadata](metadata.md#llvm-loop-unroll-followup-remainder-metadata)

    - [‘`llvm.loop.unroll_and_jam`’](metadata.md#llvm-loop-unroll-and-jam)

    - [‘`llvm.loop.unroll_and_jam.count`’ Metadata](metadata.md#llvm-loop-unroll-and-jam-count-metadata)

    - [‘`llvm.loop.unroll_and_jam.disable`’ Metadata](metadata.md#llvm-loop-unroll-and-jam-disable-metadata)

    - [‘`llvm.loop.unroll_and_jam.enable`’ Metadata](metadata.md#llvm-loop-unroll-and-jam-enable-metadata)

    - [‘`llvm.loop.unroll_and_jam.followup_outer`’ Metadata](metadata.md#llvm-loop-unroll-and-jam-followup-outer-metadata)

    - [‘`llvm.loop.unroll_and_jam.followup_inner`’ Metadata](metadata.md#llvm-loop-unroll-and-jam-followup-inner-metadata)

    - [‘`llvm.loop.unroll_and_jam.followup_remainder_outer`’ Metadata](metadata.md#llvm-loop-unroll-and-jam-followup-remainder-outer-metadata)

    - [‘`llvm.loop.unroll_and_jam.followup_remainder_inner`’ Metadata](metadata.md#llvm-loop-unroll-and-jam-followup-remainder-inner-metadata)

    - [‘`llvm.loop.unroll_and_jam.followup_all`’ Metadata](metadata.md#llvm-loop-unroll-and-jam-followup-all-metadata)

    - [‘`llvm.loop.licm_versioning.disable`’ Metadata](metadata.md#llvm-loop-licm-versioning-disable-metadata)

    - [‘`llvm.loop.distribute.enable`’ Metadata](metadata.md#llvm-loop-distribute-enable-metadata)

    - [‘`llvm.loop.distribute.followup_coincident`’ Metadata](metadata.md#llvm-loop-distribute-followup-coincident-metadata)

    - [‘`llvm.loop.distribute.followup_sequential`’ Metadata](metadata.md#llvm-loop-distribute-followup-sequential-metadata)

    - [‘`llvm.loop.distribute.followup_fallback`’ Metadata](metadata.md#llvm-loop-distribute-followup-fallback-metadata)

    - [‘`llvm.loop.distribute.followup_all`’ Metadata](metadata.md#llvm-loop-distribute-followup-all-metadata)

    - [‘`llvm.loop.isdistributed`’ Metadata](metadata.md#llvm-loop-isdistributed-metadata)

    - [‘`llvm.loop.estimated_trip_count`’ Metadata](metadata.md#llvm-loop-estimated-trip-count-metadata)

    - [‘`llvm.licm.disable`’ Metadata](metadata.md#llvm-licm-disable-metadata)

    - [‘`llvm.access.group`’ Metadata](metadata.md#llvm-access-group-metadata)

    - [‘`llvm.loop.parallel_accesses`’ Metadata](metadata.md#llvm-loop-parallel-accesses-metadata)

    - [‘`llvm.loop.mustprogress`’ Metadata](metadata.md#llvm-loop-mustprogress-metadata)

    - [‘`irr_loop`’ Metadata](metadata.md#irr-loop-metadata)

    - [‘`invariant.load`’ Metadata](metadata.md#invariant-load-metadata)

    - [‘`invariant.group`’ Metadata](metadata.md#invariant-group-metadata)

    - [‘`type`’ Metadata](metadata.md#type-metadata)

    - [‘`callee_type`’ Metadata](metadata.md#callee-type-metadata)

    - [‘`callgraph`’ Metadata](metadata.md#callgraph-metadata)

    - [‘`associated`’ Metadata](metadata.md#associated-metadata)

    - [‘`prof`’ Metadata](metadata.md#prof-metadata)

    - [‘`annotation`’ Metadata](metadata.md#annotation-metadata)

    - [‘`func_sanitize`’ Metadata](metadata.md#func-sanitize-metadata)

    - [‘`kcfi_type`’ Metadata](metadata.md#kcfi-type-metadata)

    - [‘`pcsections`’ Metadata](metadata.md#pcsections-metadata)

    - [‘`memprof`’ Metadata](metadata.md#memprof-metadata)

    - [‘`callsite`’ Metadata](metadata.md#callsite-metadata)

    - [‘`noalias.addrspace`’ Metadata](metadata.md#noalias-addrspace-metadata)

    - [‘`mmra`’ Metadata](metadata.md#mmra-metadata)

    - [‘`nofree`’ Metadata](metadata.md#nofree-metadata)

    - [‘`alloc_token`’ Metadata](metadata.md#alloc-token-metadata)

    - [‘`stack-protector`’ Metadata](metadata.md#stack-protector-metadata)

    - [‘`implicit.ref`’ Metadata](metadata.md#implicit-ref-metadata)

    - [‘`inline_history`’ Metadata](metadata.md#inline-history-metadata)

    - [‘`elf_section_properties`’ Metadata](metadata.md#elf-section-properties-metadata)

- [Module Flags Metadata](named-metadata-and-module-flags.md#module-flags-metadata)

  - [Synthesized Functions Module Flags Metadata](named-metadata-and-module-flags.md#synthesized-functions-module-flags-metadata)

  - [Objective-C Garbage Collection Module Flags Metadata](named-metadata-and-module-flags.md#objective-c-garbage-collection-module-flags-metadata)

  - [C type width Module Flags Metadata](named-metadata-and-module-flags.md#c-type-width-module-flags-metadata)

  - [Stack Alignment Metadata](named-metadata-and-module-flags.md#stack-alignment-metadata)

  - [Windows Control Flow Guard Metadata](named-metadata-and-module-flags.md#windows-control-flow-guard-metadata)

  - [Other Module Flags](named-metadata-and-module-flags.md#other-module-flags)

- [Embedded Objects Names Metadata](named-metadata-and-module-flags.md#embedded-objects-names-metadata)

- [Automatic Linker Flags Named Metadata](named-metadata-and-module-flags.md#automatic-linker-flags-named-metadata)

- [Dependent Libs Named Metadata](named-metadata-and-module-flags.md#dependent-libs-named-metadata)

- [‘`llvm.errno.tbaa`’ Named Metadata](named-metadata-and-module-flags.md#llvm-errno-tbaa-named-metadata)

- [ThinLTO Summary](thinlto-and-global-variables.md#thinlto-summary)

  - [Module Path Summary Entry](thinlto-and-global-variables.md#module-path-summary-entry)

  - [Global Value Summary Entry](thinlto-and-global-variables.md#global-value-summary-entry)

    - [Function Summary](thinlto-and-global-variables.md#function-summary)

    - [Global Variable Summary](thinlto-and-global-variables.md#global-variable-summary)

    - [Alias Summary](thinlto-and-global-variables.md#alias-summary)

    - [Function Flags](thinlto-and-global-variables.md#function-flags)

    - [Calls](thinlto-and-global-variables.md#calls)

    - [Params](thinlto-and-global-variables.md#params)

    - [Refs](thinlto-and-global-variables.md#refs)

    - [TypeIdInfo](thinlto-and-global-variables.md#typeidinfo)

  - [Type ID Summary Entry](thinlto-and-global-variables.md#type-id-summary-entry)

- [Intrinsic Global Variables](thinlto-and-global-variables.md#intrinsic-global-variables)

  - [The ‘`llvm.used`’ Global Variable](thinlto-and-global-variables.md#the-llvm-used-global-variable)

  - [The ‘`llvm.compiler.used`’ Global Variable](thinlto-and-global-variables.md#the-llvm-compiler-used-global-variable)

  - [The ‘`llvm.global_ctors`’ Global Variable](thinlto-and-global-variables.md#the-llvm-global-ctors-global-variable)

  - [The ‘`llvm.global_dtors`’ Global Variable](thinlto-and-global-variables.md#the-llvm-global-dtors-global-variable)

- [Instruction Reference](instructions-overview.md#instruction-reference)

  - [Terminator Instructions](instructions-terminators.md#terminator-instructions)

    - [‘`ret`’ Instruction](instructions-terminators.md#ret-instruction)

    - [‘`br`’ Instruction](instructions-terminators.md#br-instruction)

    - [‘`switch`’ Instruction](instructions-terminators.md#switch-instruction)

    - [‘`indirectbr`’ Instruction](instructions-terminators.md#indirectbr-instruction)

    - [‘`invoke`’ Instruction](instructions-terminators.md#invoke-instruction)

    - [‘`callbr`’ Instruction](instructions-terminators.md#callbr-instruction)

    - [‘`resume`’ Instruction](instructions-terminators.md#resume-instruction)

    - [‘`catchswitch`’ Instruction](instructions-terminators.md#catchswitch-instruction)

    - [‘`catchret`’ Instruction](instructions-terminators.md#catchret-instruction)

    - [‘`cleanupret`’ Instruction](instructions-terminators.md#cleanupret-instruction)

    - [‘`unreachable`’ Instruction](instructions-terminators.md#unreachable-instruction)

  - [Unary Operations](instructions-arithmetic.md#unary-operations)

    - [‘`fneg`’ Instruction](instructions-arithmetic.md#fneg-instruction)

  - [Binary Operations](instructions-arithmetic.md#binary-operations)

    - [‘`add`’ Instruction](instructions-arithmetic.md#add-instruction)

    - [‘`fadd`’ Instruction](instructions-arithmetic.md#fadd-instruction)

    - [‘`sub`’ Instruction](instructions-arithmetic.md#sub-instruction)

    - [‘`fsub`’ Instruction](instructions-arithmetic.md#fsub-instruction)

    - [‘`mul`’ Instruction](instructions-arithmetic.md#mul-instruction)

    - [‘`fmul`’ Instruction](instructions-arithmetic.md#fmul-instruction)

    - [‘`udiv`’ Instruction](instructions-arithmetic.md#udiv-instruction)

    - [‘`sdiv`’ Instruction](instructions-arithmetic.md#sdiv-instruction)

    - [‘`fdiv`’ Instruction](instructions-arithmetic.md#fdiv-instruction)

    - [‘`urem`’ Instruction](instructions-arithmetic.md#urem-instruction)

    - [‘`srem`’ Instruction](instructions-arithmetic.md#srem-instruction)

    - [‘`frem`’ Instruction](instructions-arithmetic.md#frem-instruction)

  - [Bitwise Binary Operations](instructions-arithmetic.md#bitwise-binary-operations)

    - [‘`shl`’ Instruction](instructions-arithmetic.md#shl-instruction)

    - [‘`lshr`’ Instruction](instructions-arithmetic.md#lshr-instruction)

    - [‘`ashr`’ Instruction](instructions-arithmetic.md#ashr-instruction)

    - [‘`and`’ Instruction](instructions-arithmetic.md#and-instruction)

    - [‘`or`’ Instruction](instructions-arithmetic.md#or-instruction)

    - [‘`xor`’ Instruction](instructions-arithmetic.md#xor-instruction)

  - [Vector Operations](instructions-vector-aggregate.md#vector-operations)

    - [‘`extractelement`’ Instruction](instructions-vector-aggregate.md#extractelement-instruction)

    - [‘`insertelement`’ Instruction](instructions-vector-aggregate.md#insertelement-instruction)

    - [‘`shufflevector`’ Instruction](instructions-vector-aggregate.md#shufflevector-instruction)

  - [Aggregate Operations](instructions-vector-aggregate.md#aggregate-operations)

    - [‘`extractvalue`’ Instruction](instructions-vector-aggregate.md#extractvalue-instruction)

    - [‘`insertvalue`’ Instruction](instructions-vector-aggregate.md#insertvalue-instruction)

  - [Memory Access and Addressing Operations](instructions-memory.md#memory-access-and-addressing-operations)

    - [‘`alloca`’ Instruction](instructions-memory.md#alloca-instruction)

    - [‘`load`’ Instruction](instructions-memory.md#load-instruction)

    - [‘`store`’ Instruction](instructions-memory.md#store-instruction)

    - [‘`fence`’ Instruction](instructions-memory.md#fence-instruction)

    - [‘`cmpxchg`’ Instruction](instructions-memory.md#cmpxchg-instruction)

    - [‘`atomicrmw`’ Instruction](instructions-memory.md#atomicrmw-instruction)

    - [‘`getelementptr`’ Instruction](instructions-memory.md#getelementptr-instruction)

  - [Conversion Operations](instructions-conversion.md#conversion-operations)

    - [‘`trunc .. to`’ Instruction](instructions-conversion.md#trunc-to-instruction)

    - [‘`zext .. to`’ Instruction](instructions-conversion.md#zext-to-instruction)

    - [‘`sext .. to`’ Instruction](instructions-conversion.md#sext-to-instruction)

    - [‘`fptrunc .. to`’ Instruction](instructions-conversion.md#fptrunc-to-instruction)

    - [‘`fpext .. to`’ Instruction](instructions-conversion.md#fpext-to-instruction)

    - [‘`fptoui .. to`’ Instruction](instructions-conversion.md#fptoui-to-instruction)

    - [‘`fptosi .. to`’ Instruction](instructions-conversion.md#fptosi-to-instruction)

    - [‘`uitofp .. to`’ Instruction](instructions-conversion.md#uitofp-to-instruction)

    - [‘`sitofp .. to`’ Instruction](instructions-conversion.md#sitofp-to-instruction)

    - [‘`ptrtoint .. to`’ Instruction](instructions-conversion.md#ptrtoint-to-instruction)

    - [‘`ptrtoaddr .. to`’ Instruction](instructions-conversion.md#ptrtoaddr-to-instruction)

    - [‘`inttoptr .. to`’ Instruction](instructions-conversion.md#inttoptr-to-instruction)

    - [‘`bitcast .. to`’ Instruction](instructions-conversion.md#bitcast-to-instruction)

    - [‘`addrspacecast .. to`’ Instruction](instructions-conversion.md#addrspacecast-to-instruction)

  - [Other Operations](instructions-other.md#other-operations)

    - [‘`icmp`’ Instruction](instructions-other.md#icmp-instruction)

    - [‘`fcmp`’ Instruction](instructions-other.md#fcmp-instruction)

    - [‘`phi`’ Instruction](instructions-other.md#phi-instruction)

    - [‘`select`’ Instruction](instructions-other.md#select-instruction)

    - [‘`freeze`’ Instruction](instructions-other.md#freeze-instruction)

    - [‘`call`’ Instruction](instructions-other.md#call-instruction)

    - [‘`va_arg`’ Instruction](instructions-other.md#va-arg-instruction)

    - [‘`landingpad`’ Instruction](instructions-other.md#landingpad-instruction)

    - [‘`catchpad`’ Instruction](instructions-other.md#catchpad-instruction)

    - [‘`cleanuppad`’ Instruction](instructions-other.md#cleanuppad-instruction)

  - [Debug Records](instructions-vector-aggregate.md#debug-records)

- [Intrinsic Functions](intrinsics-overview-and-basic.md#intrinsic-functions)

  - [Variable Argument Handling Intrinsics](intrinsics-overview-and-basic.md#variable-argument-handling-intrinsics)

    - [‘`llvm.va_start`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-va-start-intrinsic)

    - [‘`llvm.va_end`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-va-end-intrinsic)

    - [‘`llvm.va_copy`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-va-copy-intrinsic)

  - [Accurate Garbage Collection Intrinsics](intrinsics-overview-and-basic.md#accurate-garbage-collection-intrinsics)

    - [‘`llvm.gcroot`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-gcroot-intrinsic)

    - [‘`llvm.gcread`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-gcread-intrinsic)

    - [‘`llvm.gcwrite`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-gcwrite-intrinsic)

    - [‘`llvm.experimental.gc.statepoint`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-experimental-gc-statepoint-intrinsic)

    - [‘`llvm.experimental.gc.result`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-experimental-gc-result-intrinsic)

    - [‘`llvm.experimental.gc.relocate`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-experimental-gc-relocate-intrinsic)

    - [‘`llvm.experimental.gc.get.pointer.base`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-experimental-gc-get-pointer-base-intrinsic)

    - [‘`llvm.experimental.gc.get.pointer.offset`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-experimental-gc-get-pointer-offset-intrinsic)

  - [Code Generator Intrinsics](intrinsics-overview-and-basic.md#code-generator-intrinsics)

    - [‘`llvm.returnaddress`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-returnaddress-intrinsic)

    - [‘`llvm.addressofreturnaddress`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-addressofreturnaddress-intrinsic)

    - [‘`llvm.sponentry`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-sponentry-intrinsic)

    - [‘`llvm.stackaddress`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-stackaddress-intrinsic)

    - [‘`llvm.frameaddress`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-frameaddress-intrinsic)

    - [‘`llvm.swift.async.context.addr`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-swift-async-context-addr-intrinsic)

    - [‘`llvm.localescape`’ and ‘`llvm.localrecover`’ Intrinsics](intrinsics-overview-and-basic.md#llvm-localescape-and-llvm-localrecover-intrinsics)

    - [‘`llvm.seh.try.begin`’ and ‘`llvm.seh.try.end`’ Intrinsics](intrinsics-overview-and-basic.md#llvm-seh-try-begin-and-llvm-seh-try-end-intrinsics)

    - [‘`llvm.seh.scope.begin`’ and ‘`llvm.seh.scope.end`’ Intrinsics](intrinsics-overview-and-basic.md#llvm-seh-scope-begin-and-llvm-seh-scope-end-intrinsics)

    - [‘`llvm.read_register`’, ‘`llvm.read_volatile_register`’, ‘`llvm.write_register`’, and ‘`llvm.write_volatile_register`’ Intrinsics](intrinsics-overview-and-basic.md#llvm-read-register-llvm-read-volatile-register-llvm-write-register-and-llvm-write-volatile-register-intrinsics)

    - [‘`llvm.stacksave`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-stacksave-intrinsic)

    - [‘`llvm.stackrestore`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-stackrestore-intrinsic)

    - [‘`llvm.structured.gep`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-structured-gep-intrinsic)

    - [‘`llvm.structured.alloca`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-structured-alloca-intrinsic)

    - [‘`llvm.get.dynamic.area.offset`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-get-dynamic-area-offset-intrinsic)

    - [‘`llvm.prefetch`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-prefetch-intrinsic)

    - [‘`llvm.pcmarker`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-pcmarker-intrinsic)

    - [‘`llvm.readcyclecounter`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-readcyclecounter-intrinsic)

    - [‘`llvm.readsteadycounter`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-readsteadycounter-intrinsic)

    - [‘`llvm.clear_cache`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-clear-cache-intrinsic)

    - [‘`llvm.instrprof.increment`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-instrprof-increment-intrinsic)

    - [‘`llvm.instrprof.increment.step`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-instrprof-increment-step-intrinsic)

    - [‘`llvm.instrprof.callsite`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-instrprof-callsite-intrinsic)

    - [‘`llvm.instrprof.timestamp`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-instrprof-timestamp-intrinsic)

    - [‘`llvm.instrprof.cover`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-instrprof-cover-intrinsic)

    - [‘`llvm.instrprof.value.profile`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-instrprof-value-profile-intrinsic)

    - [‘`llvm.instrprof.mcdc.parameters`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-instrprof-mcdc-parameters-intrinsic)

    - [‘`llvm.instrprof.mcdc.tvbitmap.update`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-instrprof-mcdc-tvbitmap-update-intrinsic)

    - [‘`llvm.thread.pointer`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-thread-pointer-intrinsic)

    - [‘`llvm.call.preallocated.setup`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-call-preallocated-setup-intrinsic)

    - [‘`llvm.call.preallocated.arg`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-call-preallocated-arg-intrinsic)

    - [‘`llvm.call.preallocated.teardown`’ Intrinsic](intrinsics-overview-and-basic.md#llvm-call-preallocated-teardown-intrinsic)

  - [Standard C/C++ Library Intrinsics](intrinsics-libc-and-arithmetic.md#standard-c-c-library-intrinsics)

    - [‘`llvm.abs.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-abs-intrinsic)

    - [‘`llvm.smax.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-smax-intrinsic)

    - [‘`llvm.smin.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-smin-intrinsic)

    - [‘`llvm.umax.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-umax-intrinsic)

    - [‘`llvm.umin.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-umin-intrinsic)

    - [‘`llvm.scmp.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-scmp-intrinsic)

    - [‘`llvm.ucmp.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-ucmp-intrinsic)

    - [‘`llvm.memcpy`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-memcpy-intrinsic)

    - [‘`llvm.memcpy.inline`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-memcpy-inline-intrinsic)

    - [‘`llvm.memmove`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-memmove-intrinsic)

    - [‘`llvm.memset.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-memset-intrinsics)

    - [‘`llvm.memset.inline`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-memset-inline-intrinsic)

    - [‘`llvm.experimental.memset.pattern`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-experimental-memset-pattern-intrinsic)

    - [‘`llvm.sqrt.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-sqrt-intrinsic)

    - [‘`llvm.powi.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-powi-intrinsic)

    - [‘`llvm.sin.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-sin-intrinsic)

    - [‘`llvm.cos.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-cos-intrinsic)

    - [‘`llvm.tan.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-tan-intrinsic)

    - [‘`llvm.asin.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-asin-intrinsic)

    - [‘`llvm.acos.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-acos-intrinsic)

    - [‘`llvm.atan.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-atan-intrinsic)

    - [‘`llvm.atan2.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-atan2-intrinsic)

    - [‘`llvm.sinh.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-sinh-intrinsic)

    - [‘`llvm.cosh.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-cosh-intrinsic)

    - [‘`llvm.tanh.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-tanh-intrinsic)

    - [‘`llvm.sincos.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-sincos-intrinsic)

    - [‘`llvm.sincospi.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-sincospi-intrinsic)

    - [‘`llvm.modf.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-modf-intrinsic)

    - [‘`llvm.pow.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-pow-intrinsic)

    - [‘`llvm.exp.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-exp-intrinsic)

    - [‘`llvm.exp2.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-exp2-intrinsic)

    - [‘`llvm.exp10.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-exp10-intrinsic)

    - [‘`llvm.ldexp.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-ldexp-intrinsic)

    - [‘`llvm.frexp.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-frexp-intrinsic)

    - [‘`llvm.log.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-log-intrinsic)

    - [‘`llvm.log10.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-log10-intrinsic)

    - [‘`llvm.log2.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-log2-intrinsic)

    - [‘`llvm.fma.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-fma-intrinsic)

    - [‘`llvm.fabs.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-fabs-intrinsic)

    - [Floating-point min/max intrinsics comparison](intrinsics-libc-and-arithmetic.md#floating-point-min-max-intrinsics-comparison)

    - [‘`llvm.minnum.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-minnum-intrinsic)

    - [‘`llvm.maxnum.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-maxnum-intrinsic)

    - [‘`llvm.minimum.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-minimum-intrinsic)

    - [‘`llvm.maximum.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-maximum-intrinsic)

    - [‘`llvm.minimumnum.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-minimumnum-intrinsic)

    - [‘`llvm.maximumnum.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-maximumnum-intrinsic)

    - [‘`llvm.copysign.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-copysign-intrinsic)

    - [‘`llvm.floor.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-floor-intrinsic)

    - [‘`llvm.ceil.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-ceil-intrinsic)

    - [‘`llvm.trunc.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-trunc-intrinsic)

    - [‘`llvm.rint.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-rint-intrinsic)

    - [‘`llvm.nearbyint.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-nearbyint-intrinsic)

    - [‘`llvm.round.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-round-intrinsic)

    - [‘`llvm.roundeven.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-roundeven-intrinsic)

    - [‘`llvm.lround.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-lround-intrinsic)

    - [‘`llvm.llround.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-llround-intrinsic)

    - [‘`llvm.lrint.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-lrint-intrinsic)

    - [‘`llvm.llrint.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-llrint-intrinsic)

  - [Bit Manipulation Intrinsics](intrinsics-libc-and-arithmetic.md#bit-manipulation-intrinsics)

    - [‘`llvm.bitreverse.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-bitreverse-intrinsics)

    - [‘`llvm.bswap.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-bswap-intrinsics)

    - [‘`llvm.ctpop.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-ctpop-intrinsic)

    - [‘`llvm.ctlz.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-ctlz-intrinsic)

    - [‘`llvm.cttz.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-cttz-intrinsic)

    - [‘`llvm.fshl.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-fshl-intrinsic)

    - [‘`llvm.fshr.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-fshr-intrinsic)

    - [‘`llvm.clmul.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-clmul-intrinsic)

    - [‘`llvm.pext.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-pext-intrinsic)

    - [‘`llvm.pdep.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-pdep-intrinsic)

  - [Arithmetic with Overflow Intrinsics](intrinsics-libc-and-arithmetic.md#arithmetic-with-overflow-intrinsics)

    - [‘`llvm.sadd.with.overflow.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-sadd-with-overflow-intrinsics)

    - [‘`llvm.uadd.with.overflow.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-uadd-with-overflow-intrinsics)

    - [‘`llvm.ssub.with.overflow.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-ssub-with-overflow-intrinsics)

    - [‘`llvm.usub.with.overflow.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-usub-with-overflow-intrinsics)

    - [‘`llvm.smul.with.overflow.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-smul-with-overflow-intrinsics)

    - [‘`llvm.umul.with.overflow.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-umul-with-overflow-intrinsics)

  - [Saturation Arithmetic Intrinsics](intrinsics-libc-and-arithmetic.md#saturation-arithmetic-intrinsics)

    - [‘`llvm.sadd.sat.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-sadd-sat-intrinsics)

    - [‘`llvm.uadd.sat.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-uadd-sat-intrinsics)

    - [‘`llvm.ssub.sat.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-ssub-sat-intrinsics)

    - [‘`llvm.usub.sat.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-usub-sat-intrinsics)

    - [‘`llvm.sshl.sat.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-sshl-sat-intrinsics)

    - [‘`llvm.ushl.sat.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-ushl-sat-intrinsics)

  - [Fixed Point Arithmetic Intrinsics](intrinsics-libc-and-arithmetic.md#fixed-point-arithmetic-intrinsics)

    - [‘`llvm.smul.fix.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-smul-fix-intrinsics)

    - [‘`llvm.umul.fix.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-umul-fix-intrinsics)

    - [‘`llvm.smul.fix.sat.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-smul-fix-sat-intrinsics)

    - [‘`llvm.umul.fix.sat.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-umul-fix-sat-intrinsics)

    - [‘`llvm.sdiv.fix.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-sdiv-fix-intrinsics)

    - [‘`llvm.udiv.fix.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-udiv-fix-intrinsics)

    - [‘`llvm.sdiv.fix.sat.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-sdiv-fix-sat-intrinsics)

    - [‘`llvm.udiv.fix.sat.*`’ Intrinsics](intrinsics-libc-and-arithmetic.md#llvm-udiv-fix-sat-intrinsics)

  - [Specialized Arithmetic Intrinsics](intrinsics-libc-and-arithmetic.md#specialized-arithmetic-intrinsics)

    - [‘`llvm.canonicalize.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-canonicalize-intrinsic)

    - [‘`llvm.fmuladd.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-fmuladd-intrinsic)

  - [Hardware-Loop Intrinsics](intrinsics-libc-and-arithmetic.md#hardware-loop-intrinsics)

    - [‘`llvm.set.loop.iterations.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-set-loop-iterations-intrinsic)

    - [‘`llvm.start.loop.iterations.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-start-loop-iterations-intrinsic)

    - [‘`llvm.test.set.loop.iterations.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-test-set-loop-iterations-intrinsic)

    - [‘`llvm.test.start.loop.iterations.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-test-start-loop-iterations-intrinsic)

    - [‘`llvm.loop.decrement.reg.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-loop-decrement-reg-intrinsic)

    - [‘`llvm.loop.decrement.*`’ Intrinsic](intrinsics-libc-and-arithmetic.md#llvm-loop-decrement-intrinsic)

  - [Vector Reduction Intrinsics](intrinsics-vector.md#vector-reduction-intrinsics)

    - [‘`llvm.vector.reduce.add.*`’ Intrinsic](intrinsics-vector.md#llvm-vector-reduce-add-intrinsic)

    - [‘`llvm.vector.reduce.fadd.*`’ Intrinsic](intrinsics-vector.md#llvm-vector-reduce-fadd-intrinsic)

    - [‘`llvm.vector.reduce.mul.*`’ Intrinsic](intrinsics-vector.md#llvm-vector-reduce-mul-intrinsic)

    - [‘`llvm.vector.reduce.fmul.*`’ Intrinsic](intrinsics-vector.md#llvm-vector-reduce-fmul-intrinsic)

    - [‘`llvm.vector.reduce.and.*`’ Intrinsic](intrinsics-vector.md#llvm-vector-reduce-and-intrinsic)

    - [‘`llvm.vector.reduce.or.*`’ Intrinsic](intrinsics-vector.md#llvm-vector-reduce-or-intrinsic)

    - [‘`llvm.vector.reduce.xor.*`’ Intrinsic](intrinsics-vector.md#llvm-vector-reduce-xor-intrinsic)

    - [‘`llvm.vector.reduce.smax.*`’ Intrinsic](intrinsics-vector.md#llvm-vector-reduce-smax-intrinsic)

    - [‘`llvm.vector.reduce.smin.*`’ Intrinsic](intrinsics-vector.md#llvm-vector-reduce-smin-intrinsic)

    - [‘`llvm.vector.reduce.umax.*`’ Intrinsic](intrinsics-vector.md#llvm-vector-reduce-umax-intrinsic)

    - [‘`llvm.vector.reduce.umin.*`’ Intrinsic](intrinsics-vector.md#llvm-vector-reduce-umin-intrinsic)

    - [‘`llvm.vector.reduce.fmax.*`’ Intrinsic](intrinsics-vector.md#llvm-vector-reduce-fmax-intrinsic)

    - [‘`llvm.vector.reduce.fmin.*`’ Intrinsic](intrinsics-vector.md#llvm-vector-reduce-fmin-intrinsic)

    - [‘`llvm.vector.reduce.fmaximum.*`’ Intrinsic](intrinsics-vector.md#llvm-vector-reduce-fmaximum-intrinsic)

    - [‘`llvm.vector.reduce.fminimum.*`’ Intrinsic](intrinsics-vector.md#llvm-vector-reduce-fminimum-intrinsic)

  - [Vector Partial Reduction Intrinsics](intrinsics-vector.md#vector-partial-reduction-intrinsics)

    - [‘`llvm.vector.partial.reduce.add.*`’ Intrinsic](intrinsics-vector.md#llvm-vector-partial-reduce-add-intrinsic)

    - [‘`llvm.vector.partial.reduce.fadd.*`’ Intrinsic](intrinsics-vector.md#llvm-vector-partial-reduce-fadd-intrinsic)

  - [Vector Manipulation Intrinsics](intrinsics-vector.md#vector-manipulation-intrinsics)

    - [‘`llvm.vector.insert`’ Intrinsic](intrinsics-vector.md#llvm-vector-insert-intrinsic)

    - [‘`llvm.vector.extract`’ Intrinsic](intrinsics-vector.md#llvm-vector-extract-intrinsic)

    - [‘`llvm.vector.reverse`’ Intrinsic](intrinsics-vector.md#llvm-vector-reverse-intrinsic)

    - [‘`llvm.vector.deinterleave2/3/4/5/6/7/8`’ Intrinsic](intrinsics-vector.md#llvm-vector-deinterleave2-3-4-5-6-7-8-intrinsic)

    - [‘`llvm.vector.interleave2/3/4/5/6/7/8`’ Intrinsic](intrinsics-vector.md#llvm-vector-interleave2-3-4-5-6-7-8-intrinsic)

    - [‘`llvm.vector.splice.left`’ Intrinsic](intrinsics-vector.md#llvm-vector-splice-left-intrinsic)

    - [‘`llvm.vector.splice.right`’ Intrinsic](intrinsics-vector.md#llvm-vector-splice-right-intrinsic)

    - [‘`llvm.stepvector`’ Intrinsic](intrinsics-vector.md#llvm-stepvector-intrinsic)

  - [Vector Mask Intrinsics](intrinsics-vector.md#vector-mask-intrinsics)

    - [‘`llvm.get.active.lane.mask.*`’ Intrinsics](intrinsics-vector.md#llvm-get-active-lane-mask-intrinsics)

    - [‘`llvm.loop.dependence.war.mask.*`’ Intrinsics](intrinsics-vector.md#llvm-loop-dependence-war-mask-intrinsics)

    - [‘`llvm.loop.dependence.raw.mask.*`’ Intrinsics](intrinsics-vector.md#llvm-loop-dependence-raw-mask-intrinsics)

  - [Experimental Vector Intrinsics](intrinsics-vector.md#experimental-vector-intrinsics)

    - [‘`llvm.experimental.cttz.elts`’ Intrinsic](intrinsics-vector.md#llvm-experimental-cttz-elts-intrinsic)

    - [‘`llvm.experimental.get.vector.length`’ Intrinsic](intrinsics-vector.md#llvm-experimental-get-vector-length-intrinsic)

    - [‘`llvm.experimental.vector.histogram.*`’ Intrinsic](intrinsics-vector.md#llvm-experimental-vector-histogram-intrinsic)

    - [‘`llvm.experimental.vector.extract.last.active`’ Intrinsic](intrinsics-vector.md#llvm-experimental-vector-extract-last-active-intrinsic)

    - [‘`llvm.experimental.vector.compress.*`’ Intrinsics](intrinsics-vector.md#llvm-experimental-vector-compress-intrinsics)

    - [‘`llvm.experimental.vector.match.*`’ Intrinsic](intrinsics-vector.md#llvm-experimental-vector-match-intrinsic)

  - [Matrix Intrinsics](intrinsics-vector.md#matrix-intrinsics)

    - [‘`llvm.matrix.transpose.*`’ Intrinsic](intrinsics-vector.md#llvm-matrix-transpose-intrinsic)

    - [‘`llvm.matrix.multiply.*`’ Intrinsic](intrinsics-vector.md#llvm-matrix-multiply-intrinsic)

    - [‘`llvm.matrix.column.major.load.*`’ Intrinsic](intrinsics-vector.md#llvm-matrix-column-major-load-intrinsic)

    - [‘`llvm.matrix.column.major.store.*`’ Intrinsic](intrinsics-vector.md#llvm-matrix-column-major-store-intrinsic)

  - [Saturating floating-point to integer conversions](intrinsics-floating-point.md#saturating-floating-point-to-integer-conversions)

    - [‘`llvm.fptoui.sat.*`’ Intrinsic](intrinsics-floating-point.md#llvm-fptoui-sat-intrinsic)

    - [‘`llvm.fptosi.sat.*`’ Intrinsic](intrinsics-floating-point.md#llvm-fptosi-sat-intrinsic)

  - [Floating-Point Conversion Intrinsics](intrinsics-floating-point.md#floating-point-conversion-intrinsics)

    - [‘`llvm.fptrunc.round`’ Intrinsic](intrinsics-floating-point.md#llvm-fptrunc-round-intrinsic)

    - [‘`llvm.convert.to.arbitrary.fp`’ Intrinsic](intrinsics-floating-point.md#llvm-convert-to-arbitrary-fp-intrinsic)

    - [‘`llvm.convert.from.arbitrary.fp`’ Intrinsic](intrinsics-floating-point.md#llvm-convert-from-arbitrary-fp-intrinsic)

  - [Convergence Intrinsics](intrinsics-general.md#convergence-intrinsics)

  - [Debugger Intrinsics](intrinsics-general.md#debugger-intrinsics)

  - [Exception Handling Intrinsics](intrinsics-general.md#exception-handling-intrinsics)

  - [Pointer Authentication Intrinsics](intrinsics-general.md#pointer-authentication-intrinsics)

  - [Trampoline Intrinsics](intrinsics-general.md#trampoline-intrinsics)

    - [‘`llvm.init.trampoline`’ Intrinsic](intrinsics-general.md#llvm-init-trampoline-intrinsic)

    - [‘`llvm.adjust.trampoline`’ Intrinsic](intrinsics-general.md#llvm-adjust-trampoline-intrinsic)

  - [Vector Predication Intrinsics](intrinsics-vector.md#vector-predication-intrinsics)

    - [Optimization Hint](intrinsics-vector.md#optimization-hint)

    - [‘`llvm.vp.select.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-select-intrinsics)

    - [‘`llvm.vp.merge.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-merge-intrinsics)

    - [‘`llvm.vp.add.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-add-intrinsics)

    - [‘`llvm.vp.sub.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-sub-intrinsics)

    - [‘`llvm.vp.mul.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-mul-intrinsics)

    - [‘`llvm.vp.sdiv.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-sdiv-intrinsics)

    - [‘`llvm.vp.udiv.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-udiv-intrinsics)

    - [‘`llvm.vp.srem.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-srem-intrinsics)

    - [‘`llvm.vp.urem.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-urem-intrinsics)

    - [‘`llvm.vp.ashr.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-ashr-intrinsics)

    - [‘`llvm.vp.lshr.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-lshr-intrinsics)

    - [‘`llvm.vp.shl.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-shl-intrinsics)

    - [‘`llvm.vp.or.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-or-intrinsics)

    - [‘`llvm.vp.and.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-and-intrinsics)

    - [‘`llvm.vp.xor.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-xor-intrinsics)

    - [‘`llvm.vp.abs.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-abs-intrinsics)

    - [‘`llvm.vp.smax.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-smax-intrinsics)

    - [‘`llvm.vp.smin.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-smin-intrinsics)

    - [‘`llvm.vp.umax.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-umax-intrinsics)

    - [‘`llvm.vp.umin.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-umin-intrinsics)

    - [‘`llvm.vp.copysign.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-copysign-intrinsics)

    - [‘`llvm.vp.minnum.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-minnum-intrinsics)

    - [‘`llvm.vp.maxnum.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-maxnum-intrinsics)

    - [‘`llvm.vp.minimum.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-minimum-intrinsics)

    - [‘`llvm.vp.maximum.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-maximum-intrinsics)

    - [‘`llvm.vp.fadd.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-fadd-intrinsics)

    - [‘`llvm.vp.fsub.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-fsub-intrinsics)

    - [‘`llvm.vp.fmul.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-fmul-intrinsics)

    - [‘`llvm.vp.fdiv.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-fdiv-intrinsics)

    - [‘`llvm.vp.frem.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-frem-intrinsics)

    - [‘`llvm.vp.fneg.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-fneg-intrinsics)

    - [‘`llvm.vp.fabs.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-fabs-intrinsics)

    - [‘`llvm.vp.sqrt.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-sqrt-intrinsics)

    - [‘`llvm.vp.fma.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-fma-intrinsics)

    - [‘`llvm.vp.fmuladd.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-fmuladd-intrinsics)

    - [‘`llvm.vp.reduce.add.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-reduce-add-intrinsics)

    - [‘`llvm.vp.reduce.fadd.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-reduce-fadd-intrinsics)

    - [‘`llvm.vp.reduce.mul.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-reduce-mul-intrinsics)

    - [‘`llvm.vp.reduce.fmul.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-reduce-fmul-intrinsics)

    - [‘`llvm.vp.reduce.and.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-reduce-and-intrinsics)

    - [‘`llvm.vp.reduce.or.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-reduce-or-intrinsics)

    - [‘`llvm.vp.reduce.xor.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-reduce-xor-intrinsics)

    - [‘`llvm.vp.reduce.smax.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-reduce-smax-intrinsics)

    - [‘`llvm.vp.reduce.smin.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-reduce-smin-intrinsics)

    - [‘`llvm.vp.reduce.umax.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-reduce-umax-intrinsics)

    - [‘`llvm.vp.reduce.umin.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-reduce-umin-intrinsics)

    - [‘`llvm.vp.reduce.fmax.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-reduce-fmax-intrinsics)

    - [‘`llvm.vp.reduce.fmin.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-reduce-fmin-intrinsics)

    - [‘`llvm.vp.reduce.fmaximum.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-reduce-fmaximum-intrinsics)

    - [‘`llvm.vp.reduce.fminimum.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-reduce-fminimum-intrinsics)

    - [‘`llvm.experimental.vp.splice`’ Intrinsic](intrinsics-vector.md#llvm-experimental-vp-splice-intrinsic)

    - [‘`llvm.experimental.vp.reverse`’ Intrinsic](intrinsics-vector.md#llvm-experimental-vp-reverse-intrinsic)

    - [‘`llvm.vp.load`’ Intrinsic](intrinsics-vector.md#llvm-vp-load-intrinsic)

    - [‘`llvm.vp.load.ff`’ Intrinsic](intrinsics-vector.md#llvm-vp-load-ff-intrinsic)

    - [‘`llvm.vp.store`’ Intrinsic](intrinsics-vector.md#llvm-vp-store-intrinsic)

    - [‘`llvm.experimental.vp.strided.load`’ Intrinsic](intrinsics-vector.md#llvm-experimental-vp-strided-load-intrinsic)

    - [‘`llvm.experimental.vp.strided.store`’ Intrinsic](intrinsics-vector.md#llvm-experimental-vp-strided-store-intrinsic)

    - [‘`llvm.vp.gather`’ Intrinsic](intrinsics-vector.md#llvm-vp-gather-intrinsic)

    - [‘`llvm.vp.scatter`’ Intrinsic](intrinsics-vector.md#llvm-vp-scatter-intrinsic)

    - [‘`llvm.vp.trunc.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-trunc-intrinsics)

    - [‘`llvm.vp.zext.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-zext-intrinsics)

    - [‘`llvm.vp.sext.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-sext-intrinsics)

    - [‘`llvm.vp.fptrunc.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-fptrunc-intrinsics)

    - [‘`llvm.vp.fpext.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-fpext-intrinsics)

    - [‘`llvm.vp.fptoui.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-fptoui-intrinsics)

    - [‘`llvm.vp.fptosi.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-fptosi-intrinsics)

    - [‘`llvm.vp.uitofp.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-uitofp-intrinsics)

    - [‘`llvm.vp.sitofp.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-sitofp-intrinsics)

    - [‘`llvm.vp.ptrtoint.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-ptrtoint-intrinsics)

    - [‘`llvm.vp.inttoptr.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-inttoptr-intrinsics)

    - [‘`llvm.vp.fcmp.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-fcmp-intrinsics)

    - [‘`llvm.vp.icmp.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-icmp-intrinsics)

    - [‘`llvm.vp.ceil.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-ceil-intrinsics)

    - [‘`llvm.vp.floor.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-floor-intrinsics)

    - [‘`llvm.vp.rint.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-rint-intrinsics)

    - [‘`llvm.vp.nearbyint.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-nearbyint-intrinsics)

    - [‘`llvm.vp.round.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-round-intrinsics)

    - [‘`llvm.vp.roundeven.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-roundeven-intrinsics)

    - [‘`llvm.vp.roundtozero.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-roundtozero-intrinsics)

    - [‘`llvm.vp.lrint.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-lrint-intrinsics)

    - [‘`llvm.vp.llrint.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-llrint-intrinsics)

    - [‘`llvm.vp.bitreverse.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-bitreverse-intrinsics)

    - [‘`llvm.vp.bswap.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-bswap-intrinsics)

    - [‘`llvm.vp.ctpop.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-ctpop-intrinsics)

    - [‘`llvm.vp.ctlz.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-ctlz-intrinsics)

    - [‘`llvm.vp.cttz.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-cttz-intrinsics)

    - [‘`llvm.vp.cttz.elts.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-cttz-elts-intrinsics)

    - [‘`llvm.vp.sadd.sat.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-sadd-sat-intrinsics)

    - [‘`llvm.vp.uadd.sat.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-uadd-sat-intrinsics)

    - [‘`llvm.vp.ssub.sat.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-ssub-sat-intrinsics)

    - [‘`llvm.vp.usub.sat.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-usub-sat-intrinsics)

    - [‘`llvm.vp.fshl.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-fshl-intrinsics)

    - [‘`llvm.vp.fshr.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-fshr-intrinsics)

    - [‘`llvm.vp.is.fpclass.*`’ Intrinsics](intrinsics-vector.md#llvm-vp-is-fpclass-intrinsics)

  - [Masked Vector Load and Store Intrinsics](intrinsics-vector.md#masked-vector-load-and-store-intrinsics)

    - [‘`llvm.masked.load.*`’ Intrinsics](intrinsics-vector.md#llvm-masked-load-intrinsics)

    - [‘`llvm.masked.store.*`’ Intrinsics](intrinsics-vector.md#llvm-masked-store-intrinsics)

  - [Masked Vector Gather and Scatter Intrinsics](intrinsics-vector.md#masked-vector-gather-and-scatter-intrinsics)

    - [‘`llvm.masked.gather.*`’ Intrinsics](intrinsics-vector.md#llvm-masked-gather-intrinsics)

    - [‘`llvm.masked.scatter.*`’ Intrinsics](intrinsics-vector.md#llvm-masked-scatter-intrinsics)

  - [Masked Vector Expanding Load and Compressing Store Intrinsics](intrinsics-vector.md#masked-vector-expanding-load-and-compressing-store-intrinsics)

    - [‘`llvm.masked.expandload.*`’ Intrinsics](intrinsics-vector.md#llvm-masked-expandload-intrinsics)

    - [‘`llvm.masked.compressstore.*`’ Intrinsics](intrinsics-vector.md#llvm-masked-compressstore-intrinsics)

  - [Masked Vector Arithmetic Intrinsics](intrinsics-vector.md#masked-vector-arithmetic-intrinsics)

    - [‘`llvm.masked.udiv.*`’ Intrinsics](intrinsics-vector.md#llvm-masked-udiv-intrinsics)

    - [‘`llvm.masked.sdiv.*`’ Intrinsics](intrinsics-vector.md#llvm-masked-sdiv-intrinsics)

    - [‘`llvm.masked.urem.*`’ Intrinsics](intrinsics-vector.md#llvm-masked-urem-intrinsics)

    - [‘`llvm.masked.srem.*`’ Intrinsics](intrinsics-vector.md#llvm-masked-srem-intrinsics)

  - [Memory Use Markers](intrinsics-general.md#memory-use-markers)

    - [‘`llvm.lifetime.start`’ Intrinsic](intrinsics-general.md#llvm-lifetime-start-intrinsic)

    - [‘`llvm.lifetime.end`’ Intrinsic](intrinsics-general.md#llvm-lifetime-end-intrinsic)

    - [‘`llvm.invariant.start`’ Intrinsic](intrinsics-general.md#llvm-invariant-start-intrinsic)

    - [‘`llvm.invariant.end`’ Intrinsic](intrinsics-general.md#llvm-invariant-end-intrinsic)

    - [‘`llvm.launder.invariant.group`’ Intrinsic](intrinsics-general.md#llvm-launder-invariant-group-intrinsic)

    - [‘`llvm.strip.invariant.group`’ Intrinsic](intrinsics-general.md#llvm-strip-invariant-group-intrinsic)

  - [Constrained Floating-Point Intrinsics](intrinsics-floating-point.md#constrained-floating-point-intrinsics)

    - [‘`llvm.experimental.constrained.fadd`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-fadd-intrinsic)

    - [‘`llvm.experimental.constrained.fsub`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-fsub-intrinsic)

    - [‘`llvm.experimental.constrained.fmul`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-fmul-intrinsic)

    - [‘`llvm.experimental.constrained.fdiv`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-fdiv-intrinsic)

    - [‘`llvm.experimental.constrained.frem`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-frem-intrinsic)

    - [‘`llvm.experimental.constrained.fma`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-fma-intrinsic)

    - [‘`llvm.experimental.constrained.fptoui`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-fptoui-intrinsic)

    - [‘`llvm.experimental.constrained.fptosi`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-fptosi-intrinsic)

    - [‘`llvm.experimental.constrained.uitofp`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-uitofp-intrinsic)

    - [‘`llvm.experimental.constrained.sitofp`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-sitofp-intrinsic)

    - [‘`llvm.experimental.constrained.fptrunc`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-fptrunc-intrinsic)

    - [‘`llvm.experimental.constrained.fpext`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-fpext-intrinsic)

    - [‘`llvm.experimental.constrained.fcmp`’ and ‘`llvm.experimental.constrained.fcmps`’ Intrinsics](intrinsics-floating-point.md#llvm-experimental-constrained-fcmp-and-llvm-experimental-constrained-fcmps-intrinsics)

    - [‘`llvm.experimental.constrained.fmuladd`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-fmuladd-intrinsic)

  - [Constrained libm-equivalent Intrinsics](intrinsics-floating-point.md#constrained-libm-equivalent-intrinsics)

    - [‘`llvm.experimental.constrained.sqrt`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-sqrt-intrinsic)

    - [‘`llvm.experimental.constrained.pow`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-pow-intrinsic)

    - [‘`llvm.experimental.constrained.powi`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-powi-intrinsic)

    - [‘`llvm.experimental.constrained.ldexp`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-ldexp-intrinsic)

    - [‘`llvm.experimental.constrained.sin`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-sin-intrinsic)

    - [‘`llvm.experimental.constrained.cos`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-cos-intrinsic)

    - [‘`llvm.experimental.constrained.tan`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-tan-intrinsic)

    - [‘`llvm.experimental.constrained.asin`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-asin-intrinsic)

    - [‘`llvm.experimental.constrained.acos`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-acos-intrinsic)

    - [‘`llvm.experimental.constrained.atan`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-atan-intrinsic)

    - [‘`llvm.experimental.constrained.atan2`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-atan2-intrinsic)

    - [‘`llvm.experimental.constrained.sinh`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-sinh-intrinsic)

    - [‘`llvm.experimental.constrained.cosh`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-cosh-intrinsic)

    - [‘`llvm.experimental.constrained.tanh`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-tanh-intrinsic)

    - [‘`llvm.experimental.constrained.exp`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-exp-intrinsic)

    - [‘`llvm.experimental.constrained.exp2`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-exp2-intrinsic)

    - [‘`llvm.experimental.constrained.log`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-log-intrinsic)

    - [‘`llvm.experimental.constrained.log10`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-log10-intrinsic)

    - [‘`llvm.experimental.constrained.log2`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-log2-intrinsic)

    - [‘`llvm.experimental.constrained.rint`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-rint-intrinsic)

    - [‘`llvm.experimental.constrained.lrint`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-lrint-intrinsic)

    - [‘`llvm.experimental.constrained.llrint`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-llrint-intrinsic)

    - [‘`llvm.experimental.constrained.nearbyint`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-nearbyint-intrinsic)

    - [‘`llvm.experimental.constrained.maxnum`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-maxnum-intrinsic)

    - [‘`llvm.experimental.constrained.minnum`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-minnum-intrinsic)

    - [‘`llvm.experimental.constrained.maximum`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-maximum-intrinsic)

    - [‘`llvm.experimental.constrained.minimum`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-minimum-intrinsic)

    - [‘`llvm.experimental.constrained.ceil`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-ceil-intrinsic)

    - [‘`llvm.experimental.constrained.floor`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-floor-intrinsic)

    - [‘`llvm.experimental.constrained.round`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-round-intrinsic)

    - [‘`llvm.experimental.constrained.roundeven`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-roundeven-intrinsic)

    - [‘`llvm.experimental.constrained.lround`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-lround-intrinsic)

    - [‘`llvm.experimental.constrained.llround`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-llround-intrinsic)

    - [‘`llvm.experimental.constrained.trunc`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-constrained-trunc-intrinsic)

    - [‘`llvm.experimental.noalias.scope.decl`’ Intrinsic](intrinsics-floating-point.md#llvm-experimental-noalias-scope-decl-intrinsic)

  - [Floating Point Environment Manipulation intrinsics](intrinsics-floating-point.md#floating-point-environment-manipulation-intrinsics)

    - [‘`llvm.get.rounding`’ Intrinsic](intrinsics-floating-point.md#llvm-get-rounding-intrinsic)

    - [‘`llvm.set.rounding`’ Intrinsic](intrinsics-floating-point.md#llvm-set-rounding-intrinsic)

    - [‘`llvm.get.fpenv`’ Intrinsic](intrinsics-floating-point.md#llvm-get-fpenv-intrinsic)

    - [‘`llvm.set.fpenv`’ Intrinsic](intrinsics-floating-point.md#llvm-set-fpenv-intrinsic)

    - [‘`llvm.reset.fpenv`’ Intrinsic](intrinsics-floating-point.md#llvm-reset-fpenv-intrinsic)

    - [‘`llvm.get.fpmode`’ Intrinsic](intrinsics-floating-point.md#llvm-get-fpmode-intrinsic)

    - [‘`llvm.set.fpmode`’ Intrinsic](intrinsics-floating-point.md#llvm-set-fpmode-intrinsic)

    - [‘`llvm.reset.fpmode`’ Intrinsic](intrinsics-floating-point.md#llvm-reset-fpmode-intrinsic)

  - [Floating-Point Test Intrinsics](intrinsics-floating-point.md#floating-point-test-intrinsics)

    - [‘`llvm.is.fpclass`’ Intrinsic](intrinsics-floating-point.md#llvm-is-fpclass-intrinsic)

  - [General Intrinsics](intrinsics-general.md#general-intrinsics)

    - [‘`llvm.var.annotation`’ Intrinsic](intrinsics-general.md#llvm-var-annotation-intrinsic)

    - [‘`llvm.ptr.annotation.*`’ Intrinsic](intrinsics-general.md#llvm-ptr-annotation-intrinsic)

    - [‘`llvm.annotation.*`’ Intrinsic](intrinsics-general.md#llvm-annotation-intrinsic)

    - [‘`llvm.codeview.annotation`’ Intrinsic](intrinsics-general.md#llvm-codeview-annotation-intrinsic)

    - [‘`llvm.trap`’ Intrinsic](intrinsics-general.md#llvm-trap-intrinsic)

    - [‘`llvm.debugtrap`’ Intrinsic](intrinsics-general.md#llvm-debugtrap-intrinsic)

    - [‘`llvm.ubsantrap`’ Intrinsic](intrinsics-general.md#llvm-ubsantrap-intrinsic)

    - [‘`llvm.stackprotector`’ Intrinsic](intrinsics-general.md#llvm-stackprotector-intrinsic)

    - [‘`llvm.stackguard`’ Intrinsic](intrinsics-general.md#llvm-stackguard-intrinsic)

    - [‘`llvm.objectsize`’ Intrinsic](intrinsics-general.md#llvm-objectsize-intrinsic)

    - [‘`llvm.expect`’ Intrinsic](intrinsics-general.md#llvm-expect-intrinsic)

    - [‘`llvm.expect.with.probability`’ Intrinsic](intrinsics-general.md#llvm-expect-with-probability-intrinsic)

    - [‘`llvm.assume`’ Intrinsic](intrinsics-general.md#llvm-assume-intrinsic)

    - [‘`llvm.ssa.copy`’ Intrinsic](intrinsics-general.md#llvm-ssa-copy-intrinsic)

    - [‘`llvm.type.test`’ Intrinsic](intrinsics-general.md#llvm-type-test-intrinsic)

    - [‘`llvm.type.checked.load`’ Intrinsic](intrinsics-general.md#llvm-type-checked-load-intrinsic)

    - [‘`llvm.type.checked.load.relative`’ Intrinsic](intrinsics-general.md#llvm-type-checked-load-relative-intrinsic)

    - [‘`llvm.arithmetic.fence`’ Intrinsic](intrinsics-general.md#llvm-arithmetic-fence-intrinsic)

    - [‘`llvm.donothing`’ Intrinsic](intrinsics-general.md#llvm-donothing-intrinsic)

    - [‘`llvm.experimental.deoptimize`’ Intrinsic](intrinsics-general.md#llvm-experimental-deoptimize-intrinsic)

    - [‘`llvm.experimental.guard`’ Intrinsic](intrinsics-general.md#llvm-experimental-guard-intrinsic)

    - [‘`llvm.experimental.widenable.condition`’ Intrinsic](intrinsics-general.md#llvm-experimental-widenable-condition-intrinsic)

    - [‘`llvm.allow.ubsan.check`’ Intrinsic](intrinsics-general.md#llvm-allow-ubsan-check-intrinsic)

    - [‘`llvm.allow.runtime.check`’ Intrinsic](intrinsics-general.md#llvm-allow-runtime-check-intrinsic)

    - [‘`llvm.load.relative`’ Intrinsic](intrinsics-general.md#llvm-load-relative-intrinsic)

    - [‘`llvm.sideeffect`’ Intrinsic](intrinsics-general.md#llvm-sideeffect-intrinsic)

    - [‘`llvm.is.constant.*`’ Intrinsic](intrinsics-general.md#llvm-is-constant-intrinsic)

    - [‘`llvm.ptrmask`’ Intrinsic](intrinsics-general.md#llvm-ptrmask-intrinsic)

    - [‘`llvm.threadlocal.address`’ Intrinsic](intrinsics-general.md#llvm-threadlocal-address-intrinsic)

    - [‘`llvm.vscale`’ Intrinsic](intrinsics-general.md#llvm-vscale-intrinsic)

    - [‘`llvm.fake.use`’ Intrinsic](intrinsics-general.md#llvm-fake-use-intrinsic)

    - [‘`llvm.reloc.none`’ Intrinsic](intrinsics-general.md#llvm-reloc-none-intrinsic)

  - [Stack Map Intrinsics](intrinsics-general.md#stack-map-intrinsics)

  - [Element Wise Atomic Memory Intrinsics](intrinsics-general.md#element-wise-atomic-memory-intrinsics)

    - [‘`llvm.memcpy.element.unordered.atomic`’ Intrinsic](intrinsics-general.md#llvm-memcpy-element-unordered-atomic-intrinsic)

    - [‘`llvm.memmove.element.unordered.atomic`’ Intrinsic](intrinsics-general.md#llvm-memmove-element-unordered-atomic-intrinsic)

    - [‘`llvm.memset.element.unordered.atomic`’ Intrinsic](intrinsics-general.md#llvm-memset-element-unordered-atomic-intrinsic)

  - [Objective-C ARC Runtime Intrinsics](intrinsics-general.md#objective-c-arc-runtime-intrinsics)

    - [‘`llvm.objc.autorelease`’ Intrinsic](intrinsics-general.md#llvm-objc-autorelease-intrinsic)

    - [‘`llvm.objc.autoreleasePoolPop`’ Intrinsic](intrinsics-general.md#llvm-objc-autoreleasepoolpop-intrinsic)

    - [‘`llvm.objc.autoreleasePoolPush`’ Intrinsic](intrinsics-general.md#llvm-objc-autoreleasepoolpush-intrinsic)

    - [‘`llvm.objc.autoreleaseReturnValue`’ Intrinsic](intrinsics-general.md#llvm-objc-autoreleasereturnvalue-intrinsic)

    - [‘`llvm.objc.copyWeak`’ Intrinsic](intrinsics-general.md#llvm-objc-copyweak-intrinsic)

    - [‘`llvm.objc.destroyWeak`’ Intrinsic](intrinsics-general.md#llvm-objc-destroyweak-intrinsic)

    - [‘`llvm.objc.initWeak`’ Intrinsic](intrinsics-general.md#llvm-objc-initweak-intrinsic)

    - [‘`llvm.objc.loadWeak`’ Intrinsic](intrinsics-general.md#llvm-objc-loadweak-intrinsic)

    - [‘`llvm.objc.loadWeakRetained`’ Intrinsic](intrinsics-general.md#llvm-objc-loadweakretained-intrinsic)

    - [‘`llvm.objc.moveWeak`’ Intrinsic](intrinsics-general.md#llvm-objc-moveweak-intrinsic)

    - [‘`llvm.objc.release`’ Intrinsic](intrinsics-general.md#llvm-objc-release-intrinsic)

    - [‘`llvm.objc.retain`’ Intrinsic](intrinsics-general.md#llvm-objc-retain-intrinsic)

    - [‘`llvm.objc.retainAutorelease`’ Intrinsic](intrinsics-general.md#llvm-objc-retainautorelease-intrinsic)

    - [‘`llvm.objc.retainAutoreleaseReturnValue`’ Intrinsic](intrinsics-general.md#llvm-objc-retainautoreleasereturnvalue-intrinsic)

    - [‘`llvm.objc.retainAutoreleasedReturnValue`’ Intrinsic](intrinsics-general.md#llvm-objc-retainautoreleasedreturnvalue-intrinsic)

    - [‘`llvm.objc.retainBlock`’ Intrinsic](intrinsics-general.md#llvm-objc-retainblock-intrinsic)

    - [‘`llvm.objc.storeStrong`’ Intrinsic](intrinsics-general.md#llvm-objc-storestrong-intrinsic)

    - [‘`llvm.objc.storeWeak`’ Intrinsic](intrinsics-general.md#llvm-objc-storeweak-intrinsic)

  - [Preserving Debug Information Intrinsics](intrinsics-general.md#preserving-debug-information-intrinsics)

    - [‘`llvm.preserve.array.access.index`’ Intrinsic](intrinsics-general.md#llvm-preserve-array-access-index-intrinsic)

    - [‘`llvm.preserve.union.access.index`’ Intrinsic](intrinsics-general.md#llvm-preserve-union-access-index-intrinsic)

    - [‘`llvm.preserve.struct.access.index`’ Intrinsic](intrinsics-general.md#llvm-preserve-struct-access-index-intrinsic)

    - [‘`llvm.protected.field.ptr`’ Intrinsic](intrinsics-general.md#llvm-protected-field-ptr-intrinsic)

    - [‘`llvm.cond.loop`’ Intrinsic](intrinsics-general.md#llvm-cond-loop-intrinsic)

    - [‘`llvm.looptrap`’ Intrinsic](intrinsics-general.md#llvm-looptrap-intrinsic)

<a id="abstract"></a>

## Abstract

This document is a reference manual for the LLVM assembly language. LLVM is a Static Single Assignment (SSA) based representation that provides type safety, low-level operations, flexibility, and the capability of representing ‘all’ high-level languages cleanly. It is the common code representation used throughout all phases of the LLVM compilation strategy.

<a id="introduction"></a>

## Introduction

The LLVM code representation is designed to be used in three different forms: as an in-memory compiler IR, as an on-disk bitcode representation (suitable for fast loading by a Just-In-Time compiler), and as a human readable assembly language representation. This allows LLVM to provide a powerful intermediate representation for efficient compiler transformations and analysis, while providing a natural means to debug and visualize the transformations. The three different forms of LLVM are all equivalent. This document describes the human-readable representation and notation.

The LLVM representation aims to be light-weight and low-level while being expressive, typed, and extensible at the same time. It aims to be a “universal IR” of sorts, by being at a low enough level that high-level ideas may be cleanly mapped to it (similar to how microprocessors are “universal IR’s”, allowing many source languages to be mapped to them). By providing type information, LLVM can be used as the target of optimizations: for example, through pointer analysis, it can be proven that a C automatic variable is never accessed outside of the current function, allowing it to be promoted to a simple SSA value instead of a memory location.

<a id="well-formedness"></a>

<a id="wellformed"></a>

### Well-Formedness

It is important to note that this document describes ‘well formed’ LLVM assembly language. There is a difference between what the parser accepts and what is considered ‘well formed’. For example, the following instruction is syntactically okay, but not well formed:

    %x = add i32 1, %x

because the definition of `%x` does not dominate all of its uses. The LLVM infrastructure provides a verification pass that may be used to verify that an LLVM module is well formed. This pass is automatically run by the parser after parsing input assembly and by the optimizer before it outputs bitcode. The violations pointed out by the verifier pass indicate bugs in transformation passes or input to the parser.

<a id="syntax"></a>

## Syntax

<a id="identifiers"></a>

<a id="id1"></a>

### Identifiers

LLVM identifiers come in two basic types: global and local. Global identifiers (functions, global variables) begin with the `'@'` character. Local identifiers (register names, types) begin with the `'%'` character. Additionally, there are three different formats for identifiers, for different purposes:

1.  Named values are represented as a string of characters with their prefix. For example, `%foo`, `@DivisionByZero`, `%a.really.long.identifier`. The actual regular expression used is ‘`[%@][-a-zA-Z$._][-a-zA-Z$._0-9]*`’. Identifiers that require other characters in their names can be surrounded with quotes. Special characters may be escaped using `"\xx"` where `xx` is the ASCII code for the character in hexadecimal. In this way, any character can be used in a name value, even quotes themselves. The `"\01"` prefix can be used on global values to suppress mangling.

2.  Unnamed values are represented as an unsigned numeric value with their prefix. For example, `%12`, `@2`, `%44`.

3.  Constants, which are described in the section [Constants](constants.md#constants) below.

LLVM requires that values start with a prefix for two reasons: Compilers don’t need to worry about name clashes with reserved words, and the set of reserved words may be expanded in the future without penalty. Additionally, unnamed identifiers allow a compiler to quickly come up with a temporary variable without having to avoid symbol table conflicts.

Reserved words in LLVM are very similar to reserved words in other languages. There are keywords for different opcodes (’`add`’, ‘`bitcast`’, ‘`ret`’, etc…), for primitive type names (’`void`’, ‘`i32`’, etc…), and others. These reserved words cannot conflict with variable names, because none of them start with a prefix character (`'%'` or `'@'`).

Here is an example of LLVM code to multiply the integer variable ‘`%X`’ by 8:

The easy way:

    %result = mul i32 %X, 8

After strength reduction:

    %result = shl i32 %X, 3

And the hard way:

    %0 = add i32 %X, %X           ; yields i32:%0
    %1 = add i32 %0, %0           ; yields i32:%1
    %result = add i32 %1, %1

This last way of multiplying `%X` by 8 illustrates several important lexical features of LLVM:

1.  Comments are delimited with a ‘`;`’ and go until the end of line. Alternatively, comments can start with `/*` and terminate with `*/`.

2.  Unnamed temporaries are created when the result of a computation is not assigned to a named value.

3.  By default, unnamed temporaries are numbered sequentially (using a per-function incrementing counter, starting with 0). However, when explicitly specifying temporary numbers, it is allowed to skip over numbers.

    Note that basic blocks and unnamed function parameters are included in this numbering. For example, if the entry basic block is not given a label name and all function parameters are named, then it will get number 0.

It also shows a convention that we follow in this document. When demonstrating instructions, we will follow an instruction with a comment that defines the type and name of value produced.

<a id="string-constants"></a>

<a id="id2"></a>

### String constants

Strings in LLVM programs are delimited by `"` characters. Within a string, all bytes are treated literally with the exception of `\` characters, which start escapes, and the first `"` character, which ends the string.

There are two kinds of escapes.

- `\\` represents a single `\` character.

- `\` followed by two hexadecimal characters (0-9, a-f, or A-F) represents the byte with the given value (e.g., `\00` represents a null byte).

To represent a `"` character, use `\22`. (`\"` will end the string with a trailing `\`.)

Newlines do not terminate string constants; strings can span multiple lines.

The interpretation of string constants (e.g., their character encoding) depends on context.
