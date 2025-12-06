# ~/.bashrc

# -------------------------
# Readline Configuration
# -------------------------
# Use custom .inputrc for readline settings (tab completion, key bindings, etc.)
export INPUTRC=~/.inputrc

# ----------------
# Source - https://stackoverflow.com/a
# Posted by jogarcia, modified by community. See post 'Timeline' for change history
# Retrieved 2025-11-16, License - CC BY-SA 4.0
if command -v tmux &> /dev/null && [ -n "$PS1" ] && [[ ! "$TERM" =~ screen ]] && [[ ! "$TERM" =~ tmux ]] && [ -z "$TMUX" ]; then
    echo "Starting tmux..."
    tmux
fi
# ----------------


# Give a small intro message upon starting a new shell that most developers use
# echo "Type 'aliases' to see custom aliases and key bindings."

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
        elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi


# Set up environment variables
if command -v nvim &> /dev/null; then
    export EDITOR=nvim
    export VISUAL=nvim
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
    case ":$PATH:" in
        *":$HOME/bin:"*) ;;
        *) export PATH="$HOME/bin:$PATH" ;;
    esac
fi

if [ -d "$HOME/.local/bin" ] ; then
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac
fi


# Aliases

# Navigation & Directory
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
alias -- -='cd -'
alias z='zoxide'
alias zi='zoxide query -i'  # Interactive selection
alias zq='zoxide query'      # Query without changing directory

# File Operations
alias ls='ls --color=auto'
alias la='ls -la'
alias ll='ls -lh'
alias l='ls -CF'
alias grep='grep --color=auto'
alias mkdir='mkdir -pv'
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -i'

# Git
alias ga='git add'
alias gaa='git add --all'
alias gb='git branch'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'
alias gco='git checkout'
alias gd='git diff'
alias gf='git fetch'
alias gl='git log'
alias glog='git log --oneline --graph --decorate'
alias gp='git pull'
alias gpull='git pull'
alias gpush='git push'
alias gs='git status'
alias gst='git status'
alias lzg='lazygit'

# Docker
alias d='docker'
alias dc='docker compose'
alias dcd='docker compose down -v'
alias dcu='docker compose up -d'
alias dex='docker exec -it'
alias di='docker images'
alias dlogs='docker logs -f'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias lzd='lazydocker'

# System & Utilities
alias c='clear'
alias h='history'
alias path='echo -e ${PATH//:/\\n}'
alias reload='source ~/.bashrc'
alias please='sudo'
alias ports='netstat -tulanp'
alias qq='exit'

# Development Tools
alias py='python3'
alias pip='pip3'
alias v='nvim'
alias vim='nvim'
alias vimcheat='bat ~/.nvim-cheatsheet.md --style=plain --paging=always'
alias serve='python3 -m http.server'
alias jsonpp='python3 -m json.tool'
alias myip='curl ifconfig.me'

# GitHub Copilot CLI
# Note: Requires authentication first with: github-copilot-cli auth
if command -v github-copilot-cli &> /dev/null; then
    eval "$(github-copilot-cli alias -- "$0")"
fi

# Functions

