+++
title = "Aggregates and local construction"
weight = 51
+++

# Aggregates and local construction

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Records, alternatives, collections, and closures can hold resource references. Storing a resource inside one of these values does not arrange for it to close or keep it open. Arrange cleanup for the resource itself.

Closing a registered resource affects all aliases, including aliases nested in aggregates. Dropping an aggregate does not recursively close its fields. A library object that deliberately manages several resources can implement `Closeable` and explicitly close them in its implementation.

Collections may retain any value, including resource references and functions. Sharing is universal and does not provide a resource lifetime guarantee.

[Builders](../../standard-library/data-and-io/builders.md) follow the same reference rules; mutation and freeze are synchronized. [Destructuring](../../core-language/basics/destructuring.md) extracts fields and positions without changing cleanup.
