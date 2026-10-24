# Hermes LW

A native Quickshell prototype for controlling Hermes Agent profiles and the local Hermes Kanban board.

## Run

```bash
cd ~/Projects/hermes-control
./launch.sh
```

The prototype reads the installed Hermes profile files and current board through the `hermes` CLI. It supports profile model/provider/reasoning edits, full `SOUL.md` editing, an advanced JSON view of profile config, profile create/delete, config and full-state cloning, per-profile API credentials for common providers or a custom `*_API_KEY` environment variable, a manager designation, pause/resume for new assignments, and name-based personality generation. Credentials save separately from profile settings, are written to that profile's `.env` with owner-only permissions, and are never returned to the UI. The profile model field includes a searchable OpenRouter catalog grouped by primary use, with model favorites, input/output price sorting, and context size. Catalog data refreshes from OpenRouter and is cached for six hours. A local prompt library supports reusable and favorite prompts.

Projects map to Hermes' isolated Kanban boards. The Projects page supports multiple boards, editable descriptions, owners, colors, budgets, deadlines, progress rollups, cost/effort totals, and JSON export to `~/Downloads`.

Ten workflow additions:

1. Set project budgets and see estimated spend and remaining budget.
2. Give each project an owner.
3. Set project delivery dates.
4. Track completion progress from Hermes task counts.
5. Add task tags and search by tag.
6. Set task due dates and see overdue dates highlighted.
7. Track planned effort hours beside cost estimates.
8. Start from built-in task templates or save custom templates.
9. Save board views with status, assignee, and search filters.
10. Select multiple tasks for bulk assignment, completion, or archiving.

Each task can limit work to selected profiles; the backend enforces that list for individual and bulk assignments. The board also supports scheduled work, task comments, dependency links, and per-project JSON exports while applying task lifecycle changes through Hermes' own CLI. Hermes owns the task body and comment history. The first config save makes a one-time `config.yaml.hermes-control-backup` next to the Hermes config. Pausing a profile in Hermes LW prevents new assignments from this app; already-running tasks continue. Cost estimates are stored by this app in `~/.local/share/hermes-control/estimates.json`; Hermes does not expose provider spend as Kanban task cost, so these are planning numbers rather than metered charges. The UI uses Windows XP Luna styling with a persistent dark mode.

The backend binds only to `127.0.0.1:18731`. It needs Python 3 with PyYAML, Hermes Agent on `PATH`, and Quickshell. On Lua-configured Hyprland, the launcher adds a session-only window rule that opens the desk floating, centered, and sized to the current scaled monitor; it opens only on workspace 5 and does not edit Hyprland config files.
