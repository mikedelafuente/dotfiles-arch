# Configuration for the 'code' command
# This file is sourced by the code script to customize your development environment

# Terminal to use (default: kitty)
TERMINAL="kitty"

# NOTE: Session names are automatically generated from the directory name.
# This allows you to have multiple repos open simultaneously, each with their own session.
# Example: 'code ~/repos/dotfiles-arch' creates session 'dotfiles-arch'

# Layout configuration
# Each line defines a tmux window with the format:
# "window_name:command:split_command:split_percentage"
#
# For simple 1 or 2 pane layouts:
#   "editor:nvim"                    - Single pane running nvim
#   "editor:nvim:bash:90"            - nvim (90%) with bash shell (10%) below
#
# For 3-pane layout (left column split, right column full height):
#   "window_name:left_cmd,right_cmd:bottom_cmd:top_pct:right_pct"
#   - top_pct: Percentage of LEFT side height for top pane
#   - right_pct: Percentage of TOTAL width for right pane
#   Example: "code:nvim,claude:bash:85:35" creates:
#     - Left side (65% width): nvim (top 85%) + bash (bottom 15%)
#     - Right side (35% width): claude (full height)
#
LAYOUT=(
    "code:nvim,claude:bash:85:35"  # Window 1: nvim (85% height) + bash (15%) on left (65% width), claude on right (35% width)
    "lazygit:lazygit"              # Window 2: lazygit for git operations
)

# Additional layout examples (uncomment and modify as needed):
#
# LAYOUT=(
#     "editor:nvim"                  # Simple nvim window
#     "terminal:::"                  # Empty shell
#     "server:npm run dev"           # Dev server
#     "tests:npm test -- --watch"    # Test watcher
# )
#
# LAYOUT=(
#     "nvim:nvim:npm run dev:70"     # nvim (70%) with dev server (30%)
#     "git:lazygit"                  # Git interface
#     "db:psql mydb"                 # Database shell
# )
