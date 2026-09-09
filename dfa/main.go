// Command dfa is the front door for dotfiles-arch day-to-day tooling: a
// Bubble Tea dashboard (this ticket) that later tickets grow into a full
// software catalog + maintenance TUI. See CONTEXT.md and GitHub issue #35
// for the full vision; this file only wires up the skeleton described in
// issue #38.
package main

import (
	"fmt"
	"os"

	"github.com/mikedelafuente/dotfiles-arch/dfa/internal/dashboard"
)

func main() {
	// The only subcommand today is "bootstrap" (the exec target from
	// bootstrap.sh). There's no first-run/onboarding flow yet, so it's just
	// an alias into the same dashboard — later tickets can differentiate
	// first-run behavior here. Any other/no argument also opens the
	// dashboard, since it's the only real thing dfa does right now.
	args := os.Args[1:]
	if len(args) > 0 {
		switch args[0] {
		case "bootstrap":
			// No first-run flow yet — just open the dashboard.
		case "-h", "--help":
			printUsage()
			return
		default:
			fmt.Fprintf(os.Stderr, "dfa: unknown command %q\n\n", args[0])
			printUsage()
			os.Exit(1)
		}
	}

	if err := dashboard.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "dfa: %v\n", err)
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Println(`dfa — dotfiles-arch front door

Usage:
  dfa              Open the dashboard
  dfa bootstrap    Open the dashboard (bootstrap.sh's handoff target)
  dfa -h, --help   Show this help`)
}
