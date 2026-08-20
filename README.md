# Unilabs AI Appointment Demo

Demo environment showing how a Talkdesk AI Agent can execute administrative appointment processes for Unilabs using controlled fictional data.

## Scope

The demo covers:

- checking appointment availability
- booking appointments
- offering alternatives when a requested slot is full
- joining and managing a waitlist
- finding existing appointments
- rescheduling appointments
- cancelling appointments
- matching released capacity to active waitlist requests
- exposing relevant actions chronologically in the Agent Console

The scope is limited to administrative appointment processes. No real patient data, diagnosis, result interpretation, treatment recommendation, or other medical decision-making is part of the demo.

## Use cases

The same administrative appointment logic must work for Voice and Chat. Talkdesk manages the conversation and invokes backend actions; Supabase remains the authoritative source for appointment state and availability.

### UC1 - Check appointment availability

A patient asks whether an appointment is available for a specific location, date, and time.

The AI Agent must:

1. collect any missing location, date, or time
2. call `CheckAvailability`
3. use only the backend result
4. tell the patient whether the requested slot is available
5. if unavailable, offer only the concrete next available slot returned by the backend

The Agent must never invent availability or calculate capacity itself.

### UC2 - Book an appointment

A patient wants to book an available appointment.

The AI Agent must:

1. collect the required patient and appointment information
2. verify availability through `CheckAvailability`
3. obtain explicit patient confirmation for the selected slot
4. call `BookAppointment`
5. confirm the booking only after backend success
6. communicate the confirmed location, date, time, and booking reference returned by the backend

Patients do not choose rooms. Room assignment is backend logic.

### UC3 - Requested slot is fully booked

A patient requests a slot that has reached capacity.

The AI Agent must:

1. call `CheckAvailability`
2. identify that the requested slot is unavailable
3. offer only the next concrete available slot returned by the backend
4. wait for the patient to accept or reject the alternative
5. continue the pending booking or rescheduling workflow if the patient accepts

The Agent must not invent an alternative time.

### UC4 - Find an existing appointment

A patient wants information about an existing appointment, or an appointment must be retrieved before another operation.

The AI Agent must:

1. call `FindAppointment`
2. use the authoritative appointment returned by the backend
3. communicate patient-facing information such as location, date, time, and booking reference
4. retain internal appointment identifiers for subsequent actions without reading them to the patient

The Agent must not infer appointment state from conversation history when the backend can provide it.

### UC5 - Reschedule an appointment

A patient wants to move an existing appointment.

The AI Agent must:

1. retrieve the existing appointment if required
2. collect the requested new location, date, and time
3. call `CheckAvailability` for the new slot
4. if unavailable, offer only the backend-provided alternative
5. obtain explicit confirmation for the move
6. call `RescheduleAppointment`
7. confirm the new appointment only after backend success

A failed reschedule must leave the original confirmed appointment active.

### UC6 - Cancel an appointment

A patient wants to cancel an existing appointment.

The AI Agent must:

1. retrieve or use the authoritative appointment
2. make clear which appointment is being cancelled
3. obtain explicit cancellation confirmation
4. call `CancelAppointment`
5. confirm cancellation only after backend success

The Agent must never claim that an appointment was cancelled when the backend operation failed.

### UC7 - Join a waitlist while keeping an existing appointment

A patient's preferred slot is fully booked, but the patient has accepted or already has another confirmed appointment.

The AI Agent must:

1. confirm through `CheckAvailability` that the preferred slot is unavailable
2. retain the existing confirmed appointment
3. explain that joining the waitlist does not cancel or replace that appointment
4. obtain the patient's intention to join
5. call `JoinWaitlist`
6. confirm the waitlist entry only after backend success

The current appointment must remain unchanged.

### UC8 - Accept a waitlist offer

A place becomes available for a patient's preferred slot and the backend creates a waitlist offer.

The AI Agent must:

1. present the offered location, date, and time
2. make clear that the current appointment remains unchanged until the offer is accepted
3. obtain explicit acceptance
4. use the existing appointment together with the authoritative `waitlist_entry_id` and `offer_token`
5. call `RescheduleAppointment`
6. confirm the move only after backend success

The Agent must not create a second appointment through `BookAppointment` when accepting a waitlist offer.

### UC9 - Decline a waitlist offer

A patient does not want the offered preferred slot.

The AI Agent must:

