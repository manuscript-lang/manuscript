+++
title = "Resource cleanup"
weight = 47
+++

# Resource cleanup

Use `with` to close a file or connection when its block ends. Keeping another reference does not keep the resource open.

- [Open and close a resource](cleanup/scopes.md)
- [Implement close](cleanup/closeable.md)
- [Cleanup order](cleanup/exit-order.md)
- [Cleanup errors](cleanup/cleanup-faults.md)
- [References](values/references.md) and [sharing data](values/sharing.md)
