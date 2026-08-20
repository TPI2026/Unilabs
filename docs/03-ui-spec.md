# Unilabs AI Appointment Demo — UI Specification

## Purpose

The website is a controlled demo environment for the appointment-management scenario. It may use Unilabs Netherlands as a visual reference, but it must remain clearly identifiable as a demo and must not represent real appointment availability.

## Patient-facing experience

The patient-facing website should:

- provide a clear route into the appointment-management experience
- embed the Talkdesk chat experience where required by the demo
- use only controlled fictional appointment and patient data
- avoid any presentation that could reasonably be mistaken for a live Unilabs booking service
- keep the interaction focused on the administrative appointment use cases

## Agent Console

The Agent Console is the operational demonstration view. It should expose the state needed to understand and validate AI-triggered actions, including:

- appointments
- capacity/availability by location, date, and time
- assigned room
- waitlist entries and offers
- notifications
- chronological events

The Agent Console is a demo operations interface, not a representation of a production Unilabs employee application.

## Location scope

The controlled appointment scenario uses:

- Amsterdam
- Rotterdam
- Utrecht

Location pages and availability views must use only the current demo backend state.

## Channel consistency

The website, Agent Console, Talkdesk Chat, and later Voice flow must use the same authoritative appointment logic. UI state must not independently invent availability or transaction outcomes.

## Priority

Reliability, correct booking data, and a transparent end-to-end demonstration take priority over visual perfection.
