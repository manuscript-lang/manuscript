+++
title = "Evaluation order and call preparation"
weight = 95
+++

# Evaluation order and call preparation

Named arguments can be written in a different order from the parameters in a declaration. Generated Go must still evaluate them in the order the caller wrote. Consume the checker's resolved argument names, including positional and mixed calls; retain their written order. Evaluate each argument into a temporary value, then arrange those values for the Go call. Preserve short-circuit behavior too.

Each TaskGroup.start prepares its callback before submitting that operation. Constructing closures snapshots their local captures without invoking their bodies. Earlier submissions may already be running while later callbacks are prepared; lexical group cleanup stops and joins them if later preparation fails. Native acquisitions retain their explicit delivery/cleanup contracts.

Ordinary list elements evaluate left to right; an existing list argument evaluates once. Destructuring evaluates the initializer once and extracts bindings in written pattern order, retaining each selected value's type.

A `with` initializer evaluates once, then registers the initialized object's resolved close method before exposing another cancellation checkpoint. Later alias assignment does not change that receiver.

See [source call order](../../../core-language/functions/declarations-and-calls.md), [operation preparation](../../../concurrency/task-groups.md#preparation), and [using with](../../../core-language/cleanup/scopes.md).
