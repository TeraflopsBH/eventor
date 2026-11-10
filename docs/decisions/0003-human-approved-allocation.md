# ADR 0003: Solver output is a proposal, never an automatic commit

- **Status:** Accepted
- **Date:** 2026-11-10

## Context

Seating and spatial allocation can affect safety, accessibility, protocol and guest experience. Constraints may conflict or source venue plans may be incomplete. An optimizer can produce useful proposals but cannot be trusted to silently alter operational assignments.

## Decision

The allocation engine returns a proposal with feasibility status, diagnostics and objective information. The application presents a preview/diff and requires an authorized human to explicitly commit the result. Locked assignments and scoped reruns are supported. Infeasible and feasible/optimal outcomes are distinguished.

## Consequences

- Solver output is not authoritative until validated and committed through the API.
- The UI must explain conflicts and proposed changes.
- Allocation commits are auditable and concurrency-checked against the state used to generate the proposal.
