# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/contracts.md:127
fn use_increment(operation: Increment) Int:
    return operation.apply(1)

let offset = Offset(2)
let view = Increment(offset)
let result = use_increment(view)
# Rejected: conversion is not implicit at a call boundary.
let wrong = use_increment(offset)
