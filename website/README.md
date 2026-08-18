# Unilabs AI Appointment Demo

Static patient-facing demo pages plus server-side Vercel Functions for the Unilabs / Talkdesk appointment showcase.

## Pages
- Dutch patient-facing Home page
- TP Infinity CRM Agent Console simulation
- Patient registry and patient details
- Scheduling simulations

## Appointment API
The Vercel project root is `website`. These server-side POST endpoints proxy only to the tested Supabase RPC functions:

- `/api/check-availability` -> `check_availability`
- `/api/book-appointment` -> `book_appointment`
- `/api/find-appointment` -> `find_appointment`
- `/api/reschedule-appointment` -> `reschedule_appointment`
- `/api/cancel-appointment` -> `cancel_appointment`
- `/api/join-waitlist` -> `join_waitlist`
- `/api/decline-waitlist-offer` -> `decline_waitlist_offer`

Every endpoint requires the `x-api-key` header. Do not call these endpoints directly from browser code.

All successful and failed responses include `request_id`, the same value is returned in the `x-request-id` response header, and responses use `Cache-Control: private, no-store`.

## Required Vercel environment variables

- `SUPABASE_URL` - `https://mshxmttxwfkvexchwjkr.supabase.co`
- `SUPABASE_SECRET_KEY` - recommended `sb_secret_...` Supabase server key; never expose it client-side
- `UNILABS_API_KEY` - shared secret sent by the Talkdesk Custom Connection as `x-api-key`

The API helper also accepts the legacy `SUPABASE_SERVICE_ROLE_KEY` for backward compatibility, but new deployments should use `SUPABASE_SECRET_KEY`.

Use `.env.example` only as a variable-name template. Never commit real secret values.

## Request contracts

### CheckAvailability
```json
{
  "location_id": "LOC-UTR",
  "slot_date": "2026-08-19",
  "start_time": "10:00",
  "patient_id": "PAT-1001"
}
```
`patient_id` is optional. This is a read action and does not require an idempotency key.

### BookAppointment
```json
{
  "request_id": "interaction-123-book-1",
  "patient_id": "PAT-1001",
  "location_id": "LOC-UTR",
  "slot_date": "2026-08-19",
  "start_time": "10:00"
}
```

### FindAppointment
```json
{
  "patient_id": "PAT-1004",
  "booking_reference": "UNI-100010"
}
```
`booking_reference` is optional. This is a read action and does not require an idempotency key.

### RescheduleAppointment
Regular rescheduling:
```json
{
  "request_id": "interaction-123-reschedule-1",
  "appointment_id": "APT-LIVE-200001",
  "new_location_id": "LOC-UTR",
  "new_slot_date": "2026-08-19",
  "new_start_time": "14:00"
}
```

Waitlist-offer acceptance additionally requires both `waitlist_entry_id` and `offer_token`:
```json
{
  "request_id": "interaction-123-accept-offer-1",
  "appointment_id": "APT-LIVE-200002",
  "new_location_id": "LOC-UTR",
  "new_slot_date": "2026-08-19",
  "new_start_time": "10:00",
  "waitlist_entry_id": "WL-LIVE-200001",
  "offer_token": "<offer token returned by the backend>"
}
```

### CancelAppointment
```json
{
  "request_id": "interaction-123-cancel-1",
  "appointment_id": "APT-C-1004"
}
```

### JoinWaitlist
```json
{
  "request_id": "interaction-123-waitlist-1",
  "patient_id": "PAT-1002",
  "location_id": "LOC-UTR",
  "slot_date": "2026-08-19",
  "start_time": "10:00",
  "current_appointment_id": "APT-LIVE-200002"
}
```
`current_appointment_id` is optional.

### DeclineWaitlistOffer
```json
{
  "request_id": "interaction-123-decline-offer-1",
  "patient_id": "PAT-1002",
  "waitlist_entry_id": "WL-LIVE-200001",
  "notification_id": "NOT-LIVE-200001"
}
```

## Idempotency
Every write action requires a stable `request_id`. Repeating the same write with the same `request_id` and payload returns the original result. Reusing a `request_id` for a different action or payload returns `idempotency_conflict`.

## Response envelope
Successful calls return:

```json
{
  "ok": true,
  "action": "BookAppointment",
  "request_id": "interaction-123-book-1",
  "data": {}
}
```

Failures return only stable, patient-safe API errors. Raw Supabase `details` and `hint` fields are not exposed:

```json
{
  "ok": false,
  "action": "BookAppointment",
  "request_id": "interaction-123-book-1",
  "error": {
    "code": "slot_fully_booked",
    "message": "The requested slot is fully booked",
    "retryable": false
  }
}
```

The Supabase RPC call is aborted after eight seconds so the integration can fail deterministically before the Talkdesk action timeout.

## Vercel
Deploy the `website` directory as the Vercel project root. The Root Directory value must be exactly `website`, without leading or trailing spaces. No frontend build step is required. Functions are configured to run in `fra1`. Production deployments are triggered from `main` through the connected Vercel project. All patient data is fictional demo data.
