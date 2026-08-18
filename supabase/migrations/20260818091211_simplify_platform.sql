-- Unilabs AI Appointment Demo
-- Simplify the Supabase model after the initial hardening pass.
-- Keep only data and functions required by the current appointment and waitlist use cases.

create or replace function public.unilabs_begin_action_request(
  p_request_id text,
  p_action_name text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  v_hash text;
  v_existing public.action_requests%rowtype;
  v_inserted integer;
begin
  if p_request_id is null or btrim(p_request_id) = '' then
    raise exception using errcode = '22023', message = 'request_id must be a non-empty string';
  end if;
  v_hash := public.unilabs_payload_hash(p_payload);
  insert into public.action_requests(request_id, action_name, payload_hash, created_at)
  values (p_request_id, p_action_name, v_hash, now())
  on conflict (request_id) do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return jsonb_build_object('replay', false, 'payload_hash', v_hash);
  end if;
  select * into v_existing from public.action_requests where request_id = p_request_id for update;
  if v_existing.action_name <> p_action_name or v_existing.payload_hash <> v_hash then
    raise exception using errcode = '23505', message = 'request_id already exists with a different action or payload';
  end if;
  if v_existing.response is not null then
    return jsonb_build_object('replay', true, 'response', v_existing.response);
  end if;
  raise exception using errcode = '55P03', message = 'request_id exists without a completed response';
end;
$$;

create or replace function public.unilabs_complete_action_request(
  p_request_id text,
  p_response jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
begin
  update public.action_requests
     set response = p_response,
         completed_at = now()
   where request_id = p_request_id
     and response is null;
  if not found then
    raise exception using errcode = 'P0001', message = 'action request cannot be completed';
  end if;
  return p_response;
end;
$$;

create or replace function public.unilabs_queue_waitlist_notification(
  p_waitlist_entry_id text,
  p_patient_id text,
  p_current_appointment_id text,
  p_target_slot_id text,
  p_target_location_id text,
  p_target_location text,
  p_target_date date,
  p_target_time time,
  p_offer_expires_at timestamptz,
  p_offer_token text
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_notification_id text;
  v_current_time time;
  v_current_location text;
  v_current_date date;
  v_payload jsonb;
begin
  if p_current_appointment_id is not null then
    select s.start_time, l.city, s.slot_date
      into v_current_time, v_current_location, v_current_date
      from public.appointments a
      join public.appointment_slots s on s.slot_id = a.slot_id
      join public.locations l on l.location_id = a.location_id
     where a.appointment_id = p_current_appointment_id
       and a.status = 'confirmed';
  end if;
  v_payload := jsonb_build_object(
    'type', 'waitlist_offer',
    'patient_id', p_patient_id,
    'waitlist_entry_id', p_waitlist_entry_id,
    'current_appointment_id', p_current_appointment_id,
    'current_location', v_current_location,
    'current_date', v_current_date,
    'current_time', case when v_current_time is null then null else to_char(v_current_time, 'HH24:MI') end,
    'target_slot_id', p_target_slot_id,
    'target_location_id', p_target_location_id,
    'target_location', p_target_location,
    'target_date', p_target_date,
    'target_time', to_char(p_target_time, 'HH24:MI'),
    'offer_expires_at', p_offer_expires_at,
    'offer_token', p_offer_token
  );
  v_notification_id := 'NOT-LIVE-' || nextval('public.unilabs_notification_id_seq');
  insert into public.notifications(notification_id, patient_id, waitlist_entry_id, payload, status, created_at)
  values (v_notification_id, p_patient_id, p_waitlist_entry_id, v_payload, 'pending', now());
  return jsonb_build_object('notification_id', v_notification_id, 'status', 'pending', 'payload', v_payload);
end;
$$;

create or replace function public.unilabs_offer_waitlist_for_slot(
  p_slot_id text,
  p_as_of timestamptz
)
returns jsonb
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  v_location_id text;
  v_target_date date;
  v_target_time time;
  v_location text;
  v_bookable boolean;
  v_capacity integer;
  v_confirmed integer;
  v_reservations integer;
  v_waitlist public.waitlist_entries%rowtype;
  v_offer_expires_at timestamptz;
  v_offer_token text;
  v_hold_minutes integer;
  v_notification jsonb;
begin
  select s.location_id, s.slot_date, s.start_time, s.bookable, l.city
    into v_location_id, v_target_date, v_target_time, v_bookable, v_location
    from public.appointment_slots s
    join public.locations l on l.location_id = s.location_id
   where s.slot_id = p_slot_id
   for update of s;
  if not found then
    raise exception using errcode = 'P0002', message = format('Slot %s not found', p_slot_id);
  end if;
  if not v_bookable then
    return jsonb_build_object('offer_created', false, 'reason', 'slot_not_bookable');
  end if;
  v_capacity := public.unilabs_slot_capacity(v_location_id);
  select count(*)::integer into v_confirmed from public.appointments where slot_id = p_slot_id and status = 'confirmed';
  v_reservations := public.unilabs_active_reservation_count(p_slot_id, null, p_as_of);
  if v_confirmed + v_reservations >= v_capacity then
    return jsonb_build_object('offer_created', false, 'reason', 'slot_still_full');
  end if;
  select * into v_waitlist
    from public.waitlist_entries
   where requested_slot_id = p_slot_id and status = 'waiting'
   order by created_at, waitlist_entry_id
   for update skip locked
   limit 1;
  if not found then
    return jsonb_build_object('offer_created', false, 'reason', 'no_waiting_entry');
  end if;
  select offer_hold_minutes into v_hold_minutes from public.demo_scenarios where scenario_key = 'default';
  v_hold_minutes := coalesce(v_hold_minutes, 5);
  v_offer_expires_at := p_as_of + make_interval(mins => v_hold_minutes);
  v_offer_token := encode(extensions.gen_random_bytes(18), 'hex');
  update public.waitlist_entries
     set status = 'offered', offered_at = p_as_of, offer_expires_at = v_offer_expires_at,
         offer_token = v_offer_token, resolved_at = null
   where waitlist_entry_id = v_waitlist.waitlist_entry_id;
  v_notification := public.unilabs_queue_waitlist_notification(
    v_waitlist.waitlist_entry_id, v_waitlist.patient_id, v_waitlist.current_appointment_id,
    p_slot_id, v_location_id, v_location, v_target_date, v_target_time, v_offer_expires_at, v_offer_token
  );
  insert into public.events(event_id, patient_id, appointment_id, waitlist_entry_id, event_type, event_at, channel, details)
  values (
    'EVT-LIVE-' || nextval('public.unilabs_event_id_seq'), v_waitlist.patient_id,
    v_waitlist.current_appointment_id, v_waitlist.waitlist_entry_id, 'waitlist_match_found', p_as_of, 'system',
    jsonb_build_object('slot_id', p_slot_id, 'location_id', v_location_id, 'location', v_location,
      'date', v_target_date, 'time', to_char(v_target_time, 'HH24:MI'), 'offer_expires_at', v_offer_expires_at)
  );
  insert into public.events(event_id, patient_id, appointment_id, waitlist_entry_id, event_type, event_at, channel, details)
  values (
    'EVT-LIVE-' || nextval('public.unilabs_event_id_seq'), v_waitlist.patient_id,
    v_waitlist.current_appointment_id, v_waitlist.waitlist_entry_id, 'notification_queued', p_as_of, 'system',
    jsonb_build_object('notification_id', v_notification->>'notification_id')
  );
  return jsonb_build_object(
    'offer_created', true,
    'waitlist_entry_id', v_waitlist.waitlist_entry_id,
    'patient_id', v_waitlist.patient_id,
    'current_appointment_id', v_waitlist.current_appointment_id,
    'target_slot_id', p_slot_id,
    'target_location_id', v_location_id,
    'target_location', v_location,
    'target_slot_date', v_target_date,
    'target_start_time', to_char(v_target_time, 'HH24:MI'),
    'waitlist_status', 'offered',
    'offer_expires_at', v_offer_expires_at,
    'offer_token', v_offer_token,
    'notification_id', v_notification->>'notification_id',
    'notification_payload', v_notification->'payload'
  );
end;
$$;

create or replace function public.unilabs_offer_waitlist_for_slot(p_slot_id text)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
begin
  return public.unilabs_offer_waitlist_for_slot(p_slot_id, now());
end;
$$;

create or replace function public.reschedule_appointment(
  p_request_id text,
  p_appointment_id text,
  p_new_location_id text,
  p_new_slot_date date,
  p_new_start_time time,
  p_waitlist_entry_id text default null,
  p_offer_token text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_begin jsonb;
  v_payload jsonb;
  v_patient_id text;
  v_booking_reference text;
  v_old_location_id text;
  v_old_slot_id text;
  v_old_room_id text;
  v_old_date date;
  v_old_time time;
  v_new_slot_id text;
  v_new_bookable boolean;
  v_new_city text;
  v_capacity integer;
  v_new_confirmed integer;
  v_new_reserved integer;
  v_new_room_id text;
  v_new_room_name text;
  v_waitlist public.waitlist_entries%rowtype;
  v_release_result jsonb;
  v_response jsonb;
begin
  v_payload := jsonb_build_object(
    'appointment_id', p_appointment_id,
    'new_location_id', p_new_location_id,
    'new_slot_date', p_new_slot_date,
    'new_start_time', to_char(p_new_start_time, 'HH24:MI'),
    'waitlist_entry_id', p_waitlist_entry_id,
    'offer_token', p_offer_token
  );
  v_begin := public.unilabs_begin_action_request(p_request_id, 'RescheduleAppointment', v_payload);
  if (v_begin->>'replay')::boolean then return v_begin->'response'; end if;
  select a.patient_id, a.booking_reference, a.location_id, a.slot_id, a.room_id, s.slot_date, s.start_time
    into v_patient_id, v_booking_reference, v_old_location_id, v_old_slot_id, v_old_room_id, v_old_date, v_old_time
    from public.appointments a join public.appointment_slots s on s.slot_id = a.slot_id
   where a.appointment_id = p_appointment_id and a.status = 'confirmed' for update of a;
  if not found then raise exception using errcode = 'P0002', message = 'Confirmed appointment was not found'; end if;
  select s.slot_id, s.bookable, l.city into v_new_slot_id, v_new_bookable, v_new_city
    from public.appointment_slots s join public.locations l on l.location_id = s.location_id
   where s.location_id = p_new_location_id and s.slot_date = p_new_slot_date and s.start_time = p_new_start_time;
  if not found then raise exception using errcode = 'P0002', message = 'Target slot does not exist'; end if;
  if not v_new_bookable then raise exception using errcode = 'P0001', message = 'Target slot is not bookable'; end if;
  perform 1 from public.appointment_slots where slot_id in (v_old_slot_id, v_new_slot_id) order by slot_id for update;
  if v_new_slot_id = v_old_slot_id and p_new_location_id = v_old_location_id then
    v_response := jsonb_build_object('request_id',p_request_id,'appointment_id',p_appointment_id,'patient_id',v_patient_id,
      'booking_reference',v_booking_reference,'location_id',v_old_location_id,'date',v_old_date,
      'time',to_char(v_old_time,'HH24:MI'),'status','confirmed','unchanged',true,'waitlist_completed',false);
    return public.unilabs_complete_action_request(p_request_id, v_response);
  end if;
  if p_waitlist_entry_id is not null then
    select * into v_waitlist from public.waitlist_entries where waitlist_entry_id = p_waitlist_entry_id for update;
    if not found then raise exception using errcode = 'P0002', message = 'Waitlist entry was not found'; end if;
    if v_waitlist.patient_id <> v_patient_id
       or v_waitlist.requested_slot_id <> v_new_slot_id
       or v_waitlist.status <> 'offered'
       or v_waitlist.offer_expires_at <= now()
       or v_waitlist.offer_token is null
       or p_offer_token is null
       or v_waitlist.offer_token <> p_offer_token
       or (v_waitlist.current_appointment_id is not null and v_waitlist.current_appointment_id <> p_appointment_id) then
      raise exception using errcode = 'P0001', message = 'Waitlist offer is invalid or expired';
    end if;
  elsif p_offer_token is not null then
    raise exception using errcode = '22023', message = 'offer_token requires waitlist_entry_id';
  end if;
  v_capacity := public.unilabs_slot_capacity(p_new_location_id);
  select count(*)::integer into v_new_confirmed from public.appointments
   where slot_id = v_new_slot_id and status='confirmed' and appointment_id <> p_appointment_id;
  v_new_reserved := public.unilabs_active_reservation_count(v_new_slot_id, p_waitlist_entry_id);
  if v_new_confirmed + v_new_reserved >= v_capacity then raise exception using errcode='P0001', message='Target slot is fully booked'; end if;
  select r.room_id, r.room_name into v_new_room_id, v_new_room_name
    from public.rooms r
   where r.location_id=p_new_location_id
     and not exists (select 1 from public.appointments a where a.slot_id=v_new_slot_id and a.room_id=r.room_id and a.status='confirmed' and a.appointment_id<>p_appointment_id)
   order by r.room_order limit 1;
  if v_new_room_id is null then raise exception using errcode='P0001', message='No free room is available in the target slot'; end if;
  update public.appointments set location_id=p_new_location_id, slot_id=v_new_slot_id, room_id=v_new_room_id, updated_at=now()
   where appointment_id=p_appointment_id;
  if p_waitlist_entry_id is not null then
    update public.waitlist_entries set status='completed', resolved_at=now() where waitlist_entry_id=p_waitlist_entry_id;
    update public.notifications set status='responded', responded_at=now()
     where waitlist_entry_id=p_waitlist_entry_id and status='pending';
  end if;
  insert into public.events(event_id,patient_id,appointment_id,waitlist_entry_id,event_type,event_at,request_id,channel,details)
  values ('EVT-LIVE-'||nextval('public.unilabs_event_id_seq'),v_patient_id,p_appointment_id,p_waitlist_entry_id,'appointment_rescheduled',now(),p_request_id,'system',
    jsonb_build_object('booking_reference',v_booking_reference,'from_location_id',v_old_location_id,'from_date',v_old_date,'from_time',to_char(v_old_time,'HH24:MI'),'from_room_id',v_old_room_id,
      'to_location_id',p_new_location_id,'to_date',p_new_slot_date,'to_time',to_char(p_new_start_time,'HH24:MI'),'to_room_id',v_new_room_id,'to_room_name',v_new_room_name));
  insert into public.events(event_id,patient_id,appointment_id,waitlist_entry_id,event_type,event_at,request_id,channel,details)
  values ('EVT-LIVE-'||nextval('public.unilabs_event_id_seq'),v_patient_id,p_appointment_id,p_waitlist_entry_id,'slot_released',now(),p_request_id,'system',
    jsonb_build_object('location_id',v_old_location_id,'slot_id',v_old_slot_id,'date',v_old_date,'time',to_char(v_old_time,'HH24:MI'),'room_id',v_old_room_id));
  if p_waitlist_entry_id is not null then
    insert into public.events(event_id,patient_id,appointment_id,waitlist_entry_id,event_type,event_at,request_id,channel,details)
    values ('EVT-LIVE-'||nextval('public.unilabs_event_id_seq'),v_patient_id,p_appointment_id,p_waitlist_entry_id,'offer_accepted',now(),p_request_id,'system',
      jsonb_build_object('target_slot_id',v_new_slot_id,'target_time',to_char(p_new_start_time,'HH24:MI')));
  end if;
  v_release_result := public.unilabs_offer_waitlist_for_slot(v_old_slot_id);
  v_response := jsonb_build_object('request_id',p_request_id,'appointment_id',p_appointment_id,'patient_id',v_patient_id,
    'booking_reference',v_booking_reference,'location_id',p_new_location_id,'location',v_new_city,'date',p_new_slot_date,
    'time',to_char(p_new_start_time,'HH24:MI'),'room_id',v_new_room_id,'room_name',v_new_room_name,'status','confirmed',
    'unchanged',false,'waitlist_completed',(p_waitlist_entry_id is not null),'released_slot_waitlist_result',v_release_result);
  return public.unilabs_complete_action_request(p_request_id,v_response);
end;
$$;

create or replace function public.decline_waitlist_offer(
  p_request_id text,
  p_patient_id text,
  p_waitlist_entry_id text,
  p_notification_id text
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_begin jsonb;
  v_payload jsonb;
  v_waitlist public.waitlist_entries%rowtype;
  v_next_offer jsonb;
  v_response jsonb;
begin
  v_payload := jsonb_build_object('patient_id',p_patient_id,'waitlist_entry_id',p_waitlist_entry_id,'notification_id',p_notification_id);
  v_begin := public.unilabs_begin_action_request(p_request_id,'DeclineWaitlistOffer',v_payload);
  if (v_begin->>'replay')::boolean then return v_begin->'response'; end if;
  select * into v_waitlist from public.waitlist_entries where waitlist_entry_id=p_waitlist_entry_id for update;
  if not found then raise exception using errcode='P0002', message='Waitlist entry was not found'; end if;
  if v_waitlist.patient_id<>p_patient_id then raise exception using errcode='P0001', message='Waitlist entry does not belong to the patient'; end if;
  if v_waitlist.status='declined' then
    v_response:=jsonb_build_object('request_id',p_request_id,'waitlist_entry_id',p_waitlist_entry_id,'patient_id',p_patient_id,
      'current_appointment_id',v_waitlist.current_appointment_id,'notification_id',p_notification_id,'status','declined',
      'appointment_unchanged',true,'unchanged',true,'next_offer_result',jsonb_build_object('offer_created',false,'reason','already_declined'));
    return public.unilabs_complete_action_request(p_request_id,v_response);
  end if;
  if v_waitlist.status<>'offered' or v_waitlist.offer_expires_at<=now() then raise exception using errcode='P0001', message='Waitlist offer is not active'; end if;
  perform 1 from public.notifications where notification_id=p_notification_id and waitlist_entry_id=p_waitlist_entry_id and patient_id=p_patient_id for update;
  if not found then raise exception using errcode='P0002', message='Waitlist notification was not found'; end if;
  update public.waitlist_entries set status='declined', resolved_at=now() where waitlist_entry_id=p_waitlist_entry_id;
  update public.notifications set status='responded', responded_at=now() where notification_id=p_notification_id and status='pending';
  insert into public.events(event_id,patient_id,appointment_id,waitlist_entry_id,event_type,event_at,request_id,channel,details)
  values ('EVT-LIVE-'||nextval('public.unilabs_event_id_seq'),p_patient_id,v_waitlist.current_appointment_id,p_waitlist_entry_id,
    'offer_declined',now(),p_request_id,'system',jsonb_build_object('notification_id',p_notification_id,'requested_slot_id',v_waitlist.requested_slot_id,'appointment_unchanged',true));
  v_next_offer:=public.unilabs_offer_waitlist_for_slot(v_waitlist.requested_slot_id);
  v_response:=jsonb_build_object('request_id',p_request_id,'waitlist_entry_id',p_waitlist_entry_id,'patient_id',p_patient_id,
    'current_appointment_id',v_waitlist.current_appointment_id,'notification_id',p_notification_id,'status','declined',
    'appointment_unchanged',true,'unchanged',false,'next_offer_result',v_next_offer);
  return public.unilabs_complete_action_request(p_request_id,v_response);
end;
$$;

create or replace function public.expire_waitlist_offers(
  p_as_of timestamptz default now(),
  p_limit integer default 100
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_waitlist record;
  v_processed integer := 0;
  v_results jsonb := '[]'::jsonb;
  v_next_offer jsonb;
begin
  if p_limit<1 or p_limit>1000 then raise exception using errcode='22023', message='p_limit must be between 1 and 1000'; end if;
  for v_waitlist in
    select waitlist_entry_id,patient_id,current_appointment_id,requested_slot_id
      from public.waitlist_entries
     where status='offered' and offer_expires_at<=p_as_of
     order by offer_expires_at,waitlist_entry_id
     for update skip locked limit p_limit
  loop
    update public.waitlist_entries set status='expired',resolved_at=p_as_of where waitlist_entry_id=v_waitlist.waitlist_entry_id;
    update public.notifications set status='expired' where waitlist_entry_id=v_waitlist.waitlist_entry_id and status='pending';
    insert into public.events(event_id,patient_id,appointment_id,waitlist_entry_id,event_type,event_at,channel,details)
    values ('EVT-LIVE-'||nextval('public.unilabs_event_id_seq'),v_waitlist.patient_id,v_waitlist.current_appointment_id,v_waitlist.waitlist_entry_id,
      'offer_expired',p_as_of,'system',jsonb_build_object('requested_slot_id',v_waitlist.requested_slot_id));
    v_next_offer:=public.unilabs_offer_waitlist_for_slot(v_waitlist.requested_slot_id,p_as_of);
    v_results:=v_results||jsonb_build_array(jsonb_build_object('expired_waitlist_entry_id',v_waitlist.waitlist_entry_id,'next_offer_result',v_next_offer));
    v_processed:=v_processed+1;
  end loop;
  return jsonb_build_object('processed_count',v_processed,'processed_at',p_as_of,'results',v_results);
end;
$$;

create or replace function public.cancel_appointment(
  p_request_id text,
  p_appointment_id text
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_begin jsonb;
  v_payload jsonb;
  v_patient_id text;
  v_booking_reference text;
  v_location_id text;
  v_slot_id text;
  v_room_id text;
  v_slot_date date;
  v_start_time time;
  v_status text;
  v_waitlist record;
  v_cancelled_waitlist_count integer := 0;
  v_release_result jsonb;
  v_response jsonb;
begin
  v_payload:=jsonb_build_object('appointment_id',p_appointment_id);
  v_begin:=public.unilabs_begin_action_request(p_request_id,'CancelAppointment',v_payload);
  if (v_begin->>'replay')::boolean then return v_begin->'response'; end if;
  select a.patient_id,a.booking_reference,a.location_id,a.slot_id,a.room_id,s.slot_date,s.start_time,a.status
    into v_patient_id,v_booking_reference,v_location_id,v_slot_id,v_room_id,v_slot_date,v_start_time,v_status
    from public.appointments a join public.appointment_slots s on s.slot_id=a.slot_id
   where a.appointment_id=p_appointment_id for update of a;
  if not found then raise exception using errcode='P0002',message='Appointment was not found'; end if;
  if v_status='cancelled' then
    v_response:=jsonb_build_object('request_id',p_request_id,'appointment_id',p_appointment_id,'patient_id',v_patient_id,
      'booking_reference',v_booking_reference,'status','cancelled','unchanged',true,'cancelled_waitlist_count',0,
      'released_slot_waitlist_result',jsonb_build_object('offer_created',false,'reason','already_cancelled'));
    return public.unilabs_complete_action_request(p_request_id,v_response);
  end if;
  if v_status<>'confirmed' then raise exception using errcode='P0001',message='Only a confirmed appointment can be cancelled'; end if;
  perform 1 from public.appointment_slots where slot_id=v_slot_id for update;
  update public.appointments set status='cancelled',updated_at=now() where appointment_id=p_appointment_id;
  for v_waitlist in
    select waitlist_entry_id,patient_id,requested_slot_id,status from public.waitlist_entries
     where current_appointment_id=p_appointment_id and status in ('waiting','offered')
     order by waitlist_entry_id for update
  loop
    update public.waitlist_entries set status='cancelled',resolved_at=now() where waitlist_entry_id=v_waitlist.waitlist_entry_id;
    update public.notifications set status='cancelled' where waitlist_entry_id=v_waitlist.waitlist_entry_id and status='pending';
    insert into public.events(event_id,patient_id,appointment_id,waitlist_entry_id,event_type,event_at,request_id,channel,details)
    values ('EVT-LIVE-'||nextval('public.unilabs_event_id_seq'),v_waitlist.patient_id,p_appointment_id,v_waitlist.waitlist_entry_id,
      'waitlist_cancelled',now(),p_request_id,'system',jsonb_build_object('requested_slot_id',v_waitlist.requested_slot_id,'reason','current_appointment_cancelled'));
    perform public.unilabs_offer_waitlist_for_slot(v_waitlist.requested_slot_id);
    v_cancelled_waitlist_count:=v_cancelled_waitlist_count+1;
  end loop;
  insert into public.events(event_id,patient_id,appointment_id,event_type,event_at,request_id,channel,details)
  values ('EVT-LIVE-'||nextval('public.unilabs_event_id_seq'),v_patient_id,p_appointment_id,'appointment_cancelled',now(),p_request_id,'system',
    jsonb_build_object('booking_reference',v_booking_reference,'location_id',v_location_id,'slot_id',v_slot_id,'date',v_slot_date,'time',to_char(v_start_time,'HH24:MI'),'room_id',v_room_id));
  insert into public.events(event_id,patient_id,appointment_id,event_type,event_at,request_id,channel,details)
  values ('EVT-LIVE-'||nextval('public.unilabs_event_id_seq'),v_patient_id,p_appointment_id,'slot_released',now(),p_request_id,'system',
    jsonb_build_object('location_id',v_location_id,'slot_id',v_slot_id,'date',v_slot_date,'time',to_char(v_start_time,'HH24:MI'),'room_id',v_room_id));
  v_release_result:=public.unilabs_offer_waitlist_for_slot(v_slot_id);
  v_response:=jsonb_build_object('request_id',p_request_id,'appointment_id',p_appointment_id,'patient_id',v_patient_id,
    'booking_reference',v_booking_reference,'status','cancelled','unchanged',false,'cancelled_waitlist_count',v_cancelled_waitlist_count,
    'released_slot_waitlist_result',v_release_result);
  return public.unilabs_complete_action_request(p_request_id,v_response);
end;
$$;

create or replace function public.cancel_appointment(p_appointment_id text)
returns jsonb
language plpgsql
security invoker
set search_path = public, extensions
as $$
begin
  return public.cancel_appointment('legacy-cancel-'||extensions.gen_random_uuid()::text,p_appointment_id);
end;
$$;

create or replace function public.reset_demo_scenario(
  p_scenario_date date default ((now() at time zone 'Europe/Amsterdam')::date + 1),
  p_generated_days integer default 7,
  p_offer_hold_minutes integer default 5
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_slots integer;
  v_appointments integer;
  v_waitlists integer;
  v_now timestamptz:=now();
begin
  if p_scenario_date is null then raise exception using errcode='22023',message='scenario_date is required'; end if;
  if p_generated_days<1 or p_generated_days>31 then raise exception using errcode='22023',message='generated_days must be between 1 and 31'; end if;
  if p_offer_hold_minutes<1 or p_offer_hold_minutes>60 then raise exception using errcode='22023',message='offer_hold_minutes must be between 1 and 60'; end if;
  perform pg_advisory_xact_lock(hashtext('unilabs_reset_demo_scenario'));
  if (select count(*) from public.locations where location_id in ('LOC-AMS','LOC-RTM','LOC-UTR'))<>3 then
    raise exception using errcode='P0002',message='Required demo locations are missing';
  end if;
  if (select count(*) from public.patients where patient_id in (
      'PAT-1001','PAT-1002','PAT-1003','PAT-1004','PAT-1005',
      'PAT-BG-U10-01','PAT-BG-U10-02','PAT-BG-U10-03','PAT-BG-U10-04',
      'PAT-BG-R15-01','PAT-BG-R15-02','PAT-BG-R15-03','PAT-BG-R15-04','PAT-BG-R15-05'))<>14 then
    raise exception using errcode='P0002',message='Required demo patients are missing';
  end if;
  if exists (select 1 from public.locations l left join public.rooms r on r.location_id=l.location_id
      where l.location_id in ('LOC-AMS','LOC-RTM','LOC-UTR') group by l.location_id having count(r.room_id)<>5) then
    raise exception using errcode='P0001',message='Each demo location must have exactly five rooms';
  end if;
  delete from public.events;
  delete from public.notifications;
  delete from public.waitlist_entries;
  delete from public.action_requests;
  delete from public.appointments;
  delete from public.appointment_slots;
  delete from public.demo_scenarios;
  insert into public.demo_scenarios(scenario_key,scenario_date,generated_days,offer_hold_minutes,reset_at)
  values ('default',p_scenario_date,p_generated_days,p_offer_hold_minutes,v_now);
  insert into public.appointment_slots(slot_id,location_id,slot_date,start_time,bookable,created_at)
  select 'SLOT-'||replace(l.location_id,'LOC-','')||'-D'||d.day_offset::text||'-'||to_char(t.start_time,'HH24MI'),
    l.location_id,p_scenario_date+d.day_offset,t.start_time,(t.start_time<>time '12:00'),v_now
  from public.locations l cross join generate_series(0,p_generated_days-1) as d(day_offset)
  cross join (values (time '09:00'),(time '10:00'),(time '11:00'),(time '12:00'),(time '13:00'),(time '14:00'),(time '15:00'),(time '16:00'),(time '17:00')) as t(start_time)
  where l.location_id in ('LOC-AMS','LOC-RTM','LOC-UTR');
  get diagnostics v_slots=row_count;
  insert into public.appointments(appointment_id,patient_id,booking_reference,location_id,slot_id,room_id,status,created_at,updated_at)
  select seed.appointment_id,seed.patient_id,seed.booking_reference,seed.location_id,s.slot_id,r.room_id,'confirmed',v_now,v_now
  from (values
      ('APT-BG-U10-01'::text,'PAT-BG-U10-01'::text,'UNI-100001'::text,'LOC-UTR'::text,time '10:00',1::smallint),
      ('APT-BG-U10-02','PAT-BG-U10-02','UNI-100002','LOC-UTR',time '10:00',2::smallint),
      ('APT-BG-U10-03','PAT-BG-U10-03','UNI-100003','LOC-UTR',time '10:00',3::smallint),
      ('APT-BG-U10-04','PAT-BG-U10-04','UNI-100004','LOC-UTR',time '10:00',4::smallint),
      ('APT-BG-R15-01','PAT-BG-R15-01','UNI-100005','LOC-RTM',time '15:00',1::smallint),
      ('APT-BG-R15-02','PAT-BG-R15-02','UNI-100006','LOC-RTM',time '15:00',2::smallint),
      ('APT-BG-R15-03','PAT-BG-R15-03','UNI-100007','LOC-RTM',time '15:00',3::smallint),
      ('APT-BG-R15-04','PAT-BG-R15-04','UNI-100008','LOC-RTM',time '15:00',4::smallint),
      ('APT-BG-R15-05','PAT-BG-R15-05','UNI-100009','LOC-RTM',time '15:00',5::smallint),
      ('APT-C-1004','PAT-1004','UNI-100010','LOC-AMS',time '13:00',1::smallint),
      ('APT-E-1005','PAT-1005','UNI-100011','LOC-RTM',time '16:00',1::smallint)
  ) as seed(appointment_id,patient_id,booking_reference,location_id,start_time,room_order)
  join public.appointment_slots s on s.location_id=seed.location_id and s.slot_date=p_scenario_date and s.start_time=seed.start_time
  join public.rooms r on r.location_id=seed.location_id and r.room_order=seed.room_order;
  get diagnostics v_appointments=row_count;
  insert into public.waitlist_entries(waitlist_entry_id,patient_id,location_id,requested_slot_id,current_appointment_id,status,created_at)
  select 'WL-E-1005','PAT-1005','LOC-RTM',s.slot_id,'APT-E-1005','waiting',v_now
  from public.appointment_slots s where s.location_id='LOC-RTM' and s.slot_date=p_scenario_date and s.start_time=time '15:00';
  get diagnostics v_waitlists=row_count;
  perform setval('public.unilabs_booking_reference_seq',100011,true);
  perform setval('public.unilabs_appointment_id_seq',200000,true);
  perform setval('public.unilabs_waitlist_id_seq',200000,true);
  perform setval('public.unilabs_notification_id_seq',200000,true);
  perform setval('public.unilabs_event_id_seq',200000,true);
  insert into public.events(event_id,event_type,event_at,channel,details)
  values ('EVT-LIVE-'||nextval('public.unilabs_event_id_seq'),'demo_reset',v_now,'system',
    jsonb_build_object('scenario_date',p_scenario_date,'generated_days',p_generated_days,'offer_hold_minutes',p_offer_hold_minutes,
      'slot_count',v_slots,'appointment_count',v_appointments,'waitlist_count',v_waitlists));
  if v_slots<>27*p_generated_days then raise exception using errcode='P0001',message='Unexpected slot count after reset'; end if;
  if v_appointments<>11 then raise exception using errcode='P0001',message='Unexpected baseline appointment count after reset'; end if;
  if v_waitlists<>1 then raise exception using errcode='P0001',message='Unexpected baseline waitlist count after reset'; end if;
  return jsonb_build_object('scenario_key','default','scenario_date',p_scenario_date,'generated_days',p_generated_days,
    'offer_hold_minutes',p_offer_hold_minutes,'slot_count',v_slots,'appointment_count',v_appointments,'waitlist_count',v_waitlists,'reset_at',v_now);
end;
$$;

drop function if exists public.unilabs_queue_waitlist_notifications(text,text,text,text,text,text,date,time,timestamptz,text);
drop table if exists public.patient_channel_identities;

alter table public.action_requests
  drop constraint if exists action_requests_completion_check,
  drop constraint if exists action_requests_status_check,
  drop constraint if exists action_requests_success_response_check,
  drop column if exists status;
alter table public.action_requests
  add constraint action_requests_completion_check
  check ((response is null and completed_at is null) or (response is not null and completed_at is not null));
drop index if exists public.action_requests_created_at_idx;

alter table public.demo_scenarios
  drop constraint if exists demo_scenarios_status_check,
  drop column if exists status,
  drop column if exists metadata;

alter table public.notifications
  drop constraint if exists notifications_channel_check,
  drop constraint if exists notifications_delivery_attempts_check,
  drop constraint if exists notifications_response_status_check,
  drop constraint if exists notifications_response_time_check,
  drop constraint if exists notifications_status_check,
  drop constraint if exists notifications_type_check,
  drop constraint if exists notifications_waitlist_entry_id_fkey;
drop index if exists public.notifications_pending_channel_idx;
drop index if exists public.notifications_waitlist_channel_status_idx;
alter table public.notifications
  drop column if exists channel,
  drop column if exists message,
  drop column if exists sent_at,
  drop column if exists notification_type,
  drop column if exists response_status,
  drop column if exists delivery_attempts;
alter table public.notifications
  alter column waitlist_entry_id set not null,
  add constraint notifications_status_check check (status in ('pending','responded','cancelled','expired')),
  add constraint notifications_response_time_check check ((status='responded' and responded_at is not null) or (status<>'responded' and responded_at is null)),
  add constraint notifications_waitlist_entry_id_fkey foreign key (waitlist_entry_id) references public.waitlist_entries(waitlist_entry_id) on delete cascade,
  add constraint notifications_waitlist_entry_id_key unique (waitlist_entry_id);

alter table public.events drop constraint if exists events_event_type_check;
alter table public.events add constraint events_event_type_check check (event_type in (
  'availability_checked','appointment_booked','waitlist_joined','appointment_rescheduled','appointment_cancelled','waitlist_cancelled',
  'slot_released','waitlist_match_found','notification_queued','patient_notified','offer_accepted','offer_declined','offer_expired','demo_reset'
));

alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from public, anon, authenticated;
revoke usage, create on schema public from public, anon, authenticated;
revoke all on table public.action_requests, public.demo_scenarios, public.notifications from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
grant select,insert,update,delete on table public.action_requests,public.demo_scenarios,public.notifications to service_role;
grant execute on function public.unilabs_queue_waitlist_notification(text,text,text,text,text,text,date,time,timestamptz,text) to service_role;
grant execute on function public.unilabs_offer_waitlist_for_slot(text,timestamptz) to service_role;
grant execute on function public.unilabs_offer_waitlist_for_slot(text) to service_role;
grant execute on function public.expire_waitlist_offers(timestamptz,integer) to service_role;
grant execute on function public.decline_waitlist_offer(text,text,text,text) to service_role;
grant execute on function public.reset_demo_scenario(date,integer,integer) to service_role;