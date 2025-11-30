# Code Command Configuration

The `code` command now uses **tmuxinator** for session management, which is much more powerful and easier to configure than custom bash scripts.

## Configuration File

The tmux layout is configured in: **`~/.config/tmuxinator/code.yml`**

This YAML file defines:
- Window names
- Pane layouts
- Commands to run in each pane
- Split percentages

## Customizing Your Layout

Edit `~/.config/tmuxinator/code.yml` to customize your development environment.

### Current Layout

**Window 1 (code)**:
- Left side (main pane, 65% width):
  - Top (85%): nvim
  - Bottom (15%): bash
- Right side (35% width): claude

**Window 2 (lazygit)**:
- Full window: lazygit

### Tmuxinator Documentation

For more advanced layouts and options, see the [Tmuxinator documentation](https://github.com/tmuxinator/tmuxinator).

## Example Customizations

### Change Split Percentages

In `code.yml`, modify the `split-window` commands:
```yaml
- tmux split-window -v -l 20%  # Bottom pane gets 20% instead of 15%
```

### Add More Windows

```yaml
windows:
  - code:
      # ... existing config
  - lazygit:
      # ... existing config
  - server:
      panes:
        - npm run dev
```

### Change Pane Commands

Simply edit the pane list:
```yaml
panes:
  - nvim
  - htop  # Changed from 'claude'
```
