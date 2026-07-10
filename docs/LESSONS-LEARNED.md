# Lessons Learned — PlumbingFixed

Durable, **repo-specific** lessons about judgment and process — the root causes behind time we
lost, not restatements of how the code works. Append short entries, each leading with a bold
takeaway.

---

## When a tool fights back, stop trial-and-erroring and go read the docs

Getting non-interactive publishing working cost far more time than it should have, because we
tried to force it by tweaking flags and re-running rather than stepping back to read the
tool's docs and reason about the mechanism first. Learning an unfamiliar tool, framework, or
API by trial and error feels like progress but rarely is: each failed attempt teaches little
and the fixes don't generalize. The real skill is noticing *early* that you're in that loop
and deliberately climbing out — consult the authoritative source, form a hypothesis, then act
deterministically instead of poking until something turns green. Same instinct as the
[Golden rule](../CLAUDE.md#-golden-rule-do-not-trust-a-lua-global-by-its-name): find the
authoritative source before you change behavior.

---

## To find where refactored vanilla code moved, search by its translation keys

When an override target disappears, don't hunt by the old function name — it's gone. Grep the
vanilla tree for the **translation keys** the feature renders (`getText("Fluid_Empty")`,
`getText("Fluid_Transfer_Fluids")`, `getText("ContextMenu_Drink")`, …). Those strings survive
refactors even when the function name, file, and even the *language* (Lua → Java) change. That's
how we pinned the B42.19 fixture menu to `ISFluidContainerMenu` and then to the native
`ISWorldObjectContextMenuLogic` after the old `do*Menu` builders were deleted. Pair it with a
`.decompiled/` read to confirm the new seam and its authority.
