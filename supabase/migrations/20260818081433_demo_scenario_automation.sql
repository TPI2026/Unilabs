-- Unilabs AI Appointment Demo
-- Dynamic scenario reset and automated waitlist offer expiry processing.

create or replace function public.reset_demo_scenario(
  p_scenario_date date default ((now() at time zone 'Europe/Amsterdam')::date + 1),
  p_generated_days integer default 7,
  p_offer_hold_minutes integer default 5
)
returns jsonb
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  v_slots integer;
  v_appointments integer;
  v_waitlists integer;
  v_identities integer;
  v_now timestamptz := now();
begin
  if p_scenario_date is null then
    raise exception using errcode = '22023', message = 'scenario_date is required';
  end if;

  if p_generated_days < 1 or p_generated_days > 31 then
    raise exception using errcode = '22023', message = 'generated_days must be between 1 and 31';
  end if;

  if p_offer_hold_minutes < 1 or p_offer_hold_minutes > 60 then
    raise exception using errcode = '22023', message = 'offer_hold_minutes must be between 1 and 60';
  end if;

  perform pg_advisory_xact_lock(hashtext('unilabs_reset_demo_scenario'));

  if (
    select count(*)
    from public.locations
    where location_id in ('LOC-AMS', 'LOC-RTM', 'LOC-UTR')
  ) <> 3 then
    raise exception using errcode = 'P0002', message = 'Required demo locations are missing';
  end if;

  if (
    select count(*)
    from public.patients
    where patient_id in (
      'PAT-1001', 'PAT-1002', 'PAT-1003', 'PAT-1004', 'PAT-1005',
      'PAT-BG-U10-01', 'PAT-BG-U10-02', 'PAT-BG-U10-03', 'PAT-BG-U10-04',
      'PAT-BG-R15-01', 'PAT-BG-R15-02', 'PAT-BG-R15-03', 'PAT-BG-R15-04', 'PAT-BG-R15-05'
    )
  ) <> 14 then
    raise exception using errcode = 'P0002', message = 'Required demo patients are missing';
  end if;

  if exists (
    select 1
      from public.locations l
      left join public.rooms r on r.location_id = l.location_id
     where l.location_id in ('LOC-AMS', 'LOC-RTM', 'LOC-UTR')
     group by l.location_id
    having count(r.room_id) <> 5
  ) then
    raise exception using errcode = 'P0001', message = 'Each demo location must have exactly five rooms';
  end if;

  delete from public.events;
  delete from public.notifications;
  delete from public.waitlist_entries;
  delete from public.action_requests;
  delete from public.appointments;
  delete from public.appointment_slots;

  insert into public.demo_scenarios(
    scenario_key, scenario_date, generated_days, offer_hold_minutes, status, reset_at, metadata
  ) values (
    'default',
    p_scenario_date,
    p_generated_days,
    p_offer_hold_minutes,
    'ready',
    v_now,
    jsonb_build_object(
      'timezone', 'Europe/Amsterdam',
      'central_story', 'Patient A and Patient B',
      'reset_function', 'ResetDemoScenario'
    )
  )
  on conflict (scenario_key) do update
     set scenario_date = excluded.scenario_date,
         generated_days = excluded.generated_days,
         offer_hold_minutes = excluded.offer_hold_minutes,
         status = excluded.status,
         reset_at = excluded.reset_at,
         metadata = excluded.metadata;

  insert into public.patient_channel_identities(
    identity_id,
    patient_id,
    channel,
    external_identifier,
    verification_method,
    is_verified,
    is_primary,
    is_active,
    metadata,
    created_at,
    updated_at
  )
  select
    'IDENTITY-' || upper(channel) || '-' || patient_id,
    patient_id,
    channel,
    'demo-' || channel || ':' || patient_id,
    'trusted_demo_context',
    true,
    true,
    true,
    jsonb_build_object('source', 'reset_demo_scenario', 'fictional', true),
    v_now,
    v_now
  from (
    select p.patient_id, c.channel
      from public.patients p
      cross join (values ('chat'::text), ('voice'::text)) c(channel)
     where p.patient_id in ('PAT-1001', 'PAT-1002', 'PAT-1003', 'PAT-1004', 'PAT-1005')
  ) identities
  on conflict (identity_id) do update
     set external_identifier = excluded.external_identifier,
         verification_method = excluded.verification_method,
         is_verified = excluded.is_verified,
         is_primary = excluded.is_primary,
         is_active = excluded.is_active,
         metadata = excluded.metadata,
         updated_at = excluded.updated_at;

  get diagnostics v_identities = row_count;

  insert into public.appointment_slots(
    slot_id, location_id, slot_date, start_time, bookable, created_at
  )
  select
    'SLOT-' || replace(l.location_id, 'LOC-', '') || '-D' || d.day_offset::text || '-' || to_char(t.start_time, 'HH24MI'),
    l.location_id,
    p_scenario_date + d.day_offset,
    t.start_time,
    (t.start_time <> time '12:00'),
    v_now
  from public.locations l
  cross join generate_series(0, p_generated_days - 1) as d(day_offset)
  cross join (
    values
      (time '09:00'),
      (time '10:00'),
      (time '11:00'),
      (time '12:00'),
      (time '13:00'),
      (time '14:00'),
      (time '15:00'),
      (time '16:00'),
      (time '17:00')
  ) as t(start_time)
  where l.location_id in ('LOC-AMS', 'LOC-RTM', 'LOC-UTR');

  get diagnostics v_slots = row_count;

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
    seed.appointment_id,
    seed.patient_id,
    seed.booking_reference,
    seed.location_id,
    s.slot_id,
    r.room_id,
    'confirmed',
    v_now,
    v_now
  from (
    values
      ('APT-BG-U10-01'::text, 'PAT-BG-U10-01'::text, 'UNI-100001'::text, 'LOC-UTR'::text, time '10:00', 1::smallint),
      ('APT-BG-U10-02', 'PAT-BG-U10-02', 'UNI-100002', 'LOC-UTR', time '10:00', 2::smallint),
      ('APT-BG-U10-03', 'PAT-BG-U10-03', 'UNI-100003', 'LOC-UTR', time '10:00', 3::smallint),
      ('APT-BG-U10-04', 'PAT-BG-U10-04', 'UNI-100004', 'LOC-UTR', time '10:00', 4::smallint),
      ('APT-BG-R15-01', 'PAT-BG-R15-01', 'UNI-100005', 'LOC-RTM', time '15:00', 1::smallint),
      ('APT-BG-R15-02', 'PAT-BG-R15-02', 'UNI-100006', 'LOC-RTM', time '15:00', 2::smallint),
      ('APT-BG-R15-03', 'PAT-BG-R15-03', 'UNI-100007', 'LOC-RTM', time '15:00', 3::smallint),
      ('APT-BG-R15-04', 'PAT-BG-R15-04', 'UNI-100008', 'LOC-RTM', time '15:00', 4::smallint),
      ('APT-BG-R15-05', 'PAT-BG-R15-05', 'UNI-100009', 'LOC-RTM', time '15:00', 5::smallint),
      ('APT-C-1004', 'PAT-1004', 'UNI-100010', 'LOC-AMS', time '13:00', 1::smallint),
      ('APT-E-1005', 'PAT-1005', 'UNI-100011', 'LOC-RTM', time '16:00', 1::smallint)
  ) as seed(appointment_id, patient_id, booking_reference, location_id, start_time, room_order)
  join public.appointment_slots s
    on s.location_id = seed.location_id
   and s.slot_date = p_scenario_date
   and s.start_time = seed.start_time
  join public.rooms r
    on r.location_id = seed.location_id
   and r.room_order = seed.room_order;

  get diagnostics v_appointments = row_count;

  insert into public.waitlist_entries(
    waitlist_entry_id,
    patient_id,
    location_id,
    requested_slot_id,
    current_appointment_id,
    status,
    created_at
  )
  select
    'WL-E-1005',
    'PAT-1005',
    'LOC-RTM',
    s.slot_id,
    'APT-E-1005',
    'waiting',
    v_now
  from public.appointment_slots s
  where s.location_id = 'LOC-RTM'
    and s.slot_date = p_scenario_date
    and s.start_time = time '15:00';

  get diagnostics v_waitlists = row_count;

  perform setval('public.unilabs_booking_reference_seq', 100011, true);
  perform setval('public.unilabs_appointment_id_seq', 200000, true);
  perform setval('public.unilabs_waitlist_id_seq', 200000, true);
  perform setval('public.unilabs_notification_id_seq', 200000, true);
  perform setval('public.unilabs_event_id_seq', 200000, true);

  insert into public.events(
    event_id, event_type, event_at, channel, details
  ) values (
    'EVT-LIVE-' || nextval('public.unilabs_event_id_seq'),
    'demo_reset',
    v_now,
    'system',
    jsonb_build_object(
      'scenario_date', p_scenario_date,
      'generated_days', p_generated_days,
      'offer_hold_minutes', p_offer_hold_minutes,
      'slot_count', v_slots,
      'appointment_count', v_appointments,
      'waitlist_count', v_waitlists
    )
  );

  if v_slots <> 27 * p_generated_days then
    raise exception using errcode = 'P0001', message = 'Unexpected slot count after reset';
  end if;

  if v_appointments <> 11 then
    raise exception using errcode = 'P0001', message = 'Unexpected baseline appointment count after reset';
  end if;

  if v_waitlists <> 1 then
    raise exception using errcode = 'P0001', message = 'Unexpected baseline waitlist count after reset';
  end if;

  return jsonb_build_object(
    'scenario_key', 'default',
    'scenario_date', p_scenario_date,
    'generated_days', p_generated_days,
    'offer_hold_minutes', p_offer_hold_minutes,
    'slot_count', v_slots,
    'appointment_count', v_appointments,
    'waitlist_count', v_waitlists,
    'identity_upsert_count', v_identities,
    'status', 'ready',
    'reset_at', v_now
  );
end;
$$;

revoke execute on function public.reset_demo_scenario(date, integer, integer) from public, anon, authenticated;
grant execute on function public.reset_demo_scenario(date, integer, integer) to service_role;

create extension if not exists pg_cron;

-- Keep exactly one expiry job. It executes every minute and forwards expired offers.
do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job where jobname = 'unilabs-expire-waitlist-offers'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'unilabs-expire-waitlist-offers',
    '* * * * *',
    $job$select public.expire_waitlist_offers();$job$
  );
end;
$$;

alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from public, anon, authenticated;
revoke usage, create on schema public from public, anon, authenticated;
grant usage on schema public to postgres, supabase_admin, service_role, authenticator;
revoke execute on all functions in schema public from public, anon, authenticated;
