# Unilabs AI Appointment Demo — Architecture

## Architectural principle

The demo uses one authoritative appointment backend for all channels. Chat and Voice may differ in conversation handling, but they must call the same appointment logic and rely on the same Supabase state.

## Responsibilities

### Talkdesk

Talkdesk is responsible for:

- patient communication
- intent recognition
- conversation continuity
- collecting the minimum information required for an action
- invoking the correct backend capability
- communicating a successful result only after the backend confirms success

Talkdesk is not responsible for storing or inventing appointment availability.

### Supabase

Supabase is the central source of truth for:

- locations
- rooms
- patients
- appointment slots and capacity
- appointments
- waitlist entries and offers
- notifications
- chronological events
- idempotency state for write operations

Critical multi-step appointment changes are handled transactionally. The database prevents overbooking, duplicate patient bookings in the same slot, and inconsistent rescheduling states.

### Vercel

Vercel hosts:

- the patient-facing demo website
- the Agent Console
- server-side API endpoints
- the integration layer between Talkdesk and Supabase

Privileged Supabase credentials must never be exposed in browser/client-side code.

## Repository mapping

```text
website/     Web UI, Agent Console, and server-side integration/API code
supabase/    Database migrations, functions/RPCs, reset logic, and regression tests
IVR/         Talkdesk Studio Voice / IVR configuration material
.github/     Deployment automation, including GitHub Pages preview
```

## Transaction rules

- availability must be checked against authoritative backend data
- booking is confirmed only after the booking operation succeeds
- rescheduling is confirmed only after the rescheduling operation succeeds
- cancellation is confirmed only after the cancellation operation succeeds
- failed rescheduling must preserve the original active appointment
- maximum active capacity is five appointments per location and bookable slot
- 12:00 is never bookable
- room assignment is automatic
- write actions use idempotency protection where applicable

## Waitlist lifecycle

```text
appointment moved or cancelled
  -> capacity released
  -> matching active waitlist entry detected
  -> reserved waitlist offer created
  -> patient notified
  -> explicit accept / decline / expiry
  -> accepted offer performs atomic move
  -> declined or expired offer can be forwarded
```

An offer must never replace a patient's existing confirmed appointment before explicit acceptance.

## Demo reset and reproducibility

The Supabase reset logic restores a deterministic demo baseline. The central Patient A / Patient B story is the primary end-to-end regression scenario and must remain reproducible after implementation changes.
