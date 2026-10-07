# Review criteria

Apply these to the inventory established by [the skill](SKILL.md), using the
target project's policies. Record inapplicable criteria rather than inventing
requirements. Read actual implementations and callers, not just declarations.

## Clarity and consistency

Can a reader follow an operation without unnecessary indirection? Check whether
each layer, wrapper, DTO, constructor, interface, and generic abstraction has a
current, distinct purpose. Prefer direct code, concrete types, and stdlib where
they preserve ownership, policy, and testing boundaries. Retain abstractions with
demonstrated value. Local repetition may be clearer than a misleading abstraction.

Compare similar operations: naming, validation, errors, authorization, side effects,
transactions, and response shapes. Recommend one authoritative convention with
evidence, while preserving differences justified by business rules.

## Language semantics and signatures

Use the project's languages and runtimes, not a universal Go policy. Assess
ownership, mutation, defaults/zero values, nullability, cancellation, cleanup,
concurrency/async behavior, exceptions or error propagation and matching, and
numeric/serialization semantics where relevant. Let tools handle formatting;
focus review on meaning.

Check function/method cohesion, receiver choice where applicable, names, exported
documentation, argument order, return/error semantics, cancellation propagation,
and whether actual callers need each input. Examine boolean mode flags, long
positional lists, ambiguous same-typed arguments, duplicated inputs, optional/null
semantics, and invalid combinations. Trace trusted/untrusted input validation to
its owning boundary. Recommend a smaller signature or cohesive input type only
when it removes a demonstrated ambiguity or invalid state; account for callers
and avoid one-use wrappers without a purpose.

## Implemented architecture and correctness

Trace actual entry points, domain behavior, adapters, storage, transaction and
event-delivery boundaries where present. Check imports/call directions, ownership,
conversion layers, shared abstractions, and dependency choices against policies
and ADRs. Challenge forwarding layers, repeated policy, and speculative seams;
retain boundaries that enforce ownership, isolation, atomicity, or necessary tests.

Challenge invariants with invalid inputs, concurrency, retries, partial failures,
and recovery. Where applicable, verify authority comes from authenticated/trusted
context, object and tenant access are enforced, queries are parameterized, storage
privileges are constrained, transactions cover intended effects, and required event
delivery is durable. Multi-tenancy, RLS, outboxes, and particular architecture
patterns are requirements only when the project needs or adopts them.

## Tests

Check observable behavior, meaningful failure conditions, isolation, cleanup, and
repeatability. Would the test detect a broken implementation? Compare integration
scenarios and documented behavior with real effects. Retain agreed TDD/regression
coverage and security/data-integrity checks; fewer tests is not inherently better.
Record which validation actually ran and which was only inspected or proposed.

## API and external contracts

When APIs are in scope, map each operation from its registered entry point and
middleware through decoder, handler, domain operation, effects, response/error
writers, tests, and consumers. Use the project's adopted API standards, versions,
and documented exceptions. Google AIPs, REST conventions, GraphQL schemas, RPC
protocols, and other guides are conditional references, not universal mandates.

- Resource ownership, names/references, fields, and versioning conventions.
- Method semantics and actual effects, including custom actions and idempotency.
- Path/query/body inputs, required/optional fields, omitted versus empty/null,
  unknown fields, immutable/output-only fields, and partial-update semantics.
- Pagination limits, stable ordering, opaque tokens, filtering, collection shapes,
  and access visibility where applicable.
- Status/error envelopes, stable reasons, privacy-preserving failures, retry hints,
  and client expectations.
- Concurrent/repeated requests, preconditions, credential secrecy, authorization,
  and release/backward-compatibility requirements.

Record applicable rules and exceptions per operation; inspect shared helpers and
overrides. A missing standard operation is a finding only when it is required.
Do not demand a particular protocol, infrastructure, or storage entity solely to
fit a guide's example.

## Unnecessary cyclomatic complexity

Inspect branches, nesting, compound predicates, loops, large switches, repeated
error mapping, mode-dependent paths, and mixed responsibilities. Prioritize by
decision paths, business/security importance, and difficulty proving behavior,
not line count. Use an existing complexity tool when useful; record tool/version,
command, and scope. Distinguish measured scores from manual estimates.

Propose behavior-preserving simplifications: redundant-decision removal, equivalent
branch consolidation, guard clauses, or separating parsing from policy at a real
responsibility boundary. Explain which paths or comprehension costs disappear.
Guard clauses may flatten nesting without lowering cyclomatic complexity. Moving
branches into helpers merely to lower a function's score is insufficient; assess
the entire operation and its helpers. Accept necessary complexity with a reason
when a rewrite hides meaning or adds indirection.

Preserve observable validation order, errors/statuses, access control, transaction
boundaries, retries, and delivery guarantees. Name the branch/failure scenarios
needed to prove equivalence. Measure before/after only after authorized fixes are
implemented; a read-only review proposes corrections.
