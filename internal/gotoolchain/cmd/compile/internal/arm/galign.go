// Code copied from the Go distribution by scripts/mkgotoolchain; DO NOT EDIT.

// Copyright 2009 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package arm

import (
	"github.com/manuscript-lang/manuscript/internal/gotoolchain/cmd/compile/internal/ssa"
	"github.com/manuscript-lang/manuscript/internal/gotoolchain/cmd/compile/internal/ssagen"
	"github.com/manuscript-lang/manuscript/internal/gotoolchain/cmd/internal/obj/arm"
	"github.com/manuscript-lang/manuscript/internal/gotoolchain/internal/buildcfg"
)

func Init(arch *ssagen.ArchInfo) {
	arch.LinkArch = &arm.Linkarm
	arch.REGSP = arm.REGSP
	arch.MAXWIDTH = (1 << 32) - 1
	arch.SoftFloat = buildcfg.GOARM.SoftFloat
	arch.ZeroRange = zerorange
	arch.Ginsnop = ginsnop

	arch.SSAMarkMoves = func(s *ssagen.State, b *ssa.Block) {}
	arch.SSAGenValue = ssaGenValue
	arch.SSAGenBlock = ssaGenBlock
}
