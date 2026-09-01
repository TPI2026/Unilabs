-- Reset the complete fictional Talkdesk demo state deterministically.
-- Demo window: 1-4 December 2026.
-- Central waitlist slot: Amsterdam, 1 Dec 2026, 10:00 (fully booked).
-- PAT-1003 keeps UNI-100020 / APT-LIVE-200009 on 4 Dec 2026 at 10:00.
select public.prepare_december_waitlist_demo();
