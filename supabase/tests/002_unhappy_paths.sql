begin;

select public.reset_demo_scenario(date '2030-02-01', 7, 5);

do $$
declare
  v_a jsonb;
  v_duplicate jsonb;
  v_noor_slot text;
begin
  begin
    perform public.book_appointment(
      'TEST-UP-LUNCH', 'PAT-1003', 'LOC-RTM', date '2030-02-01', time '12:00'
    );
    raise exception 'Lunch booking unexpectedly succeeded';
  exception when others then
    if sqlerrm = 'Lunch booking unexpectedly succeeded' then raise; end if;
  end;

  v_a := public.book_appointment(
    'TEST-UP-A-BOOK', 'PAT-1001', 'LOC-UTR', date '2030-02-01', time '10:00'
  );

  begin
    perform public.book_appointment(
      'TEST-UP-B-FULL', 'PAT-1002', 'LOC-UTR', date '2030-02-01', time '10:00'
    );
    raise exception 'Full-slot booking unexpectedly succeeded';
  exception when others then
    if sqlerrm = 'Full-slot booking unexpectedly succeeded' then raise; end if;
  end;

  v_duplicate := public.book_appointment(
    'TEST-UP-A-DUPLICATE', 'PAT-1001', 'LOC-UTR', date '2030-02-01', time '10:00'
  );
  if not (v_duplicate->>'unchanged')::boolean then
    raise exception 'Duplicate patient booking was not handled as unchanged';
  end if;
  if (select count(*) from public.appointments where patient_id='PAT-1001' and status='confirmed') <> 1 then
    raise exception 'Duplicate patient booking created more than one appointment';
  end if;

  begin
    perform public.book_appointment(
      'TEST-UP-REQUEST-REUSE', 'PAT-1003', 'LOC-RTM', date '2030-02-01', time '09:00'
    );
    perform public.book_appointment(
      'TEST-UP-REQUEST-REUSE', 'PAT-1003', 'LOC-RTM', date '2030-02-01', time '10:00'
    );
    raise exception 'request_id reuse with changed payload unexpectedly succeeded';
  exception when others then
    if sqlerrm = 'request_id reuse with changed payload unexpectedly succeeded' then raise; end if;
  end;

  select slot_id into v_noor_slot
  from public.appointments
  where appointment_id='APT-C-1004';

  begin
    perform public.reschedule_appointment(
      'TEST-UP-NOOR-FULL',
      'APT-C-1004',
      'LOC-RTM',
      date '2030-02-01',
      time '15:00',
      null,
      null
    );
    raise exception 'Rescheduling into a full slot unexpectedly succeeded';
  exception when others then
    if sqlerrm = 'Rescheduling into a full slot unexpectedly succeeded' then raise; end if;
  end;

  if (select slot_id from public.appointments where appointment_id='APT-C-1004') <> v_noor_slot then
    raise exception 'Failed rescheduling changed the original appointment';
  end if;

  begin
    perform public.join_waitlist(
      'TEST-UP-WAITLIST-AVAILABLE', 'PAT-1003', 'LOC-RTM', date '2030-02-01', time '09:00', null
    );
    raise exception 'Joining an available slot waitlist unexpectedly succeeded';
  exception when others then
    if sqlerrm = 'Joining an available slot waitlist unexpectedly succeeded' then raise; end if;
  end;

  begin
    perform public.decline_waitlist_offer(
      'TEST-UP-DECLINE-MISSING', 'PAT-1002', 'WL-NOT-FOUND', 'NOT-NOT-FOUND'
    );
    raise exception 'Declining a missing offer unexpectedly succeeded';
  exception when others then
    if sqlerrm = 'Declining a missing offer unexpectedly succeeded' then raise; end if;
  end;
end;
$$;

rollback;
