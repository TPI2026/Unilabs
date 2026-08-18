begin;

select public.reset_demo_scenario(date '2030-01-15', 7, 5);

do $$
declare
  v_a_book jsonb;
  v_a_replay jsonb;
  v_b_check jsonb;
  v_b_book jsonb;
  v_b_waitlist jsonb;
  v_a_move jsonb;
  v_offer jsonb;
  v_b_move jsonb;
  v_waitlist_id text;
  v_offer_token text;
  v_b_appointment_id text;
begin
  v_a_book := public.book_appointment(
    'TEST-CS-A-BOOK', 'PAT-1001', 'LOC-UTR', date '2030-01-15', time '10:00'
  );

  v_a_replay := public.book_appointment(
    'TEST-CS-A-BOOK', 'PAT-1001', 'LOC-UTR', date '2030-01-15', time '10:00'
  );

  if v_a_book->>'appointment_id' <> v_a_replay->>'appointment_id' then
    raise exception 'Idempotent replay returned a different appointment';
  end if;

  if (select count(*) from public.action_requests where request_id = 'TEST-CS-A-BOOK') <> 1 then
    raise exception 'Action request was not stored exactly once';
  end if;

  v_b_check := public.check_availability('LOC-UTR', date '2030-01-15', time '10:00', 'PAT-1002');
  if (v_b_check->>'available')::boolean then
    raise exception 'Utrecht 10:00 should be fully booked after Patient A books the fifth room';
  end if;
  if v_b_check#>>'{next_available,time}' <> '11:00' then
    raise exception 'Expected 11:00 as the next available appointment';
  end if;

  v_b_book := public.book_appointment(
    'TEST-CS-B-BOOK', 'PAT-1002', 'LOC-UTR', date '2030-01-15', time '11:00'
  );
  v_b_appointment_id := v_b_book->>'appointment_id';

  v_b_waitlist := public.join_waitlist(
    'TEST-CS-B-WAITLIST', 'PAT-1002', 'LOC-UTR', date '2030-01-15', time '10:00', v_b_appointment_id
  );
  v_waitlist_id := v_b_waitlist->>'waitlist_entry_id';

  v_a_move := public.reschedule_appointment(
    'TEST-CS-A-MOVE',
    v_a_book->>'appointment_id',
    'LOC-UTR',
    date '2030-01-15',
    time '14:00',
    null,
    null
  );

  v_offer := v_a_move->'released_slot_waitlist_result';
  if not (v_offer->>'offer_created')::boolean then
    raise exception 'Releasing Utrecht 10:00 did not create the Patient B waitlist offer';
  end if;
  if v_offer->>'waitlist_entry_id' <> v_waitlist_id then
    raise exception 'The wrong waitlist entry received the offer';
  end if;
  if jsonb_array_length(v_offer->'notifications') <> 2 then
    raise exception 'Expected one structured chat and one structured voice notification';
  end if;

  if (select count(*) from public.notifications where waitlist_entry_id = v_waitlist_id and channel in ('chat','voice')) <> 2 then
    raise exception 'Structured omnichannel notifications were not persisted';
  end if;

  if (select count(*) from public.appointments a join public.appointment_slots s on s.slot_id=a.slot_id where a.status='confirmed' and s.location_id='LOC-UTR' and s.slot_date=date '2030-01-15' and s.start_time=time '10:00') <> 4 then
    raise exception 'The released slot should contain four confirmed appointments before acceptance';
  end if;

  if public.unilabs_active_reservation_count(v_offer->>'target_slot_id') <> 1 then
    raise exception 'The waitlist offer did not reserve the released capacity';
  end if;

  v_offer_token := v_offer->>'offer_token';
  v_b_move := public.reschedule_appointment(
    'TEST-CS-B-ACCEPT',
    v_b_appointment_id,
    'LOC-UTR',
    date '2030-01-15',
    time '10:00',
    v_waitlist_id,
    v_offer_token
  );

  if not (v_b_move->>'waitlist_completed')::boolean then
    raise exception 'Waitlist acceptance did not complete the waitlist entry';
  end if;

  if (select status from public.waitlist_entries where waitlist_entry_id = v_waitlist_id) <> 'completed' then
    raise exception 'Waitlist entry is not completed';
  end if;

  if (select count(*) from public.appointments where patient_id='PAT-1002' and status='confirmed') <> 1 then
    raise exception 'Patient B does not have exactly one active appointment';
  end if;

  if not exists (
    select 1
    from public.appointments a
    join public.appointment_slots s on s.slot_id=a.slot_id
    where a.patient_id='PAT-1002'
      and a.status='confirmed'
      and s.location_id='LOC-UTR'
      and s.slot_date=date '2030-01-15'
      and s.start_time=time '10:00'
  ) then
    raise exception 'Patient B was not moved to Utrecht 10:00';
  end if;

  if exists (
    select 1
    from public.appointments a
    join public.appointment_slots s on s.slot_id=a.slot_id
    where a.patient_id='PAT-1002'
      and a.status='confirmed'
      and s.start_time=time '11:00'
  ) then
    raise exception 'Patient B still has an active 11:00 appointment';
  end if;

  if exists (
    select 1 from public.notifications
    where waitlist_entry_id = v_waitlist_id
      and status <> 'responded'
  ) then
    raise exception 'Waitlist offer notifications were not closed after acceptance';
  end if;
end;
$$;

rollback;
