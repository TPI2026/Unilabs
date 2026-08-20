create or replace function public.resolve_patient_by_phone(p_phone_number text)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_patient public.patients%rowtype;
begin
  if p_phone_number is null or btrim(p_phone_number) = '' then
    raise exception using errcode = '22023', message = 'phone_number must be a non-empty string';
  end if;

  select * into v_patient
  from public.patients
  where phone_number = p_phone_number
  limit 1;

  if not found then
    return jsonb_build_object(
      'found', false,
      'patient_id', null,
      'first_name', null,
      'last_name', null,
      'phone_number', p_phone_number
    );
  end if;

  return jsonb_build_object(
    'found', true,
    'patient_id', v_patient.patient_id,
    'first_name', v_patient.first_name,
    'last_name', v_patient.last_name,
    'phone_number', v_patient.phone_number
  );
end;
$$;

revoke execute on function public.resolve_patient_by_phone(text) from public, anon, authenticated;
grant execute on function public.resolve_patient_by_phone(text) to service_role;
