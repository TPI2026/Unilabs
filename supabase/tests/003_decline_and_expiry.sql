begin;

select public.reset_demo_scenario(date '2030-03-01', 7, 5);

do $$
declare
  v_a jsonb;
  v_b jsonb;
  v_b_wait jsonb;
  v_a_move jsonb;
  v_offer jsonb;
  v_decline jsonb;
  v_notification_id text;
begin
  v_a := public.book_appointment('TEST-DE-A', 'PAT-1001', 'LOC-UTR', date '2030-03-01', time '10:00');
  v_b := public.book_appointment('TEST-DE-B', 'PAT-1002', 'LOC-UTR', date '2030-03-01', time '11:00');
  v_b_wait := public.join_waitlist('TEST-DE-B-WL', 'PAT-1002', 'LOC-UTR', date '2030-03-01', time '10:00', v_b->>'appointment_id');
  v_a_move := public.reschedule_appointment('TEST-DE-A-MOVE', v_a->>'appointment_id', 'LOC-UTR', date '2030-03-01', time '14:00', null, null);
  v_offer := v_a_move->'released_slot_waitlist_result';
  v_notification_id := v_offer->>'notification_id';

  v_decline := public.decline_waitlist_offer(
    'TEST-DE-B-DECLINE', 'PAT-1002', v_b_wait->>'waitlist_entry_id', v_notification_id
  );

  if v_decline->>'status' <> 'declined' or not (v_decline->>'appointment_unchanged')::boolean then
    raise exception 'Decline result is incorrect';
  end if;
  if (select status from public.waitlist_entries where waitlist_entry_id=v_b_wait->>'waitlist_entry_id') <> 'declined' then
    raise exception 'Waitlist entry was not declined';
  end if;
  if not exists (
    select 1 from public.appointments a join public.appointment_slots s on s.slot_id=a.slot_id
    where a.appointment_id=v_b->>'appointment_id' and a.status='confirmed' and s.start_time=time '11:00'
  ) then
    raise exception 'Decline changed Patient B current appointment';
  end if;
end;
$$;

select public.reset_demo_scenario(date '2030-03-02', 7, 1);

do $$
declare
  v_a jsonb;
  v_b jsonb;
  v_b_wait jsonb;
  v_d_wait jsonb;
  v_a_move jsonb;
  v_offer jsonb;
  v_expiry jsonb;
  v_expire_at timestamptz;
begin
  v_a := public.book_appointment('TEST-EX-A', 'PAT-1001', 'LOC-UTR', date '2030-03-02', time '10:00');
  v_b := public.book_appointment('TEST-EX-B', 'PAT-1002', 'LOC-UTR', date '2030-03-02', time '11:00');
  v_b_wait := public.join_waitlist('TEST-EX-B-WL', 'PAT-1002', 'LOC-UTR', date '2030-03-02', time '10:00', v_b->>'appointment_id');
  v_d_wait := public.join_waitlist('TEST-EX-D-WL', 'PAT-1005', 'LOC-UTR', date '2030-03-02', time '10:00', 'APT-E-1005');
  v_a_move := public.reschedule_appointment('TEST-EX-A-MOVE', v_a->>'appointment_id', 'LOC-UTR', date '2030-03-02', time '14:00', null, null);
  v_offer := v_a_move->'released_slot_waitlist_result';
  v_expire_at := (v_offer->>'offer_expires_at')::timestamptz + interval '1 second';

  v_expiry := public.expire_waitlist_offers(v_expire_at, 100);
  if (v_expiry->>'processed_count')::integer <> 1 then
    raise exception 'Expected exactly one expired offer';
  end if;
  if (select status from public.waitlist_entries where waitlist_entry_id=v_b_wait->>'waitlist_entry_id') <> 'expired' then
    raise exception 'Patient B offer was not expired';
  end if;
  if (select status from public.waitlist_entries where waitlist_entry_id=v_d_wait->>'waitlist_entry_id') <> 'offered' then
    raise exception 'The next waiting patient did not receive the released reservation';
  end if;
  if public.unilabs_active_reservation_count(v_offer->>'target_slot_id', null, v_expire_at + interval '1 second') <> 1 then
    raise exception 'Forwarded waitlist offer did not reserve capacity';
  end if;
end;
$$;

rollback;
