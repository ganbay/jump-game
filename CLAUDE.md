# Token-efficiency rules for this project

This project has the `godot-ai` MCP server connected (live editor + running-game
introspection, screenshots, input simulation). It is powerful but expensive:
screenshots burn image tokens, and tree-walking ops like `get_ui_elements`
dump huge nested JSON. Default to reading source instead.

## 1. Read the code first, always

Almost every bug in this repo (layout, logic, config, balance) is fully
diagnosable from `.gd` files plus reasoning about Godot semantics. Before
touching any `mcp__godot-ai__*` tool:

- Read the relevant script(s) end to end.
- Check `git diff` / `git log` for what recently changed in that area.
- Form a concrete hypothesis for the root cause.

Only reach for the live editor/game when the question genuinely cannot be
answered from source — e.g. an actual runtime property value after dynamic
node construction, whether a signal fired, whether an autoload initialized
correctly. Non-obvious engine behavior (like `Control.set_anchors_preset`
preserving offsets instead of stretching a freshly-created 0×0 control) is
a legitimate reason to verify at runtime — but verify with the *cheapest*
call that proves the hypothesis (see §3), not by re-exploring blind.

## 2. Don't self-verify gameplay feel — ask the user to test

For anything that requires actually *playing* — does this feel right, does
the boss fight flow work, does the shop appear at the right time, does a
skill behave as intended in a real run — don't drive it yourself with
`project_run` + `input_sequence`/`input_action` + repeated screenshots. That
loop is slow, expensive, and the user can just play it in seconds.

Instead: tell the user exactly what to do and what to look for, e.g.:

> "Can you clear stage 1 and check whether the shop cards are centered on
> screen after the boss banner?"

> "Play until you get a Critical Rate item from the shop, then land a hit —
> does the crit multiplier feel right, or too weak?"

Be specific: which scene/stage, which action, which screen, what a
pass/fail looks like. Let them paste back a screenshot or describe what
they saw — that's one image (or zero) instead of an automated multi-step
exploration.

## 3. When Godot AI MCP is actually needed, use the narrowest tool

Ranked cheapest → most expensive; use the cheapest one that answers the
question:

1. **`get_node_info(path, include_properties=True)` on one specific node** —
   targeted property dump (anchors, offsets, size, etc.). This is what
   actually found the anchor/offset bug — one call, one node.
2. **`get_scene_tree` / `get_ui_elements` with a narrow `root_path` and small
   `depth`** — only when you need shape/structure, not every node's every
   field. Never call these unscoped on a screen with many nodes (a 5-card
   shop screen alone is 50+ nodes) — it dumps rect/global_rect/text/etc for
   every one of them.
3. **`editor_screenshot`** — last resort, and only for genuinely *visual*
   questions (sprite alignment, color, particle look) that numeric
   properties can't answer. If a numeric property already proves the bug
   (e.g. `size: {0,0}`), don't also take a screenshot to "see" it — trust
   the numbers. Only screenshot once, at the end, to confirm a fix looks
   right — not before-and-after pairs when the "before" was already proven
   by data.
4. **`project_run` / input simulation loops** — avoid entirely per §2 unless
   the user explicitly asks you to automate a specific repeatable check
   (e.g. a regression test). Stop the run (`project_manage(op="stop")`)
   as soon as you have what you need — don't leave it running while you
   think or edit files.

Before running any of these, say in one sentence what you're checking and
why source-reading wasn't enough — the user asked to be told when this is
needed, not just have it happen silently.

## 4. Other efficiency habits

- Batch independent reads (multiple files, or a tool call + a `git diff`)
  into one message instead of sequential round trips.
- Don't re-read a file immediately after `Edit`/`Write` — the tool already
  confirms the change; trust it.
- Don't fork/spawn agents for something you can answer directly from files
  already in context.
