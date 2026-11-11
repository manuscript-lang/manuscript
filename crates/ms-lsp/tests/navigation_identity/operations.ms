export type Sample:
    number: Int

fn Sample.amount() Int:
    return self.number

fn Sample.label() String:
    return "sample"

export interface Named:
    fn label() String

export enum Shape:
    Number(value: Int)
    Empty

export fn calls() String:
    sample := Sample(number: 1)
    shape := Shape.Number(sample.amount())
    _shape := shape
    return sample.label()
