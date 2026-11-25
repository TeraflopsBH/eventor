# ADR 0016 — Staff publication of event RSVP settings

- Status: accepted.
- Date: 2026-11-25.
- Related: #104, ADR 0004/0005, RSVP and invitation design v0.3.

## Decision

Expose read/publication commands for the existing event RSVP policy tables to staff with `event.manage` for the selected event. Staff explicitly choose a nonempty subset of accepted/declined/tentative, an optional absolute response deadline entered in the effective event schedule's IANA time zone, and whether guests can change their answer. The first form uses the existing schema defaults; publishing requires explicit confirmation. No modules, guest records, links, messages or reminder jobs are created by this command.

Each publication inserts an immutable published revision. A new event receives a stable policy identity and an internal generated reference; subsequent publications reuse the current published policy's identity. A retired current policy is rejected rather than silently reactivated. Revision numbers advance above all existing event policy revisions, including legacy multiple-policy data, so existing invitation and uninvited staff-response selectors choose the newly published revision unambiguously. Existing revisions and issued invitation/response references remain untouched. Existing late-change and reminder settings are preserved, rather than introducing new reminder/override behavior through this form.

The command locks the event, checks an open lifecycle (not completed/cancelled/archived), the expected published revision ID (null for first publication), and the expected effective time-zone name. A stale policy or changed time zone requires reloading. Absolute deadlines are not silently shifted or constrained by an invented venue policy. Permission is checked both on command execution and idempotent replay. An audit records the actual membership, event and new/previous revision IDs. Runtime direct policy-table writes are revoked; publication remains a narrow SECURITY DEFINER boundary with tenant context and pinned search path.

The staff UI includes permission errors, stale-edit recovery through refresh, fieldset/checkbox labels and confirmation. Closed events remain readable without publication controls. Reuse the event scheduler's local-date conversion and reject nonexistent local times. Preserve an unchanged deadline's exact instant when editing other settings, including DST ambiguity and sub-minute precision. Settings publication is separate from invitation reissuance and does not reinterpret existing guest answers.

## Limits

This slice does not add reminder scheduling, policy retirement, invitation template authoring, bulk reissuance, attendee admission, or a full capability-management console. Those require their own workflows. Existing guest self-service and explicit staff deadline-override enforcement remain authoritative.