1. identify the active waitlist offer
2. interpret an explicit decline in the context of that offer
3. call `DeclineWaitlistOffer`
4. confirm the decline only after backend success
5. preserve the patient's existing confirmed appointment

### UC10 - Context-dependent confirmations

Short replies must continue the immediately preceding workflow rather than being interpreted as new generic intents.

Examples:

- after an alternative-slot proposal, `yes`, `that works`, or `take it` selects that exact alternative and continues the pending booking or rescheduling workflow
- after a cancellation confirmation, `yes` or `cancel it` authorizes cancellation of the pending appointment
- after a waitlist invitation, `yes` authorizes joining the pending waitlist
- after a waitlist offer, `yes`, `take it`, or `move me` accepts the offer; `no` or `keep my current appointment` declines it

### UC11 - Backend failure and safe recovery

The Agent must handle conditions such as:

- slot fully booked
- slot not bookable
- patient not found
- appointment not found
- invalid or expired waitlist offer
- request already being processed
- temporary backend failure
- timeout

The Agent must never claim success after a failed action. Existing confirmed appointments must be preserved unless the backend confirms a change. Technical implementation details must not be exposed to the patient.

### UC12 - Human escalation

The patient must be transferable to human support when:

- the patient explicitly asks for a human
- the request is outside administrative appointment management
- required information cannot be obtained
- repeated backend failure prevents completion of an important administrative operation

The AI Agent must not provide clinical advice before escalation.

## Architecture

- **Talkdesk** — patient communication, intent recognition, orchestration, and invocation of appointment actions
- **Supabase** — source of truth for locations, rooms, patients, appointments, availability, waitlists, notifications, and events
- **Vercel** — patient website, Agent Console, server-side APIs, and integration layer between Talkdesk and Supabase

Critical booking logic is executed server-side. Talkdesk never invents appointment availability; it must use authoritative backend results before confirming any booking, rescheduling, or cancellation.

## Repository structure

```text
.github/        GitHub Actions workflows, including the GitHub Pages preview deployment
IVR/            Talkdesk Studio Voice / IVR configuration material
supabase/       Versioned database migrations, reset logic, and regression tests
website/        Demo website, Agent Console, and server-side integration/API implementation
docs/           Project brief, architecture, and UI documentation
```

The production demo website is deployed through Vercel. GitHub Pages provides a static repository preview of `website/`.

## Central demo story

The core Patient A / Patient B scenario must remain reproducible:

1. Patient A requests Utrecht at 10:00 and `CheckAvailability` confirms one remaining place
2. Patient A confirms and `BookAppointment` books the final available 10:00 appointment
3. Patient B requests Utrecht at 10:00; `CheckAvailability` reports the slot full and returns 11:00 as the next concrete available slot
4. Patient B accepts 11:00 and `BookAppointment` creates the appointment
5. Patient B joins the 10:00 waitlist through `JoinWaitlist` while retaining the confirmed 11:00 appointment
6. Patient A reschedules from 10:00 to 14:00 through `RescheduleAppointment`
7. The released 10:00 capacity triggers a waitlist match and offer for Patient B
8. If Patient B accepts, `RescheduleAppointment` atomically moves the existing appointment from 11:00 to 10:00 using the waitlist offer data
9. If Patient B declines, `DeclineWaitlistOffer` records the decline and the 11:00 appointment remains unchanged
10. The complete process is visible chronologically in the Agent Console

## Core business rules

- maximum five active appointments per location and bookable time slot
- 12:00 is blocked for lunch and must never be bookable
- patients do not select rooms; the system assigns an available room
- a write is only confirmed after the corresponding backend operation succeeds
- failed rescheduling must leave the original appointment active
- a patient may retain a confirmed appointment while waiting for a preferred slot
- a waitlist offer never replaces an existing appointment before explicit acceptance
- accepting a waitlist offer moves the existing appointment; it does not create a second appointment
- relevant state changes are recorded as chronological events
- Voice and Chat use the same appointment business logic

## Current repository state

The repository contains the implemented demo website and integration layer, the current Supabase schema/migrations and regression tests, Talkdesk IVR configuration material, and GitHub Pages/Vercel deployment configuration. Ongoing Talkdesk AI Agent configuration must continue to use the same backend appointment logic and authoritative Supabase data as the web channel.

All patient and appointment data used for the demo is fictional.
