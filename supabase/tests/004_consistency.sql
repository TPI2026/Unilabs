begin;

select public.reset_demo_scenario(date '2030-04-01', 7, 5);

do $$
declare
  v_issue_count integer;
begin
  select count(*) into v_issue_count
  from (
    select a.slot_id, count(*) as confirmed_count, public.unilabs_slot_capacity(s.location_id) as capacity
    from public.appointments a
    join public.appointment_slots s on s.slot_id=a.slot_id
    where a.status='confirmed'
    group by a.slot_id, s.location_id
    having count(*) > public.unilabs_slot_capacity(s.location_id)
  ) q;
  if v_issue_count <> 0 then raise exception 'Over-capacity appointments detected'; end if;

  select count(*) into v_issue_count
  from (
    select slot_id, room_id
    from public.appointments
    where status='confirmed'
    group by slot_id, room_id
    having count(*) > 1
  ) q;
  if v_issue_count <> 0 then raise exception 'Duplicate confirmed room-slot assignment detected'; end if;

  select count(*) into v_issue_count
  from (
    select patient_id, slot_id
    from public.appointments
    where status='confirmed'
    group by patient_id, slot_id
    having count(*) > 1
  ) q;
  if v_issue_count <> 0 then raise exception 'Duplicate confirmed patient-slot assignment detected'; end if;

  select count(*) into v_issue_count
  from public.waitlist_entries
  where status='offered'
    and (offered_at is null or offer_expires_at is null or offer_token is null);
  if v_issue_count <> 0 then raise exception 'Offered waitlist entry lacks reservation data'; end if;

  select count(*) into v_issue_count
  from public.appointment_slots
  where start_time=time '12:00' and bookable=true;
  if v_issue_count <> 0 then raise exception 'Lunch slot is bookable'; end if;

  if (select count(*) from public.appointment_slots) <> 189 then
    raise exception 'Seven-day scenario does not contain 189 slots';
  end if;

  if (select count(*) from public.patient_channel_identities where patient_id in ('PAT-1001','PAT-1002','PAT-1003','PAT-1004','PAT-1005') and is_active and is_verified) <> 10 then
    raise exception 'Expected ten active verified demo channel identities';
  end if;
end;
$$;

rollback;
