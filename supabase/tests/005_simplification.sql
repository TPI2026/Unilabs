-- Regression tests for 20260818091211_simplify_platform.sql
-- Every data change is rolled back.

begin;

select public.reset_demo_scenario(date '2026-08-19', 7, 5);

do $$
declare
  a jsonb; b jsonb; w jsonb; moved jsonb; offer jsonb; accepted jsonb;
  notification_id text; offer_token text; waitlist_id text;
begin
  if to_regclass('public.patient_channel_identities') is not null then
    raise exception 'identity table must not exist';
  end if;

  a := public.book_appointment('TEST-SIMPLE-A','PAT-1001','LOC-UTR',date '2026-08-19',time '10:00');
  if public.book_appointment('TEST-SIMPLE-A','PAT-1001','LOC-UTR',date '2026-08-19',time '10:00')->>'appointment_id' <> a->>'appointment_id' then
    raise exception 'idempotent replay failed';
  end if;

  b := public.book_appointment('TEST-SIMPLE-B','PAT-1002','LOC-UTR',date '2026-08-19',time '11:00');
  w := public.join_waitlist('TEST-SIMPLE-W','PAT-1002','LOC-UTR',date '2026-08-19',time '10:00',b->>'appointment_id');
  waitlist_id := w->>'waitlist_entry_id';

  moved := public.reschedule_appointment('TEST-SIMPLE-MOVE-A',a->>'appointment_id','LOC-UTR',date '2026-08-19',time '14:00',null,null);
  offer := moved->'released_slot_waitlist_result';
  notification_id := offer->>'notification_id';
  offer_token := offer->>'offer_token';

  if (select count(*) from public.notifications where waitlist_entry_id=waitlist_id) <> 1 then
    raise exception 'waitlist offer must create one notification';
  end if;
  if not exists (
    select 1 from public.notifications
    where notification_id=notification_id
      and status='pending'
      and payload->>'type'='waitlist_offer'
      and not (payload ? 'external_identifier')
  ) then
    raise exception 'notification is not channel-neutral';
  end if;

  accepted := public.reschedule_appointment('TEST-SIMPLE-MOVE-B',b->>'appointment_id','LOC-UTR',date '2026-08-19',time '10:00',waitlist_id,offer_token);
  if coalesce((accepted->>'waitlist_completed')::boolean,false) is not true then
    raise exception 'waitlist acceptance failed';
  end if;
  if (select count(*) from public.appointments where patient_id='PAT-1002' and status='confirmed') <> 1 then
    raise exception 'Patient B must have one active appointment';
  end if;
end $$;

select public.reset_demo_scenario(date '2026-08-19', 7, 5);

do $$
declare
  a jsonb; b jsonb; bw jsonb; cw jsonb; moved jsonb; cancelled jsonb;
  bw_id text; cw_id text; notification_id text;
begin
  a := public.book_appointment('TEST-CANCEL-A','PAT-1001','LOC-UTR',date '2026-08-19',time '10:00');
  b := public.book_appointment('TEST-CANCEL-B','PAT-1002','LOC-UTR',date '2026-08-19',time '11:00');
  bw := public.join_waitlist('TEST-CANCEL-BW','PAT-1002','LOC-UTR',date '2026-08-19',time '10:00',b->>'appointment_id');
  cw := public.join_waitlist('TEST-CANCEL-CW','PAT-1003','LOC-UTR',date '2026-08-19',time '10:00',null);
  bw_id := bw->>'waitlist_entry_id';
  cw_id := cw->>'waitlist_entry_id';

  moved := public.reschedule_appointment('TEST-CANCEL-MOVE-A',a->>'appointment_id','LOC-UTR',date '2026-08-19',time '14:00',null,null);
  notification_id := moved->'released_slot_waitlist_result'->>'notification_id';
  cancelled := public.cancel_appointment('TEST-CANCEL-B-CANCEL',b->>'appointment_id');

  if (cancelled->>'cancelled_waitlist_count')::integer <> 1 then
    raise exception 'dependent waitlist was not closed';
  end if;
  if not exists (select 1 from public.waitlist_entries where waitlist_entry_id=bw_id and status='cancelled') then
    raise exception 'dependent waitlist is not cancelled';
  end if;
  if not exists (select 1 from public.notifications where notification_id=notification_id and status='cancelled') then
    raise exception 'open notification is not cancelled';
  end if;
  if not exists (select 1 from public.waitlist_entries where waitlist_entry_id=cw_id and status='offered') then
    raise exception 'offer was not forwarded';
  end if;
end $$;

select 'simplification_passed' as test_result;
rollback;
