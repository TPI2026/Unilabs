create or replace function public.prepare_december_waitlist_demo()
returns jsonb
language plpgsql
set search_path to 'public'
as $function$
declare
  v_result jsonb;
  v_slot_id text;
  v_room_id text;
begin
  v_result := public.reset_demo_scenario(date '2026-12-01', 4, 5);

  -- Start the deterministic Talkdesk waitlist demo with no active offer.
  delete from public.notifications;
  delete from public.waitlist_entries;

  -- Reuse five existing background demo appointments to fill Amsterdam 10:00
  -- on the first demo day. This keeps the patient master data unchanged.
  select slot_id into v_slot_id
  from public.appointment_slots
  where location_id='LOC-AMS'
    and slot_date=date '2026-12-01'
    and start_time=time '10:00';

  if v_slot_id is null then
    raise exception 'Amsterdam 2026-12-01 10:00 slot was not generated';
  end if;

  update public.appointments a
     set location_id='LOC-AMS',
         slot_id=v_slot_id,
         room_id=r.room_id,
         updated_at=now()
    from (values
      ('APT-BG-U10-01'::text,1::smallint),
      ('APT-BG-U10-02'::text,2::smallint),
      ('APT-BG-U10-03'::text,3::smallint),
      ('APT-BG-U10-04'::text,4::smallint),
      ('APT-BG-R15-01'::text,5::smallint)
    ) seed(appointment_id, room_order)
    join public.rooms r
      on r.location_id='LOC-AMS'
     and r.room_order=seed.room_order
   where a.appointment_id=seed.appointment_id;

  -- Preserve the Talkdesk demo identifiers already used by the appointment flows.
  select room_id into v_room_id
  from public.rooms
  where location_id='LOC-AMS' and room_order=1;

  insert into public.appointments(
    appointment_id,
    patient_id,
    booking_reference,
    location_id,
    slot_id,
    room_id,
    status,
    created_at,
    updated_at
  )
  select
    'APT-LIVE-200009',
    'PAT-1003',
    'UNI-100020',
    'LOC-AMS',
    s.slot_id,
    v_room_id,
    'confirmed',
    now(),
    now()
  from public.appointment_slots s
  where s.location_id='LOC-AMS'
    and s.slot_date=date '2026-12-04'
    and s.start_time=time '10:00';

  if not found then
    raise exception 'Amsterdam 2026-12-04 10:00 slot was not generated';
  end if;

  perform setval(
    'public.unilabs_booking_reference_seq',
    greatest(
      100020,
      (select coalesce(max(substring(booking_reference from '[0-9]+$')::bigint),100020)
       from public.appointments)
    ),
    true
  );

  perform setval(
    'public.unilabs_appointment_id_seq',
    greatest(
      200009,
      (select coalesce(max(substring(appointment_id from '[0-9]+$')::bigint),200009)
       from public.appointments
       where appointment_id like 'APT-LIVE-%')
    ),
    true
  );

  return jsonb_build_object(
    'scenario_start','2026-12-01',
    'scenario_end','2026-12-04',
    'generated_days',4,
    'waitlist_slot', public.check_availability(
      'LOC-AMS',
      date '2026-12-01',
      time '10:00',
      null
    ),
    'patient_1003_appointment', (
      select jsonb_build_object(
        'appointment_id',a.appointment_id,
        'booking_reference',a.booking_reference,
        'location_id',a.location_id,
        'date',s.slot_date,
        'time',to_char(s.start_time,'HH24:MI'),
        'status',a.status
      )
      from public.appointments a
      join public.appointment_slots s on s.slot_id=a.slot_id
      where a.appointment_id='APT-LIVE-200009'
    )
  );
end;
$function$;
