# Unilabs AI Appointment Demo

Static patient-facing demo pages plus server-side Vercel Functions for the Unilabs / Talkdesk appointment showcase.

## Pages
- Dutch patient-facing Home page
- TP Infinity CRM Agent Console simulation
- Patient registry and patient details
- Scheduling simulations

## Appointment API
The Vercel project root is `website`. The following server-side POST endpoints proxy only to the tested Supabase RPC functions:

- `/api/check-availability` -> `check_availability`
- `/api/book-appointment` -> `book_appointment`
- `/api/find-appointment` -> `find_appointment`
- `/api/reschedule-appointment` -> `reschedule_appointment`
- `/api/cancel-appointment` -> `cancel_appointment`
- `/api/join-waitlist` -> `join_waitlist`

Every endpoint requires the `x-api-key` header. Do not call these endpoints directly from browser code.

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
  "slot_date": "2026-08-18",
  "start_time": "10:00",
  "patient_id": "PAT-1001"
}
```
`patient_id` is optional.

### BookAppointment
```json
{
  "patient_id": "PAT-1001",
  "location_id": "LOC-UTR",
  "slot_date": "2026-08-18",
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
`booking_reference` is optional.

### RescheduleAppointment
```json
{
  "appointment_id": "APT-LIVE-200001",
  "new_location_id": "LOC-UTR",
  "new_slot_date": "2026-08-18",
  "new_start_time": "14:00",
  "waitlist_entry_id": null
}
```
`waitlist_entry_id` is optional and is used when accepting a waitlist offer.

### CancelAppointment
```json
{
  "appointment_id": "APT-C-1004"
}
```

### JoinWaitlist
```json
{
  "patient_id": "PAT-1002",
  "location_id": "LOC-UTR",
  "slot_date": "2026-08-18",
  "start_time": "10:00",
  "current_appointment_id": "APT-LIVE-200002"
}
```
`current_appointment_id` is optional.

## Response envelope
Successful calls return:

```json
{
  "ok": true,
  "action": "CheckAvailability",
  "data": {}
}
```

Failures return:

```json
{
  "ok": false,
  "action": "CheckAvailability",
  "error": {
    "code": "...",
    "message": "...",
    "details": null,
    "hint": null
  }
}
```

## Vercel
Deploy the `website` directory as the Vercel project root. The Root Directory value must be exactly `website`, without leading or trailing spaces. No frontend build step is required. Functions are configured to run in `fra1`. Production deployments are triggered from `main` through the connected Vercel project. All patient data is fictional demo data.
