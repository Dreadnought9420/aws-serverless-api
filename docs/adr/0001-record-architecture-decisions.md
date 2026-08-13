# ADR-0001: Record architecture decisions

**Status:** Accepted
**Date:** 2026-08-13
**Deciders:** Repository owner

## Context

This repository is a portfolio project. Someone reading it — a reviewer, an
interviewer, or the author six months later — cannot tell from Terraform code
alone whether a choice was reasoned or arbitrary. `billing_mode = "PAY_PER_REQUEST"`
looks identical whether it was chosen after a cost analysis or copied from a
blog post.

Small projects usually skip decision records because "there is only one person
here". That is exactly when the reasoning is lost fastest: there is no code
review conversation to go back to.

## Decision

Keep a numbered log of architecture decisions in `docs/adr/`, using the format
described by Michael Nygard, extended with an explicit options table.

A record is written when a decision:

- is expensive or disruptive to reverse (state backend, data model, auth model), or
- looks wrong at first glance and needs its justification attached, or
- was a close call between two defensible options.

Routine choices — variable names, file layout, formatting — do not get a record.

## Options Considered

### Option A: ADR files in the repository

| Dimension | Assessment |
| --- | --- |
| Complexity | Low — plain Markdown, no tooling |
| Cost | Zero |
| Discoverability | High — versioned alongside the code it explains |
| Team familiarity | High — a widely recognised convention |

**Pros:** reviewed through the same pull request as the change; diffable; no
external service to keep alive.
**Cons:** needs discipline; goes stale if decisions are made and not written down.

### Option B: Comments in the Terraform code

| Dimension | Assessment |
| --- | --- |
| Complexity | Lowest |
| Cost | Zero |
| Discoverability | Low — no place to record options that were rejected |
| Team familiarity | High |

**Pros:** impossible to miss when reading the resource.
**Cons:** there is nowhere to put an option that was considered and rejected,
which is most of the value of a decision record.

### Option C: A wiki or external document store

| Dimension | Assessment |
| --- | --- |
| Complexity | Medium — another system to maintain |
| Cost | Zero to low |
| Discoverability | Low — drifts away from the code immediately |
| Team familiarity | High |

**Pros:** richer formatting, easier for non-engineers to read.
**Cons:** not versioned with the code; nothing forces it to be updated in the
same change.

## Trade-off Analysis

Option B is not an alternative so much as a complement — inline comments explain
*what* a resource does, records explain *why the alternative was rejected*. Both
are used here. Option C loses the property that matters most: the decision and
the code change land in the same reviewed commit.

## Consequences

- A reviewer can audit reasoning without reading every resource block.
- Any pull request that changes a load-bearing decision is expected to add or
  supersede a record; that is extra work on every such change.
- Records will need revisiting when AWS changes the underlying trade-offs —
  several of the decisions here are cost-driven, and AWS pricing moves.

## Action Items

1. [x] Create `docs/adr/` with this record as 0001
2. [x] Backfill records for the decisions already made in the initial build
3. [ ] Add an ADR checkbox to the pull request template if the log starts going stale
