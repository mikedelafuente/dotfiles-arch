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
# - window_name: Name of the tmux window
# - command: Command to run in the main pane (optional, leave empty for shell)
# - split_command: Command to run in a split pane (optional, omit for no split)
# - split_percentage: Percentage of screen for main pane (optional, default 50)
#
# Examples:
#   "editor:nvim"                    - Single pane running nvim
#   "editor:nvim:bash:80"            - nvim (80%) with bash shell (20%) below
#   "shell:::"                       - Just a shell, no command
#   "git:lazygit"                    - Single pane running lazygit
#
LAYOUT=(
    "nvim:nvim:bash:80"      # Window 1: nvim (80%) with terminal (20%) below
    "lazygit:lazygit"        # Window 2: lazygit for git operations
    "claude:claude"          # Window 3: claude code CLI
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
