# ADR 0001: Use an API-first modular monolith

- **Status:** Accepted as the initial design direction
- **Date:** 2026-11-10

## Context

Eventor spans bookings, guest management, invitations, spatial allocation, check-in and event operations. These domains are related and require consistent transactions, auditability and coordinated workflow changes. The first deployment is self-hosted and the project should remain operable without a large distributed-systems footprint.

## Decision

Build an API-first modular monolith with explicit domain/application boundaries. Use Vue 3 + TypeScript + Vite for frontends, Fastify + TypeScript for the API/workers, and PostgreSQL for authoritative data. Independently deployable UI entry points and a separate C++ optimization process are allowed where justified, but domain modules are not microservices.

## Alternatives considered

- Microservices from the outset: rejected due to operational complexity and unnecessary distributed consistency boundaries.
- Single tightly coupled application: rejected because explicit module boundaries and shared contracts are needed for long-term maintainability.

## Consequences

- Cross-domain workflows can use database transactions and shared audit conventions.
- Modules must maintain clear interfaces and avoid uncontrolled cross-module table access.
- Extracting a service later remains possible if measured operational or scaling needs justify it.
