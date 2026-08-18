# Validation Report

## Simplification validation

The cleanup migration `20260818091211_simplify_platform` was first executed together with the critical regression paths inside one database transaction and then rolled back.

Result:

```json
{
  "rollback_validation": "passed",
  "central_story": "passed",
  "channel_neutral_notification": "passed",
  "idempotency": "passed",
  "cancel_waitlist_cleanup": "passed",
  "expiry_forwarding": "passed",
  "privileges": "passed"
}
```

The same critical paths were rerun after applying the migration to the connected Supabase project.

## Simplification performed

- Removed `patient_channel_identities`
- Replaced parallel Chat/Voice notifications with one channel-neutral waitlist notification
- Removed speculative notification delivery fields and message generation from Supabase
- Removed unused `status` and `metadata` fields from `demo_scenarios`
- Removed the unused durable `status` field from `action_requests`
- Kept `request_id` idempotency, offer reservation, expiry, decline, and transactional appointment logic
- Made `reset_demo_scenario` deterministic by replacing all scenario rows with one `default` scenario
- Added cleanup of active waitlists when their dependent appointment is cancelled
- Added the `waitlist_cancelled` event

## Central Patient A / Patient B story

Validated after the migration:

1. Patient A books the fifth Utrecht 10:00 appointment
2. Replaying the same `request_id` returns the same appointment
3. Patient B receives the requested 10:00 slot as unavailable
4. Patient B books 11:00
5. Patient B joins the 10:00 waitlist while retaining 11:00
6. Patient A moves from 10:00 to 14:00
7. Patient B receives a reserved 10:00 offer
8. Exactly one channel-neutral notification is created
9. Patient B accepts with the valid offer token
10. Patient B ends with exactly one confirmed appointment at 10:00
11. The waitlist is completed and the notification is marked `responded`

Result: `central_story_passed`.

## Cancellation and dependent waitlist

A previously uncovered lifecycle case is now validated:

1. Patient B holds an 11:00 appointment and an active waitlist for 10:00
2. Patient B receives a 10:00 waitlist offer
3. Patient B cancels the 11:00 appointment
4. The dependent waitlist entry becomes `cancelled`
5. Its pending notification becomes `cancelled`
6. No active waitlist remains linked to the cancelled appointment
7. The released waitlist reservation is offered to the next waiting patient

Result: `cancel_waitlist_cleanup_passed`.

## Expiry forwarding

Validated after the migration:

- An expired offer becomes `expired`
- Its notification becomes `expired`
- The slot is forwarded to the next waiting patient
- The next offer receives a new reservation and one channel-neutral notification

Result: `expiry_forwarding_passed`.

## Unhappy paths

Validated after the migration:

- 12:00 lunch booking is rejected
- A full slot booking is rejected
- Failed rescheduling preserves the original confirmed appointment
- Joining a waitlist for an available slot is rejected

All checks passed.

## Data consistency

The final live consistency query returned zero issues for:

- over-capacity slots
- confirmed appointments on non-bookable slots
- offered waitlists without notifications
- duplicate confirmed room/slot combinations
- offered waitlists without token or expiry
- duplicate confirmed patient/slot combinations
- active waitlists linked to cancelled appointments

## Current schema simplification

`notifications` now contains only:

- `notification_id`
- `patient_id`
- `waitlist_entry_id`
- `status`
- `created_at`
- `payload`
- `responded_at`

`action_requests` now contains only:

- `request_id`
- `action_name`
- `payload_hash`
- `response`
- `created_at`
- `completed_at`

`demo_scenarios` now contains only:

- `scenario_key`
- `scenario_date`
- `generated_days`
- `offer_hold_minutes`
- `reset_at`

`patient_channel_identities` no longer exists.

## Security audit

Verified after application:

- `anon` schema usage: false
- `authenticated` schema usage: false
- `service_role` schema usage: true
- `anon` booking RPC execution: false
- `service_role` booking RPC execution: true
- `postgres` default table, sequence, and function privileges contain only `postgres` and `service_role`

The Supabase Security Advisor reports only informational `RLS enabled, no policy` notices. This is intentional because direct client access is denied and the database is used through the server-side integration layer.

The Supabase-managed `supabase_admin` default privileges cannot be modified by the project database owner; attempting to do so returns `permission denied to change default privileges`. No privilege-escalation workaround is used.

## Automated expiry

The `unilabs-expire-waitlist-offers` cron job remains active:

```text
* * * * *
```

It calls `select public.expire_waitlist_offers();` once per minute.

## Final baseline

After all tests, the project was reset again to a clean baseline:

- Scenario date: `2026-08-19`
- Generated days: `7`
- Offer hold: `5 minutes`
- Appointment slots: `189`
- Confirmed baseline appointments: `11`
- Active baseline waitlist entries: `1`

All test mutations were rolled back before the final reset.
