# Retrospective Design Audit

This document records the current high-cost design issues in the app after extended parity work.

## Highest-cost issues

### 1. `ManagePageController` is still a monolith
File:
- `lib/eirinchan_web/controllers/manage_page_controller.ex`

Current state:
- ~2000 lines
- mixes dashboard, queues, page/theme editing, config editing, announcements, feedback, reports, board admin, and multiple browser-only flows

Why this is costly:
- changes in one admin area have a large regression surface
- permission and rendering logic are hard to isolate
- testing is broad instead of local

Recommended change:
- split into focused controllers:
  - `Manage.DashboardController`
  - `Manage.QueueController`
  - `Manage.ConfigController`
  - `Manage.PageController`
  - `Manage.ThemeController`

### 2. `Posts` is still too large, even after extractions
Files:
- `lib/eirinchan/posts.ex`
- `lib/eirinchan/posts/moderation.ex`
- `lib/eirinchan/posts/validation.ex`
- `lib/eirinchan/posts/metadata.ex`
- `lib/eirinchan/posts/flags.ex`
- `lib/eirinchan/posts/upload_preparation.ex`
- `lib/eirinchan/posts/thread_lookup.ex`

Current state:
- core file is still >1100 lines
- orchestration, persistence, post targeting, anti-spam, and creation flow are still tightly coupled

Why this is costly:
- the posting path remains the highest-risk backend surface
- regressions in replies/OP/moderation still tend to meet in this module

Recommended change:
- extract the remaining orchestration into:
  - `Posts.Create`
  - `Posts.Targeting`
  - `Posts.Persistence`
- keep `Posts` as a thin facade only

### 3. Rendering is still split between HEEx components and raw HTML helpers
Files:
- `lib/eirinchan_web/post_view.ex`
- `lib/eirinchan_web/post_components.ex`
- `lib/eirinchan/build.ex`

Current state:
- more display has moved into HEEx, but `PostView` is still >1100 lines
- there are still many `raw(...)` boundaries and string helpers in the display pipeline

Why this is costly:
- formatting regressions happen when one fragment path diverges from another
- board page, thread page, updater fragments, moderation pages, and static build can drift apart

Recommended change:
- continue moving file/info/media wrappers and remaining post fragments into HEEx components
- reduce `PostView` to formatting/data helpers rather than HTML assembly
- have `build.ex` reuse the same components where possible

### 4. Frontend behavior is still split across too many interdependent scripts
Largest active files:
- `priv/static/js/post-filter.js`
- `priv/static/js/auto-reload.js`
- `priv/static/js/quick-reply.js`
- `priv/static/js/ajax.js`
- `priv/static/js/server-thread-watcher.js`
- `priv/static/js/post-menu.js`

Why this is costly:
- updater, quick reply, filters, and menus all mutate the same post/thread DOM
- regressions often come from interaction between scripts, not one script alone
- page load vs updater insert vs AJAX insert is still a complex lifecycle

Recommended change:
- define one explicit frontend lifecycle for inserted content:
  - init page
  - init inserted post
  - init inserted thread
- route updater/AJAX/quick-reply through that lifecycle only
- keep interaction-only features in JS, but move truth/rendering lower

### 5. The updater system still polls full page fragments frequently
Files:
- `priv/static/js/auto-reload.js`
- board/thread/catalog fragment templates and controllers

Current state:
- md5 gating helps, but polling is still frequent
- board/thread/catalog all depend on repeated network probes and fragment parsing

Why this is costly:
- unnecessary repeated work under normal idle conditions
- DOM replacement remains a regression vector

Recommended change:
- replace current polling with narrow “changed?” endpoints plus fragment endpoints
- keep md5/etag logic server-owned and explicit
- stop using page-shaped fragments for updater state checks

## Parallel or redundant systems

### 6. Announcement and global message are parallel systems
Files:
- `lib/eirinchan/announcement.ex`
- `lib/eirinchan_web/controllers/manage_page_controller.ex`
- `lib/eirinchan_web/board_chrome.ex`

Current state:
- the site effectively uses `global_message`
- there is still a parallel announcement subsystem and admin surface

Why this is costly:
- two concepts for one public message slot
- more UI and code than the current site needs

Recommended change:
- remove the separate announcement subsystem entirely or finish consolidating it into `global_message`

### 7. Watcher exists as both page and options-tab experience
Files:
- `lib/eirinchan_web/controllers/page_controller.ex`
- `lib/eirinchan_web/controllers/page_html/watcher.html.heex`
- `lib/eirinchan_web/controllers/page_html/watcher_fragment.html.heex`
- `priv/static/js/server-thread-watcher.js`

Current state:
- watcher has:
  - a standalone `/watcher` page
  - an Options tab
  - top-bar icon entry point

Why this is costly:
- multiple surfaces for one feature
- more rendering paths to keep visually and behaviorally aligned

Recommended change:
- choose one primary watcher surface
- keep the other only as fallback if there is clear value

### 8. Style selector architecture still carries legacy duality
Files:
- `lib/eirinchan_web/public_shell.ex`
- `priv/static/js/style-select.js`
- `priv/static/js/options/general.js`
- `priv/static/js/main.js`

Current state:
- bottom styles block and Options style selector are now separated, which is good
- but the codebase still contains legacy `style-select.js` alongside server-templated selector flow

Why this is costly:
- theme-selector regressions have repeatedly come from mixed ownership

Recommended change:
- remove dead/legacy selector paths completely once current server-templated path is fully stable

## Likely dead or low-value assets/scripts

### 9. Legacy scripts appear to be present but not part of the active architecture
Examples:
- `priv/static/js/watch.js`
- `priv/static/js/thread-watcher.js`
- `priv/static/js/style-select.js`

Why this is costly:
- they create ambiguity during debugging
- future work can accidentally patch inactive code paths

Recommended change:
- audit active script inclusion from `PublicShell`
- mark unused scripts clearly or remove them

## Security / policy boundaries worth simplifying

### 10. Admin-authored raw HTML remains spread across many surfaces
Files:
- `lib/eirinchan_web/components/layouts/root.html.heex`
- `lib/eirinchan_web/controllers/manage_page_html/announcement.html.heex`
- custom page / FAQ / formatting surfaces

Current state:
- several trusted HTML surfaces still render via `raw(...)`

Why this is costly:
- hard to audit one boundary for trusted HTML
- increases the chance of inconsistent escaping assumptions

Recommended change:
- centralize trusted-admin HTML rendering into one clear boundary/module
- keep user-generated content strictly separated from that path

## Efficiency notes

### 11. The site still pays for repeated JS initialization after DOM swaps
Current state:
- updater and AJAX success paths still have to re-run JS behavior over inserted nodes

Why this is costly:
- bugs tend to appear as “works on first load, breaks after update”

Recommended change:
- continue moving post/thread truth into server fragments
- reduce DOM mutation by hand
- make inserted content structurally identical to first-load content

### 12. Static build and dynamic render still have overlapping but separate display logic
Files:
- `lib/eirinchan/build.ex`
- dynamic templates/components

Why this is costly:
- parity regressions are easy when static output and dynamic output diverge

Recommended change:
- continue collapsing both onto the same component/render helpers

## Suggested execution order

1. Break up `ManagePageController`
2. Finish shrinking `Posts` into thin orchestration
3. Finish moving remaining `PostView` HTML assembly into HEEx components
4. Simplify updater architecture into explicit change-check endpoints
5. Remove or consolidate duplicate watcher/style/announcement paths
6. Audit and remove inactive legacy JS files
