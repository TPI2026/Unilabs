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

1. Patient A books the final available 10:00 appointment
2. Patient B requests 10:00, receives 11:00 instead, and joins the 10:00 waitlist
3. Patient A reschedules from 10:00 to 14:00
4. The released 10:00 capacity triggers a waitlist match
5. Patient B is notified and explicitly accepts the offer
6. Patient B is atomically moved from 11:00 to 10:00
7. The complete process is visible in the Agent Console

## Core business rules

- maximum five active appointments per location and bookable time slot
- 12:00 is blocked for lunch and must never be bookable
- patients do not select rooms; the system assigns an available room
- a write is only confirmed after the corresponding backend operation succeeds
- failed rescheduling must leave the original appointment active
- a patient may retain a confirmed appointment while waiting for a preferred slot
- a waitlist offer never replaces an existing appointment before explicit acceptance
- relevant state changes are recorded as chronological events

## Current repository state

The repository contains the implemented demo website and integration layer, the current Supabase schema/migrations and regression tests, Talkdesk IVR configuration material, and GitHub Pages/Vercel deployment configuration. Ongoing Talkdesk AI Agent configuration must continue to use the same backend appointment logic and authoritative Supabase data as the web channel.

All patient and appointment data used for the demo is fictional.
