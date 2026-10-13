+++
title = "Reading a concurrent-flow diagram"
weight = 114
+++

# Reading a concurrent-flow diagram

Read this diagram from the preparation step downward. The two branches run concurrently, then meet at a join. It shows how [task groups](../../concurrency/task-groups.md) handles ordinary results, faults, timeouts, and caller cancellation.

```mermaid
flowchart TD
    R[Prepare first and second functions] --> A[Construct TaskGroup with a 2 second timeout]
    A --> I[Start first operation]
    A --> S[Start second operation]
    I --> W[Observe completion outcomes]
    S --> W
    W -->|Both complete normally| J[Join operations and cleanup]
    J --> V[Read each typed task result]
    W -->|Operation fault or API timeout| C[Cancel unfinished operations]
    P[Caller cancellation or deadline] -.-> C
    C --> K[Join all operations and cleanup]
    K -->|Execution failure| E[Return ExecutionError]
    K -->|Caller stopped| U[Unwind caller]
```

The API prepares all arguments before starting work. Successful positions follow input order regardless of completion order. A domain error is an ordinary returned value; it does not cancel siblings.

Every exit joins all operations, even if joining exceeds the initiating timeout. Caller cancellation unwinds the caller after joining. Resource cleanup follows explicit `with` registrations; no result or capture is recursively closed merely because it is unreturned.

Scheduler submission has a different lifetime edge: an accepted operation runs under its service's fixed parent, survives a submitting request, and is joined during service shutdown. See [Scheduler](../../concurrency/scheduling.md), [cancellation propagation](../../concurrency/cancellation.md#propagation-and-checkpoints), and [cleanup ordering](../../core-language/cleanup/exit-order.md).
