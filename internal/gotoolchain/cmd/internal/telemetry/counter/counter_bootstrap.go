// Code copied from the Go distribution by scripts/mkgotoolchain; DO NOT EDIT.

// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//

package counter

import "github.com/manuscript-lang/manuscript/internal/gotoolchain/internal/flag"

type dummyCounter struct{}

func (dc dummyCounter) Inc() {}

func Open()                                                               {}
func Inc(name string)                                                     {}
func New(name string) dummyCounter                                        { return dummyCounter{} }
func NewStack(name string, depth int) dummyCounter                        { return dummyCounter{} }
func CountFlags(name string, flagSet flag.FlagSet)                        {}
func CountFlagValue(prefix string, flagSet flag.FlagSet, flagName string) {}
