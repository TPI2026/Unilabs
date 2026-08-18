# Validation Report

## Pre-application rollback validation

The two migrations and all regression tests were executed in one database transaction and then rolled back.

Result:

```json
{
  "rollback_validation": "passed",
  "migration_statements": 127,
  "test_statements": 10,
  "central_story": "passed",
  "unhappy_paths": "passed",
  "decline_and_expiry": "passed",
  "consistency": "passed"
}
```

## Post-application tests

- Central Patient A / Patient B story: passed
- Unhappy paths and transaction protection: passed
- Waitlist decline and expiry forwarding: passed
- Data consistency checks: passed

## Central story coverage

1. Patient A books the fifth Utrecht 10:00 appointment
2. Idempotent replay returns the same appointment
3. Patient B receives `available = false` and 11:00 as the next available time
4. Patient B books 11:00
5. Patient B joins the waitlist for 10:00 while retaining 11:00
6. Patient A moves to 14:00
7. The released 10:00 capacity is reserved for Patient B
8. Structured chat and voice notifications are created
9. Patient B accepts with the valid offer token
10. Patient B ends with exactly one active appointment at 10:00
11. The waitlist entry is completed and notifications are closed

## Unhappy-path coverage

- Lunch slot booking rejected
- Full-slot booking rejected
- Duplicate patient/slot booking does not create a second appointment
- Reuse of a `request_id` with a different payload is rejected
- Failed rescheduling preserves the original appointment
- Joining a waitlist for an available slot is rejected
- Declining a nonexistent offer is rejected

## Waitlist lifecycle coverage

- Decline preserves the current confirmed appointment
- Expired offers are marked `expired`
- Expired notifications are closed
- The next waiting patient receives a new offer
- The forwarded offer reserves capacity

## Consistency coverage

- No slot exceeds room-derived capacity
- No duplicate confirmed room/slot combinations
- No duplicate confirmed patient/slot combinations
- Every offered waitlist entry has token and expiry data
- 12:00 remains non-bookable
- Seven-day reset produces exactly 189 slots
- Five featured patients have ten verified chat/voice identities

## Security audit

Verified after application:

- `anon` schema usage: false
- `authenticated` schema usage: false
- `anon` write-RPC execution: false
- `authenticated` write-RPC execution: false
- `service_role` schema usage: true
- `service_role` write-RPC execution: true
- `service_role` reset-RPC execution: true

The Supabase Security Advisor reports only informational `RLS enabled, no policy` notices. This is intentional because direct client access is denied and the database is used exclusively through the server-side integration layer.

## Live baseline after final reset

- Scenario date: `2026-08-19`
- Generated days: `7`
- Offer hold: `5 minutes`
- Appointment slots: `189`
- Confirmed baseline appointments: `11`
- Active baseline waitlist entries: `1`
- Verified featured-patient channel identities: `10`
- Residual staging rows: `0`

## Cron verification

The `unilabs-expire-waitlist-offers` job is active with schedule `* * * * *`. PostgreSQL logs show repeated successful starts and completions for `select public.expire_waitlist_offers();`.

## Default-privilege hardening

Default table, sequence, and function privileges are restricted for the application migration owner `postgres`. Current schema ACLs additionally remove `USAGE` and `CREATE` from `PUBLIC`, `anon`, and `authenticated`, and all current public-schema functions have explicit execution revocations for those roles.
