import Shared from "@std/shared.ms"
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
