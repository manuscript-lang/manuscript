// Code copied from the Go distribution by scripts/mkgotoolchain; DO NOT EDIT.

// Copyright 2022 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package loong64

import (
	"github.com/manuscript-lang/manuscript/internal/gotoolchain/cmd/compile/internal/ssa"
	"github.com/manuscript-lang/manuscript/internal/gotoolchain/cmd/compile/internal/ssagen"
	"github.com/manuscript-lang/manuscript/internal/gotoolchain/cmd/internal/obj/loong64"
)

func Init(arch *ssagen.ArchInfo) {
	arch.LinkArch = &loong64.Linkloong64
	arch.REGSP = loong64.REGSP
	arch.MAXWIDTH = 1 << 50
	arch.ZeroRange = zerorange
	arch.Ginsnop = ginsnop

	arch.SSAMarkMoves = func(s *ssagen.State, b *ssa.Block) {}
	arch.SSAGenValue = ssaGenValue
	arch.SSAGenBlock = ssaGenBlock
	arch.LoadRegResult = loadRegResult
	arch.SpillArgReg = spillArgReg
}
