package debugger

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"github.com/go-delve/delve/service"
	"github.com/go-delve/delve/service/api"
)

type scriptCommand struct {
	name, argument string
	depth          int
	raw            bool
}

func (c scriptCommand) resumes() bool {
	return c.name == "continue" || c.name == "next" || c.name == "step" || c.name == "step-out"
}

func parseScriptCommand(line string) (scriptCommand, error) {
	line = strings.TrimSpace(line)
	if line == "" || strings.HasPrefix(line, "#") {
		return scriptCommand{}, nil
	}
	parts := strings.Fields(line)
	c := scriptCommand{name: parts[0], depth: 20}
	switch c.name {
	case "continue", "next", "step", "step-out", "locals", "exit":
		if len(parts) != 1 {
			return c, fmt.Errorf("%s accepts no arguments", c.name)
		}
	case "break", "print":
		// Preserve spaces in file names; print accepts exactly one source name.
		c.argument = strings.TrimSpace(strings.TrimPrefix(line, c.name))
		if c.argument == "" {
			return c, fmt.Errorf("%s requires a %s", c.name, map[string]string{"break": "location", "print": "source local name"}[c.name])
		}
		if c.name == "print" && (len(parts) != 2 || !sourceIdentifier(c.argument)) {
			return c, fmt.Errorf("print accepts one source local name; use locals to discover names")
		}
	case "bt":
		depthSet := false
		for _, p := range parts[1:] {
			if p == "--raw" && !c.raw {
				c.raw = true
				continue
			}
			n, err := strconv.Atoi(p)
			if err != nil || depthSet || n < 1 || n > 256 {
				return c, fmt.Errorf("bt accepts one depth from 1 to 256 and optional --raw")
			}
			c.depth, depthSet = n, true
		}
	default:
		return c, fmt.Errorf("unknown debug command %q; use break, continue, next, step, step-out, locals, print, bt, or exit", c.name)
	}
	return c, nil
}

func sourceIdentifier(name string) bool {
	for i, r := range name {
		if r == '_' || r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || i > 0 && r >= '0' && r <= '9' {
			continue
		}
		return false
	}
	return name != ""
}

type scriptSession struct {
	client   service.Client
	source   *sourceView
	rawStack bool
}

func (s *scriptSession) execute(c scriptCommand) commandResult {
	switch c.name {
	case "break":
		loc, err := s.source.breakpointLocation(c.argument)
		if err != nil {
			return commandResult{err: err}
		}
		locations, _, err := s.client.FindLocation(api.EvalScope{GoroutineID: -1}, loc, true, nil)
		if err != nil {
			return commandResult{err: err}
		}
		if len(locations) != 1 {
			return commandResult{err: fmt.Errorf("break location %q resolved to %d locations; use a single file:line", c.argument, len(locations))}
		}
		location := locations[0]
		if loc != c.argument { // mapped source function, rather than an explicit file/native location
			functions := map[string]bool{}
			pcs := append([]uint64{location.PC}, location.PCs...)
			for _, pc := range pcs {
				if pc == 0 {
					continue
				}
				concrete, _, err := s.client.FindLocation(api.EvalScope{GoroutineID: -1}, fmt.Sprintf("*%#x", pc), true, nil)
				if err != nil {
					return commandResult{err: err}
				}
				for _, candidate := range concrete {
					functions[candidate.Function.Name()] = true
				}
			}
			if len(functions) > 1 {
				names := make([]string, 0, len(functions))
				for name := range functions {
					names = append(names, name)
				}
				sort.Strings(names)
				return commandResult{err: fmt.Errorf("ambiguous native entry for source function %q (%s); use explicit file:line or a native function location", c.argument, strings.Join(names, ", "))}
			}
		}
		bp, err := s.client.CreateBreakpoint(&api.Breakpoint{Addr: location.PC, Addrs: location.PCs})
		if err != nil {
			return commandResult{err: err}
		}
		return commandResult{result: map[string]any{"breakpoint_id": bp.ID, "location": s.source.frame(location, 0)}}
	case "continue":
		var state *api.DebuggerState
		// Always consume the channel through closure, including on cancellation.
		for next := range s.client.Continue() {
			state = next
		}
		if state == nil {
			return commandResult{err: fmt.Errorf("continue returned no state")}
		}
		return commandResult{state: state, err: state.Err}
	case "next":
		state, err := s.client.Next()
		return commandResult{state: state, err: err}
	case "step":
		state, err := s.client.Step()
		return commandResult{state: state, err: err}
	case "step-out":
		state, err := s.client.StepOut()
		return commandResult{state: state, err: err}
	case "locals", "print":
		values, err := s.locals()
		if err != nil {
			return commandResult{err: err}
		}
		if c.name == "locals" {
			return commandResult{result: values}
		}
		matches := []sourceValue{}
		for _, v := range values {
			if v.Name == c.argument {
				matches = append(matches, v)
			}
		}
		if len(matches) != 1 {
			return commandResult{err: fmt.Errorf("source local %q has %d visible matches; inspect locals", c.argument, len(matches))}
		}
		return commandResult{result: matches[0]}
	case "bt":
		frames, truncated, err := s.stack(c.depth, c.raw || s.rawStack)
		return commandResult{result: map[string]any{"frames": frames, "truncated": truncated}, err: err}
	}
	return commandResult{err: fmt.Errorf("unhandled command %q", c.name)}
}

