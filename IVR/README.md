# Unilabs IVR

This folder documents the Talkdesk Studio IVR used for the Unilabs demo.

## Current setup

- **Talkdesk number:** `+49 5241 9143005` (`DEV Nummer`)
- **Studio flow:** `Unilabs Demo - imported`
- **Flow validation:** `0 Errors`
- **Language:** Dutch (`nl-NL`)
- **AI handoff:** `Unilabs Appointment Assistant`

## Routing

```text
Incoming call
  |
  v
Unilabs Main IVR
  |
  +-- 1 Patient / Client
  |      -> Unilabs AI Appointment Agent
  |         +-- Success -> End flow
  |         +-- Escalation -> Demo Human Mobile
  |         +-- Execution error -> Demo Human Mobile
  |
  +-- 2 Doctor Midden-Nederland -> Demo Human Mobile
  +-- 3 Doctor Oost-Nederland  -> Demo Human Mobile
  +-- 4 Healthcare Institution -> Demo Human Mobile
  +-- 5 Other Questions        -> Demo Human Mobile
```

## IVR prompt

> Welkom bij Unilabs.  
> Bent u patiënt of cliënt? Toets 1.  
> Bent u arts in de regio Midden-Nederland, voorheen Saltro of SHO? Toets 2.  
> Bent u arts in de regio Oost-Nederland, voorheen Medlon? Toets 3.  
> Belt u namens een zorginstelling? Toets 4.  
> Voor alle overige vragen, toets 5.

## Human fallback

The `Demo Human Mobile` step uses **Forward to External Number**. It is used for options 2–5 and as the fallback for AI escalation or execution errors.

Recommended exits:

- `No answer` -> `End flow`
- `Invalid number` -> `End flow`
- `Invalid outbound number` -> `End flow`

## AI step

Studio component: `Unilabs AI Appointment Agent`

Selected Autopilot: `Unilabs Appointment Assistant`

Recommended exits:

- `Success` -> `End flow`
- `Escalation` -> `Demo Human Mobile`
- `Execution error` -> `Demo Human Mobile`
- Component error handling -> follow the `Execution error` path

The AI Agent Platform configuration is maintained separately from this IVR documentation.

## Validation checklist

Before a demo:

1. Confirm IVR option `1` routes to the AI step.
2. Confirm options `2`–`5` route to `Demo Human Mobile`.
3. Confirm the Studio flow is published.
4. Confirm the demo number is assigned to the published flow.
5. Test option `2` to validate the human fallback path.
6. Test option `1` to validate the Autopilot handoff.

## Notes

- During voice testing, verify the TTS pronunciation of `Unilabs` and `SHO`.
- Keep Studio/IVR changes separate from AI Agent Platform fine-tuning where possible.
