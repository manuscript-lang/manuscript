from "@std/collections.ms" import ListBuilder
from "./contracts.ms" import Read

export interface Original:
    def original() -> Int

export type Item:
    value: Int

impl Original for Item:
    def original() -> Int:
        return self.value

export type Box[T]:
    value: T

export type Holder[T: Read[Int]]:
    value: T

impl Read[Int] for Holder[T]:
    def get() -> Int:
        return self.value.get()

export type Choice:
    case Some(value: Int)
    case Empty

export type Resource:
    events: ListBuilder[Int]
