package main

import "fmt"

type Op struct {
	kind int
	arg  int
}

const (
	Push = iota
	Load
	Store
	Add
	Mul
	Mod
	Lt
	Jz
	Jmp
	Halt
)

func program(n, m int) []Op {
	return []Op{
		{Push, 0}, {Store, 0},
		{Push, 0}, {Store, 1},
		{Load, 1}, {Push, n}, {Lt, 0}, {Jz, 33},
		{Push, 0}, {Store, 2},
		{Load, 2}, {Push, m}, {Lt, 0}, {Jz, 28},
		{Load, 0}, {Load, 1}, {Load, 2}, {Mul, 0}, {Push, 7}, {Mod, 0}, {Add, 0}, {Store, 0},
		{Load, 2}, {Push, 1}, {Add, 0}, {Store, 2},
		{Jmp, 10}, {Halt, 0},
		{Load, 1}, {Push, 1}, {Add, 0}, {Store, 1}, {Jmp, 4},
		{Halt, 0},
	}
}

func run(code []Op) int {
	stack := []int{}
	vars := [4]int{}
	pop := func() int {
		v := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		return v
	}
	pc, steps := 0, 0
loop:
	for {
		steps++
		op := code[pc]
		switch op.kind {
		case Push:
			stack = append(stack, op.arg)
			pc++
		case Load:
			stack = append(stack, vars[op.arg])
			pc++
		case Store:
			vars[op.arg] = pop()
			pc++
		case Add:
			b := pop()
			a := pop()
			stack = append(stack, a+b)
			pc++
		case Mul:
			b := pop()
			a := pop()
			stack = append(stack, a*b)
			pc++
		case Mod:
			b := pop()
			a := pop()
			stack = append(stack, a%b)
			pc++
		case Lt:
			b := pop()
			a := pop()
			if a < b {
				stack = append(stack, 1)
			} else {
				stack = append(stack, 0)
			}
			pc++
		case Jz:
			if pop() == 0 {
				pc = op.arg
			} else {
				pc++
			}
		case Jmp:
			pc = op.arg
		case Halt:
			break loop
		}
	}
	fmt.Printf("steps %d\n", steps)
	return vars[0]
}

func main() {
	fmt.Printf("total %d\n", run(program(3000, 2000)))
}
