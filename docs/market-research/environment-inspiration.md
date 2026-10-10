# Environment inspiration and council guidance

Research date/access date for all URLs: 2026-10-09. Status: proposed advice.
Scope: ideas for this repository's Arch/Ubuntu GNOME workstation workflows.
Existing README, PACKAGES and deployment guidance were reused.
This note grants no implementation, publication, deployment or scheduling permission.

## Suggested council instruction

Optimize my daily development workflows for reliability, speed, comfort and low
maintenance. Inspect my existing setup and identify concrete friction before
recommending changes. Use the creators below for ideas, then verify each proposed
change against current upstream documentation and this repository's constraints.
Preserve Arch/Ubuntu, GNOME Wayland, Kitty, tmux, Neovim/Zed, package ownership and
installed-copy deployment unless I explicitly approve a change in direction.
Reuse existing tools before adding packages or services. Consider consistency,
readability, keyboard use, accessibility and laptop/dock/multi-monitor behavior.

When a prompt or goal is vague, consult relevant creator examples or articles to
develop concrete options. Specific articles and video timestamps are optional;
include them when they help explain an option or resolve uncertainty.

For each idea report: the task improved, present behavior, proposed behavior,
relevant versions, Arch/Ubuntu applicability, maintenance/dependency cost,
conflicts, rollback, and one observable success check.
Rank by recurring benefit, then maintenance cost. Recommend at most three ideas
per review, including keeping the current setup where adequate. Separate personal
preference from measured benefit and uncertain compatibility from verified facts.
Record ideas as proposals; publish GitHub work only under actual authority.

## Sources and fit

| Source | Primary references | Suggested remit and limitations |
|---|---|---|
| Josean Martinez | https://www.josean.com/posts/tmux-setup ; https://github.com/josean-dev/dev-environment-files | Integrated tmux/Neovim, terminal ergonomics and CLI workflows. The repo includes multiple generations/platforms; select individual ideas and verify current plugin APIs. Its Stow setup does not replace DFA deployment. |
| bashbunni | https://www.youtube.com/watch?v=aZQWLG4JDFQ ; https://github.com/bashbunni/dotfiles | tmux workflow, navigation and terminal ergonomics. The tmux video dates to 2022-08-20; current GitHub profile lists Doom Emacs, so older Neovim configs are historical examples rather than proof of present recommendations. |
| typecraft | https://typecraft.dev/ ; https://github.com/typecraft-dev/dotfiles | Vim/Linux/Docker practice and terminal workflow/configuration examples. Dotfiles include Hyprland/i3; translate useful workflow ideas to GNOME rather than assuming those desktop configurations apply. |
| Chris Titus Tech | https://christitus.com/ ; https://github.com/ChrisTitusTech/linutil ; https://linutil.christitus.com/faq/ | Linux setup and maintenance patterns. Linutil's distro-specific mutations and advertised installation command are not this repository's installation/update/deployment policy. Inspect exact scripts without running the toolbox. |
| NetworkChuck | https://academy.networkchuck.com/home ; https://www.youtube.com/watch?v=ey4u7OUAF3c | Networking, remote access and homelab discovery. The tunnel example dates to 2022-12-14; revalidate authentication and product behavior from current vendor documentation before a proposal. Additional infrastructure needs a concrete user need. |
| Julia Evans | https://jvns.ca/ | Articles on terminal behavior, Linux debugging, networking and Git. Match individual article date and tool version before using instructions. |
| MIT Missing Semester | https://missing.csail.mit.edu/ | 2026 course notes/videos on shell, development tools, debugging and Git. Teaching examples still need adaptation to the actual workstation. |
| ArchWiki / Ubuntu Desktop docs | https://wiki.archlinux.org/index.php/General_Recommendations ; https://ubuntu.com/desktop/docs/en/latest/ | Platform-specific validation references for setup and administration. These are live docs, not pinned implementation evidence; capture the relevant page/version at proposal admission. |

These are research entry points, not versioned configurations approved for import.
No upstream repository commit or tool version was selected or tested. Browse the
specific implementation/docs and record exact identities before implementation.
Some documentation roots returned limited content; no compatibility claim relies
on unreadable pages. Sources above establish topics/examples, not benchmarked
productivity benefits or complete Arch/Ubuntu support.

## Council coverage

Single-agent lenses: BA owns actual workflow friction/observable acceptance; PM
owns value ranking and user priorities; TPM owns distro/plugin/API compatibility;
SE owns existing implementation reuse and checks. SA omitted for this source-list
question because no structural change is proposed. One cross-check: copying a
creator's complete environment can conflict with GNOME, shell choice and deployment
ownership. Prefer a bounded improvement to an existing workflow. No independent
agents, challenge replies or follow-ups were run. No retained dissent.

Unanswered: which daily workflow currently causes the most friction; desired
balance of visual customization versus maintenance. These need user evidence,
not a creator's popularity. This recommendation remains proposed.