# Better touch that creates directories if they don't exist
touch() {
    for file in "$@"; do
        if [[ "$file" == */* ]]; then
            mkdir -p "$(dirname "$file")"
        fi
        command touch "$file"
    done
}

# -------------------------
# Note: Key bindings and completion settings are now in ~/.inputrc
# See $INPUTRC for tab completion, history search, and editing keybindings
# -------------------------

# Function to display welcome message
welcome() {
    if [ -f "$HOME/.welcome.md" ]; then
        if command -v bat &> /dev/null; then
            bat --style=grid --paging=never "$HOME/.welcome.md"
        else
            cat "$HOME/.welcome.md"
        fi
    else
        echo "Welcome message file not found at $HOME/.welcome.md"
    fi
}

aliases() {
    # Create a temporary file for bat to display with syntax highlighting
    local temp_file=$(mktemp)
    
    {
        echo ""
        echo "╔══════════════════════════════════════════════════════════════════════════════╗"
        echo "║                           📋 Custom Aliases                                  ║"
        echo "╚══════════════════════════════════════════════════════════════════════════════╝"
        echo ""
        
        # Display aliases in a formatted table
        alias | sed 's/^alias //' | awk -F= '{
            alias=$1
            cmd=$2
            gsub(/^'\''|'\''$/, "", cmd)
            printf "  %-12s → %s\n", alias, cmd
        }' | sort
        
        echo ""
        echo "╔══════════════════════════════════════════════════════════════════════════════╗"
        echo "║                         ⌨️  Custom Key Bindings                              ║"
        echo "╚══════════════════════════════════════════════════════════════════════════════╝"
        echo ""
        
        # Display key bindings in readable format - only show our custom bindings
        # These are configured in ~/.inputrc (tmux-compatible)
        printf "  %-22s → %s\n" "Tab" "Cycle through completions (menu-style)"
        printf "  %-22s → %s\n" "Shift+Tab" "Cycle backward through completions"
        printf "  %-22s → %s\n" "Up Arrow" "Search history backward (with prefix)"
        printf "  %-22s → %s\n" "Down Arrow" "Search history forward (with prefix)"
        printf "  %-22s → %s\n" "Ctrl+Right/Alt+F" "Jump forward one word"
        printf "  %-22s → %s\n" "Ctrl+Left/Alt+B" "Jump backward one word"
        printf "  %-22s → %s\n" "Ctrl+K" "Delete from cursor to end of line"
        printf "  %-22s → %s\n" "Ctrl+U" "Delete from cursor to start of line"
        printf "  %-22s → %s\n" "Ctrl+W" "Delete word backward"
        printf "  %-22s → %s\n" "Ctrl+A" "Go to beginning of line"
        printf "  %-22s → %s\n" "Ctrl+E" "Go to end of line"
        
        echo ""
        echo "  💡 Note: All key bindings configured in ~/.inputrc"
        echo "     Run 'bat ~/.inputrc' to see full readline configuration"
        
        
        echo ""
        echo "╔══════════════════════════════════════════════════════════════════════════════╗"
        echo "║                        🛠️  Essential Tools Installed                         ║"
        echo "╚══════════════════════════════════════════════════════════════════════════════╝"
        echo ""
        
        # Show essential packages from bootstrap.sh (keep in sync with ESSENTIAL_PACKAGES)
        # Alphabetically sorted for easier reading
        local tools=(
            "bat:Cat clone with syntax highlighting"
            "btop:Resource monitor (better than htop)"
            "curl:Transfer data from/to servers"
            "duf:Better disk usage utility (modern df)"
            "fastfetch:System information display (neofetch successor)"
            "fd:Fast alternative to find (fd command)"
            "fzf:Fuzzy finder for command-line"
            "gh:GitHub CLI"
            "git:Version control system"
            "htop:Interactive process viewer"
            "jq:JSON processor for command line"
            "ncdu:Disk usage analyzer with ncurses"
            "netstat:Network utilities (netstat, ifconfig)"
            "ripgrep:Fast recursive search (rg command)"
            "shellcheck:Shell script analysis tool"
            "stow:Symlink farm manager for dotfiles"
            "tldr:Simplified man pages with examples"
            "tmux:Terminal multiplexer"
            "tree:Display directory structure as tree"
            "wget:Download files from the web"
            "xsel:Clipboard manipulation tool"
            "zoxide:Smart cd - learns your navigation habits - current aliases z, zi, zq"
        )
        
        for tool_info in "${tools[@]}"; do
            local tool="${tool_info%%:*}"
            local desc="${tool_info#*:}"
            # Special case for ripgrep which uses 'rg' command
            if [ "$tool" = "ripgrep" ]; then
                if command -v rg &> /dev/null; then
                    printf "  %-12s → %s\n" "$tool" "$desc"
                else
                    printf "  \033[0;31m%-12s\033[0m → %s\n" "MISSING" "$tool" "$desc"
                fi
            else
                if command -v "$tool" &> /dev/null; then
                    printf "  %-12s → %s\n" "$tool" "$desc"
                else
                    printf "  \033[0;31m%-12s\033[0m → %s\n" "MISSING" "$tool" "$desc"
                fi
            fi
        done
        
        if command -v zoxide &> /dev/null; then
            
            echo ""
            echo "╔══════════════════════════════════════════════════════════════════════════════╗"
            echo "║                        🧭 Zoxide Usage (Smart Navigation)                    ║"
            echo "╚══════════════════════════════════════════════════════════════════════════════╝"
            echo ""
            printf "  %-12s → %s\n" "z <keyword>" "Jump to directory (e.g., 'z dotfiles')"
            printf "  %-12s → %s\n" "zi <keyword>" "Interactive directory selection"
            printf "  %-12s → %s\n" "z -" "Go back to previous directory"
            printf "  %-12s → %s\n" "zq <keyword>" "Query directory path without jumping"
            echo ""
            echo "  💡 Zoxide learns from your cd usage and lets you jump to frequently"
            echo "     used directories by typing partial names. Just use it for a while!"
        fi
        
        if command -v tmux &> /dev/null; then
            
            echo ""
            echo "╔══════════════════════════════════════════════════════════════════════════════╗"
            echo "║                         🪟  Tmux Key Bindings                                ║"
            echo "╚══════════════════════════════════════════════════════════════════════════════╝"
            echo ""
            echo "  Prefix: Ctrl+B (press first, then the command key)"
            echo ""
            
            # Session Management
            printf "  %-22s → %s\n" "Ctrl+B  d" "Detach from session"
            printf "  %-22s → %s\n" "Ctrl+B  $" "Rename current session"
            printf "  %-22s → %s\n" "Ctrl+B  s" "List/switch sessions"
            
            echo ""
            # Window Management
            printf "  %-22s → %s\n" "Ctrl+B  c" "Create new window"
            printf "  %-22s → %s\n" "Ctrl+B  ," "Rename current window"
            printf "  %-22s → %s\n" "Ctrl+B  w" "List/switch windows"
            printf "  %-22s → %s\n" "Ctrl+B  n" "Next window"
            printf "  %-22s → %s\n" "Ctrl+B  p" "Previous window"
            printf "  %-22s → %s\n" "Ctrl+B  0-9" "Switch to window number"
            printf "  %-22s → %s\n" "Ctrl+B  &" "Kill current window"
            
            echo ""
            # Pane Management
            printf "  %-22s → %s\n" "Ctrl+B  %" "Split pane vertically"
            printf "  %-22s → %s\n" "Ctrl+B  \"" "Split pane horizontally"
            printf "  %-22s → %s\n" "Ctrl+B  o" "Switch to next pane"
            printf "  %-22s → %s\n" "Ctrl+B  ;" "Toggle last pane"
            printf "  %-22s → %s\n" "Ctrl+B  x" "Kill current pane"
            printf "  %-22s → %s\n" "Ctrl+B  {" "Move pane left"
            printf "  %-22s → %s\n" "Ctrl+B  }" "Move pane right"
            printf "  %-22s → %s\n" "Ctrl+B  z" "Toggle pane zoom (fullscreen)"
            printf "  %-22s → %s\n" "Ctrl+B  ↑↓←→" "Navigate between panes"
            
            echo ""
            # Copy Mode
            printf "  %-22s → %s\n" "Ctrl+B  [" "Enter copy mode (scroll/search)"
            printf "  %-22s → %s\n" "Ctrl+B  ]" "Paste from buffer"
            printf "  %-22s → %s\n" "q (in copy mode)" "Exit copy mode"
            
            echo ""
            # Helpful Commands
            printf "  %-22s → %s\n" "Ctrl+B  ?" "Show all key bindings"
            printf "  %-22s → %s\n" "Ctrl+B  t" "Show time"
            
            echo ""
            echo "  💡 Outside tmux: 'tmux' (start), 'tmux ls' (list), 'tmux attach' (reconnect)"
        fi
        
        # Add GitHub Copilot CLI aliases if available
        if command -v github-copilot-cli &> /dev/null; then
            echo ""
            echo "🤖 AI Assistant (GitHub Copilot CLI):"
            echo "  ??        → Ask for any command help"
            echo "  git?     → Git-specific help"
            echo "  gh?       → GitHub CLI help"
            echo "  Note: Run 'github-copilot-cli auth' to authenticate first"
        fi
        
        echo ""
    } > "$temp_file"
    
    # Display with bat if available, otherwise use cat
    if command -v bat &> /dev/null; then
        bat --style=plain --paging=never "$temp_file"
    else
        cat "$temp_file"
    fi
    
    rm -f "$temp_file"
}

# Enable color support for ls and grep
export CLICOLOR=1
export LSCOLORS=GxFxCxDxBxegedabagacad

# Load additional scripts if they exist
if [ -f "$HOME/.bash_aliases" ]; then
    . "$HOME/.bash_aliases"
fi

# Initialize Starship prompt if installed
if command -v starship &> /dev/null; then
    eval "$(starship init bash)"
fi

# User-specific shell configuration for bash
if [ -f "$HOME/.cargo/env" ]; then
    . "$HOME/.cargo/env"
fi

# NVM (Node Version Manager) setup
export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"  # This loads nvm bash_completion


# Initialize zoxide if installed
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init bash)"
fi

# Herd Lite PHP environment variables if installed
if [ -d "$HOME/.config/herd-lite/bin" ]; then
    export PATH="$HOME/.config/herd-lite/bin:$PATH"
    export PHP_INI_SCAN_DIR="$HOME/.config/herd-lite/bin:$PHP_INI_SCAN_DIR"
fi

export PATH="$PATH:/home/dela/.config/composer/vendor/bin"
export PATH="$PATH:/home/dela/.config/composer/vendor/bin"

# Ruby gem binaries
if [ -d "$HOME/.local/share/gem/ruby/3.4.0/bin" ]; then
    export PATH="$HOME/.local/share/gem/ruby/3.4.0/bin:$PATH"
fi
