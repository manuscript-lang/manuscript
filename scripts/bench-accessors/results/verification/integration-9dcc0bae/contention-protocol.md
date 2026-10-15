# Bounded accessor contention measurement protocol

Compare historical method baseline 1383851e with the integrated accessor runtime;
do not rewrite the historical 52-workload sample files. Use one common Go test
template compiled as a runtime-package test by an overlay in each immutable tree.
Only the adapter differs: normal Bind/Invoke of guard.get or logger.level versus
the statically resolved accessor helper. No compiler/runtime optimization is added.

Cases: GuardValue and LoggerLevel. Construct receivers and RootExecution outside
timing. Consume a scalar/tag without user Equal, JSON, transport, logging I/O or
construction. Guard adapters retain native holder validation and cell mutex;
Logger adapters retain threshold mutex and result representation. An identical
handwritten safety control in both trees performs admission cancellation,
receiver unwrapping, lock, holder validation where applicable, live read, unlock,
and delivery cancellation. It is a control, not a proposed replacement API.

Uncontended mode measures the complete read. Coordinated blocked-read mode starts
a reader while the peer holds the actual receiver mutex. Before timing, inspect
the reader's Go stack until it is demonstrably blocked in sync.Mutex.Lock, with
a bounded timeout. No sleep or assumed scheduler ordering establishes contention.
Then time release-to-reader-result delivery, including unlock, rescheduling and
the result channel. Setup, stack inspection and waiting before release are outside
timing. This is explicitly release latency, not throughput or pure getter cost.
Use fixed iteration counts to bound stack-inspection cost. Both public read and
safety control use the same coordination, context, result channel and validation.

Verify live writes made under the held mutex are delivered after release, stale
guards fault, and cancellation during the blocked read is observed after release.
Never forcibly release a guard or skip a validation/cancellation check to improve
the benchmark. Record contextual differences in the historical dispatch wrappers.

Run correctness and race probes first. Retain generated files, commands, hashes,
Go/environment metadata, all sample values and medians. Measure five samples
after broader verification is quiet, GOMAXPROCS=2, same SDK and host for both
revisions. No absolute speedup threshold or significance claim; report observed
control behavior and limitations, including unrepresentative forced contention.