// Native frame indexes survive filtering; a bounded native scan avoids unlimited
// recursion. Report when the scan or requested source-frame limit truncates it.
func (s *scriptSession) stack(depth int, raw bool) ([]sourceFrame, bool, error) {
	limit := 256
	if raw {
		limit = depth
	}
	frames, err := s.client.Stacktrace(-1, limit, 0, nil)
	if err != nil {
		return nil, false, err
	}
	result := []sourceFrame{}
	truncated := len(frames) > limit
	for i, frame := range frames {
		if frame.Err != "" {
			return nil, true, fmt.Errorf("stack frame %d unavailable: %s", i, frame.Err)
		}
		f := s.source.frame(frame.Location, i)
		if !raw && !f.Source {
			continue
		}
		if len(result) == depth {
			truncated = true
			break
		}
		result = append(result, f)
	}
	return result, truncated, nil
}

func (s *scriptSession) locals() ([]sourceValue, error) {
	frames, err := s.client.Stacktrace(-1, 0, 0, nil)
	if err != nil {
		return nil, err
	}
	if len(frames) == 0 || !s.source.frame(frames[0].Location, 0).Source {
		return nil, fmt.Errorf("selected native frame is outside Manuscript source; continue to a source breakpoint")
	}
	scope := api.EvalScope{GoroutineID: -1}
	locals, err := s.client.ListLocalVariables(scope, valueLoad)
	if err != nil {
		return nil, err
	}
	args, err := s.client.ListFunctionArgs(scope, valueLoad)
	if err != nil {
		return nil, err
	}
	values := []sourceValue{}
	seen := map[string]bool{}
	for _, variable := range append(locals, args...) {
		local, ok := s.source.locals[variable.Name]
		if !ok || variable.Flags&api.VariableShadowed != 0 || seen[variable.Name] {
			continue
		}
		seen[variable.Name] = true
		values = append(values, renderValue(variable, local.Name, local.Type, 0, s.source.recordTypes))
	}
	sort.SliceStable(values, func(i, j int) bool { return values[i].Name < values[j].Name })
	return values, nil
}

func (s *scriptSession) stop(state *api.DebuggerState) (scriptEvent, error) {
	event := scriptEvent{Event: "stop", Reason: "step"}
	if state.CurrentThread != nil {
		thread := state.CurrentThread
		f := s.source.frame(api.Location{File: thread.File, Line: thread.Line, Function: thread.Function}, 0)
		event.Location = &f
		if thread.Breakpoint != nil {
			event.Reason = "breakpoint"
		}
		if f.Source {
			locals, err := s.locals()
			if err != nil {
				return event, err
			}
			event.Locals = locals
		}
	}
	frames, truncated, err := s.stack(20, s.rawStack)
	event.Stack = frames
	event.StackTruncated = truncated
	return event, err
}
