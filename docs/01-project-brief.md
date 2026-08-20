# Unilabs AI Appointment Demo — Project Brief

## Objective

Demonstrate that a Talkdesk AI assistant can execute administrative appointment processes rather than merely answer questions.

The end-to-end demo must visibly check authoritative availability, execute transactional appointment actions, support waitlist handling, and expose resulting changes in the Agent Console.

## Demo scope

Supported administrative processes:

1. check appointment availability
2. book an available appointment
3. offer the next available option when a requested slot is full
4. join a waitlist while retaining an existing appointment
5. find an existing appointment
6. reschedule an appointment
7. cancel an appointment
8. detect released capacity and match it to an active waitlist request
9. let the patient explicitly accept or decline a waitlist offer
10. show relevant actions chronologically in the Agent Console

The demo does not include medical diagnosis, result interpretation, treatment recommendations, or other clinical decision-making.

## Demo locations

- Amsterdam
- Rotterdam
- Utrecht

Each location has five demo rooms. Patients never select a room; the system automatically assigns an available room after a successful booking.

## Appointment model

Bookable start times are 09:00, 10:00, 11:00, 13:00, 14:00, 15:00, 16:00, and 17:00.

12:00 is blocked for lunch and must never be bookable.

A maximum of five active appointments may exist per location and bookable time slot.

## System responsibilities

### Talkdesk

Talkdesk owns patient communication, intent recognition, conversation continuity, and invocation of the appropriate backend capability. It must never invent available appointments or transaction results.

### Supabase

Supabase is the central source of truth for locations, rooms, patients, appointment availability, appointments, waitlists, notifications, and events.

### Vercel

Vercel hosts the patient website, Agent Console, server-side APIs, and the integration layer between Talkdesk and Supabase. Privileged database credentials remain server-side.

## Central demo story

1. Patient A books the final available 10:00 appointment
2. Patient B requests 10:00, receives 11:00 instead, and joins the 10:00 waitlist
3. Patient A reschedules from 10:00 to 14:00
4. The released 10:00 capacity triggers a matching waitlist offer
5. Patient B explicitly accepts the offer
6. Patient B is atomically moved from 11:00 to 10:00
7. The full sequence is visible in the Agent Console

## Definition of done

The demo is complete only when the central story and relevant happy/unhappy paths are reproducible with consistent data. At minimum, validation must cover:

- successful booking
- full-slot handling without overbooking
- next-available alternative handling
- waitlist join while retaining an existing appointment
- successful rescheduling
- failed rescheduling with the original appointment preserved
- cancellation
- waitlist offer creation, acceptance, decline, and expiry/forwarding
- 12:00 lunch-slot rejection
- duplicate/race-condition protection
- chronological event visibility

Only fictional demo data may be used.
