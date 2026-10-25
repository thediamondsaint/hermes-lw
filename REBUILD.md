# Interface rebuild — October 25, 2026

The previous UI mixed navigation, dialogs, model catalogs and mutable form fields in a single large QML file. Some controls depended on fields owned by another screen. Fixed-size canvases also placed actions outside narrow tiled windows.

## What changed

- Replaced the main UI with four pages: Tasks, Profiles, Models, Settings.
- Split request/connection state into `AppState.qml`; pages and dialogs live in `ui/`.
- Replaced custom click targets with native Button, Dialog, TextField, ComboBox, CheckBox and Menu controls, with keyboard support and readable padding.
- Reused one scrollable form shell and one searchable model picker. Modal titles have a close button at the top right; active mutations/generation keep the form open until their result arrives.
- Every form owns its inputs. Picking a new profile’s model cannot change the existing profile editor. Model changes from the main catalog require confirmation.
- Profiles default to a full copy of default with credentials. Human-readable names are converted to explicit profile IDs.
- Profile generation works for existing profiles as well as new ones; producing a draft does not create or overwrite a profile.
- Errors persist until dismissed and are shown inside the affected form. Generation failures preserve the previous text. Request deadlines and duplicate-operation guards remain in place.
- Corrected and tested favorite-model request fields and HTTPS proxy body/timeout routing. SSH tabs connect before querying their tunneled backend. Connection-local page/project/profile state is remembered during the session.
- Simplified the board to four visual groups while displaying each task’s exact native status. Task access still requires explicit selection and a positive planning budget per selected profile.
- Advanced model filters, clone settings, provider credentials and secondary profile actions are available without crowding the main screens.

## Verification

Validation passed: 36 backend/startup/HTTP tests, 19 native UI interaction checks, screenshot captures, and the real-Hermes/local-fake-provider smoke test. The checks exercise the rebuilt flows. UI tests cover navigation, minimum-size scrolling, default cloning, generation success/error recovery, model picking, existing-profile editing, provider/key saving, task policy validation, unassigned task creation, comments, project creation, search/refresh, favorites and remote request routing.

A short Wayland fixture verifies normal tiling on desktop 4. Interaction tests run on a separate Xvfb display: a hidden Hyprland workspace can defer Qt layout/rendering, so clicking unrendered controls gave misleading test failures. Screenshots contain synthetic profiles/tasks/models only.

## Deliberate limits

- Planning budgets are not hard dollar caps. Use provider-side limits; this app never raises them or silently chooses another key/model.
- Existing OpenRouter key limits remain in force. A successful local fake-provider test does not prove a funded live provider request will succeed.
- Pause is an assignment policy, not worker cancellation. External Hermes clients can bypass this app’s metadata.
- The simplified interface does not carry forward the separate dashboard/Task Advisor, raw JSON editor or bulk task-action toolbar. The backend and existing stored data are retained. Core model advice is in Models → Ask AI; profile generation is in the profile form.
- Real SSH hosts, HTTPS gateways, plugin installations and paid inference require environment-specific checks; fixtures verify request routing without contacting them.
