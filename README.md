questionpro-infra — Fleet Knowledge & Control Plane

A version-controlled, AI-readable source of truth for the Mumbai (mu) OCI fleet.
Separate from QuestionProX (which is the *dev/product* knowledge base) — this is *operational* infra.

Philosophy (carried from QuestionProX):
- Every file is self-contained — no "see other doc".
- Document WHY, not just WHAT. Decision logs always include "When to reconsider".
- Generated files are header-marked GENERATED and NEVER hand-edited.
- Trust level is declared per directory (below).

TRUST LEVEL per directory:
  access/      — intent/measured by hand. What I can touch, as whom. (Phase 0)
  topology/    — MEANING. Hand-authored, MEASURED dependency graph + why. Items I haven't
                 verified on a real box are tagged UNVERIFIED. (Phase 1)
  inventory/   — FACTS. Machine-generated from OCI/boxes. Do not hand-edit. (Phase 1)
  fleet/       — per-host WHY-docs, self-contained. (Phase 1)
  risks.md     — the ranked risk list. Each item marked verified | UNVERIFIED + evidence. (Phase 1)
  observability/ — Phase 2.  iac/ — Phase 3.  differentiators/ — Phase 4.
  decisions/   — why X over Y, with "When to reconsider".

THE THROUGH-LINE:
  Move the fleet's knowledge out of people's heads and ~/.bash_history into
  version-controlled, queryable, testable artifacts that scream when reality drifts —
  measured-not-assumed, prod-last, WITH the infra owner, every step.

Start here: read BATTLE-PLAN.md end-to-end once. Then work access/ (Phase 0). Build nothing else yet.

Current phase: PHASE 0 — Access + Discovery (zero authority, change nothing).
