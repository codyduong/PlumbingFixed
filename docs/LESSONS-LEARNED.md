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
