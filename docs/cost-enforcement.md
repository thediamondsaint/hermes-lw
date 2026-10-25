# Hermes LW: cost and profile enforcement research

Research checked on 2026-10-24 against the installed Hermes Agent v0.19.0 (2026.7.20), current upstream Hermes documentation/source, OpenRouter's current API docs, and LiteLLM's proxy budget docs.

## Findings

### What the installed Hermes runtime can enforce now

The installed `hermes kanban create` supports `--max-runtime` and `--max-retries`. Hermes LW now puts a finite wall-clock limit and `--max-retries 1` on tasks created in the app. Hermes' dispatcher terminates a worker after the runtime expires; its task failure circuit then blocks the task after the first failed attempt. This limits one run's duration and prevents an automatic repeat. It is useful protection against stuck or retrying work, but **it is not a dollar limit**. A fast worker can spend heavily; a slow worker can spend little. Source: the [Hermes Kanban reference](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/kanban.md).

Hermes Kanban runs the one profile named in a task's `assignee`. Hermes LW checks its own saved allowlist before it creates or assigns that task. The allowlist is app metadata, however, and other Hermes clients can write directly to the shared board. Current upstream Hermes also documents `kanban.dispatch_profiles`, a fail-closed allowlist of profiles a dispatcher home can run, but this is **per dispatcher/home**, not per task, and it is absent from the installed v0.19.0. Current upstream supports per-task model/provider overrides as task fields; those fields and the `set-model` CLI are not available in v0.19.0. Do not assume current upstream features exist on an installed Hermes version. Source: [current Hermes Kanban docs](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/kanban.md) and [current Hermes Kanban API model](https://github.com/NousResearch/hermes-agent/blob/main/plugins/kanban/dashboard/plugin_api.py).

### Closest native hard limit for OpenRouter profiles

OpenRouter's Management API can issue a separate inference key with a USD limit. `limit_reset: null` means the limit does not reset; `include_byok_in_limit: true` opts BYOK spend into that limit. This can produce a real **cumulative profile/key cap** when Hermes uses only that issued key. A management key is required to create it; management keys cannot make inference calls, and a new inference key is returned once at creation. Sources: [Create an OpenRouter API key](https://openrouter.ai/docs/api/api-reference/api-keys/create-a-new-api-key) and [OpenRouter key spend controls](https://openrouter.ai/blog/tutorials/team-spend-controls-setup/).

That still does not give each Kanban task its own independent cap. It is a shared key/profile allowance, so several tasks consume the same limit. It can be bypassed if Hermes selects another OpenRouter key from the shell environment, another profile `.env`, a custom endpoint, or a different provider. A correct app integration would need to provision the capped inference key and then verify the Hermes subprocess actually uses it, scrub higher-precedence ambient provider credentials, prevent uncontrolled provider fallback, count BYOK, and expose remaining allowance. It must never store the Management key in Hermes' profile environment. This is a useful next feature, but it is not yet wired into Hermes LW.

### Strongest general per-task dollar design

For per-task ceilings across providers, use an OpenAI-compatible metering gateway between every Hermes model request and the actual providers. Each worker request must carry an authenticated task/session ID; the gateway must associate all main-model, auxiliary, and tool-model calls with that ID; estimate and reserve maximum request cost before forwarding; reconcile actual returned usage; and reject further requests before the configured task budget can be crossed. A local gateway is only a control if every provider route is forced through it and direct provider keys cannot escape it.

[LiteLLM Proxy](https://github.com/BerriAI/litellm) is the most complete existing base we found. Its budget docs describe estimating a request's maximum from `max_tokens` and model pricing, reserving that amount before provider dispatch, rejecting requests that cannot fit, and reconciling actual cost after the response. It requires a database for budgets; its fail-closed mode rejects requests if it cannot verify authoritative spend. Sources: [LiteLLM budgets and reservation](https://docs.litellm.ai/docs/proxy/users) and [LiteLLM virtual keys](https://docs.litellm.ai/docs/proxy/virtual_keys).

The remaining Hermes integration work is substantial: have the dispatcher pass an unforgeable task/session identity to the gateway, route all Hermes model paths through the gateway, keep API credentials only at the gateway, and ensure the session budget uses pre-request reservation under concurrency. Then add an explicit hard-limit mode that refuses execution if the gateway or price data is unavailable. A warning, post-response usage report, `max_tokens` alone, or wall-clock timeout is not equivalent to a dollar cap.

### Upstream cost-control project reviewed

The community repo [hermes-cost-control](https://github.com/Antoine130676/hermes-cost-control) demonstrates provider lock-down and routing ideas. Its author reports provider-console measurements and describes a provider lock that removed alternate keys, while also explicitly saying the routing savings were not yet established. It is a useful example of restricting alternate credential paths, not a drop-in hard per-task budget implementation.

## Safe current behavior in Hermes LW

- New tasks start with no allowed profiles; every profile must be checked explicitly. An unassigned task is created Blocked. Promote/Unblock require an explicitly assigned approved profile, and an existing task must be blocked before its assignee can be removed.
- The app rejects assignments outside its saved list. Tasks from other clients have no Hermes LW allowlist and fail closed in this app until one is saved.
- Every allowed profile requires a separate positive USD planning value. Those values are saved for planning, not enforced by Hermes.
- App-created tasks have a finite Hermes worker runtime and one attempt. A timeout prevents automatic retry, but the runtime is not translated into dollars.
- AI/Profiles uses local matching and sends no request. The Task Advisor only estimates published token prices for a sample size; it does not run a model.

## Recommended implementation sequence

1. **OpenRouter profile cap:** offer an opt-in “Provision limited key” flow. Accept an OpenRouter Management key only for the create/update call; create a non-resetting inference key with BYOK counted; replace only the selected profile's OpenRouter inference credential; keep the Management key out of profile `.env`; show cap/remaining using the key-management API. Fail closed if a different credential path is detected.
2. **Hermes version adapter:** detect runtime flags and task schema. Add per-task model/provider overrides only when installed Hermes supports them. Use `dispatch_profiles` only when that key is supported, with warning that it is per dispatcher and not per task.
3. **Per-task provider-neutral caps:** prototype an optional local gateway based on LiteLLM with Postgres-backed reservation and fail-closed budget checks. Route all Hermes provider traffic through it; do not start paid tasks until proxy identity, pricing, reservation, and deny-path checks pass.
4. **User-visible accounting:** show pending reservation, actual provider-reported cost, cap remaining, failed/unpriced requests, and which provider credential was used. Keep planning estimates visually separate from enforced limits.

Until step 1 or 3 is wired and verified, Hermes LW does not claim a hard dollar ceiling.
