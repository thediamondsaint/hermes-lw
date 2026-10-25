# Hermes LW

A native Quickshell prototype for controlling Hermes Agent profiles and the local Hermes Kanban board.

## Run

```bash
cd ~/Projects/hermes-control
./launch.sh
```

The prototype reads the installed Hermes profile files and current board through the `hermes` CLI. The **Options** toolbar button and sidebar page open app-wide settings for the local Hermes LW connection, startup board, manager profile, theme, catalog refresh, and keyboard shortcuts. **Models & Providers** is a separate profile editor for backend, model, reasoning, and credentials. It supports full `SOUL.md` editing, an advanced JSON view of profile config, profile create/delete, config and full-state cloning, per-profile credentials for every inference provider registered by the installed Hermes version, pause/resume for new assignments, and name-based personality generation. API-key credentials are written to that profile's `.env` with owner-only permissions. Custom/local OpenAI-compatible endpoints have a per-profile base URL and key saved in the profile config with owner-only permissions. OAuth and system-auth providers use Hermes' own sign-in flow (`hermes model`). Secrets never return to the UI. The OpenRouter catalog has multi-term search, creator and use filters, modality/capability/price/context filters, grouping by use, creator, price, context, or modality, and sorting by popularity order, name, release date, price, or context. Its catalog controls are laid out in separate rows for smaller windows: **Collapse all groups**, **Expand all groups**, sample input/output token fields, per-model sample cost, and **Show next 100 models**. Other providers accept their provider-specific model ID. Catalog data refreshes from OpenRouter and is cached for six hours. A local prompt library supports reusable and favorite prompts.

**Provider Connections** opens a dedicated window from Options. Choose a Hermes profile, search and filter the providers installed with Hermes, inspect each provider's setup status and credential variables, set its model ID or a custom/local endpoint URL, and save or clear that profile's API key without displaying its value. OpenRouter model choices flow from the catalog into this window.

The model catalog follows the provider selected for the active profile. OpenRouter uses its full priced catalog; other providers use model IDs discovered through Hermes' installed provider registry and profile credentials. Since Hermes does not return consistent pricing metadata for those catalogs, their prices are labeled unavailable. Input and output token prices can be filtered independently. **Task Advisor** suggests catalog models by task type, sample-token cost, and context length, and drafts prompts for code audits, implementation, research, writing, and general work. It does not send task text to a model. **Plugins & Tools** manages profile-scoped Hermes plugins, platform-specific toolsets, and MCP app connections. Plugin installs start disabled, enabling tool overrides requires an explicit opt-in, and plugin source trust is called out in the UI. MCP apps can be added as local stdio processes or remote HTTP services, installed from Hermes' catalog, tested, and removed. Remote bearer tokens are stored in the selected profile's private `.env`; local stdio environment values follow Hermes' profile config format. The API only returns credential variable names, never their values or raw MCP command arguments. These controls use Hermes' own config and plugin validation helpers.

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

The **AI/Profiles** checkbox locally matches task words to profile names, models, and personalities; suggestions never select a profile. This matching is heuristic and makes no model request. Each task has a fail-closed profile allowlist: profiles are not selected by default, and the backend rejects task creation or assignment when a profile is outside the saved list. Tasks imported from Hermes without an Hermes LW allowlist are treated as unassigned to all profiles until an allowlist is saved. A separate positive USD planning budget is required for every allowed profile and is saved with the task. **This budget is metadata only: the current Hermes task runner does not accept or enforce per-task dollar caps. Do not treat it as a spend guarantee.** The board also supports scheduled work, task comments, dependency links, and per-project JSON exports while applying task lifecycle changes through Hermes' own CLI. Hermes owns the task body and comment history. The first config save makes a one-time `config.yaml.hermes-control-backup` next to the Hermes config. Pausing a profile in Hermes LW prevents new assignments from this app; already-running tasks continue. The UI uses Windows XP Luna styling with a persistent dark mode.

The backend binds only to `127.0.0.1:18731` and rejects nonlocal hosts and cross-origin web requests. It needs Python 3 with PyYAML, Hermes Agent on `PATH`, and Quickshell. On Lua-configured Hyprland, the launcher applies a session-only rule to float, center, and size the desk for the current scaled monitor. It does not force a workspace or edit Hyprland config files.

The latest 25-item audit, GitHub references, and implemented fixes are documented in [AUDIT.md](AUDIT.md).

## Screenshots

The workspace screenshots use fictional demo profiles, prompts, and tasks. The Plugins & Tools screenshot is cropped to the capability panel and contains no profile list or credentials.

![Hermes LW overview](screenshots/overview.png)

![Hermes LW options](screenshots/options.png)

![Hermes LW provider connections](screenshots/provider-connections.png)

![Hermes LW Kanban board](screenshots/kanban.png)

![Hermes LW profiles](screenshots/profiles.png)

![Hermes LW model catalog](screenshots/model-catalog.png)

![Hermes LW plugins and tools](screenshots/plugins-tools.png)
