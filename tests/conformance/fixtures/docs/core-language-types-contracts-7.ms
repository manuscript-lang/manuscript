// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=documentation/core-language/types/contracts.md:127
fn use_increment(operation: Increment) Int:
    return operation.apply(1)

offset := Offset(2)
view := Increment(offset)
result := use_increment(view)
// Rejected: conversion is not implicit at a call boundary.
wrong := use_increment(offset)
