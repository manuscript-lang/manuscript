# conform: tags=alternatives,control-flow,faults,formatter,generics,interfaces,modules,parser,records,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/local_extensions/domain.ms
import Shared from "@std/concurrency/shared.ms"
import Read from "./contracts.ms"

export interface Original:
    fn original() Int

export type Item:
    value: Int

impl Original for Item:
    fn original() Int:
        return self.value

export type Box[T]:
    value: T

export type Holder[T: Read[Int]]:
    value: T

impl Read[Int] for Holder[T]:
    fn get() Int:
        return self.value.get()

export type Choice:
    case Some(value: Int)
    case Empty

export type Resource:
    events: Shared[List[Int]]
