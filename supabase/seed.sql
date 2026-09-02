-- Idempotent fictional reference data for the Unilabs AI Appointment Demo.
-- Run after the versioned migrations. The final statement resets the active
-- scenario to tomorrow in Europe/Amsterdam and generates seven calendar days.

insert into public.locations(location_id, city, timezone)
values
  ('LOC-AMS', 'Amsterdam', 'Europe/Amsterdam'),
  ('LOC-UTR', 'Utrecht', 'Europe/Amsterdam'),
  ('LOC-ENS', 'Enschede', 'Europe/Amsterdam')
on conflict (location_id) do update
set city = excluded.city,
    timezone = excluded.timezone;

insert into public.rooms(room_id, location_id, room_name, room_order)
values
  ('ROOM-AMS-01-DAMRAK', 'LOC-AMS', 'Damrak', 1),
  ('ROOM-AMS-02-HERENGRACHT', 'LOC-AMS', 'Herengracht', 2),
  ('ROOM-AMS-03-KEIZERSGRACHT', 'LOC-AMS', 'Keizersgracht', 3),
  ('ROOM-AMS-04-PRINSENGRACHT', 'LOC-AMS', 'Prinsengracht', 4),
  ('ROOM-AMS-05-WETERINGSCHANS', 'LOC-AMS', 'Weteringschans', 5),
  ('ROOM-UTR-01-OUDEGRACHT', 'LOC-UTR', 'Oudegracht', 1),
  ('ROOM-UTR-02-NEUDE', 'LOC-UTR', 'Neude', 2),
  ('ROOM-UTR-03-BILTSTRAAT', 'LOC-UTR', 'Biltstraat', 3),
  ('ROOM-UTR-04-MALIEBAAN', 'LOC-UTR', 'Maliebaan', 4),
  ('ROOM-UTR-05-CROESELAAN', 'LOC-UTR', 'Croeselaan', 5),
  ('ROOM-ENS-01-LANGESTRAAT', 'LOC-ENS', 'Langestraat', 1),
  ('ROOM-ENS-02-DEURNINGERSTRAAT', 'LOC-ENS', 'Deurningerstraat', 2),
  ('ROOM-ENS-03-HENGELOSESTRAAT', 'LOC-ENS', 'Hengelosestraat', 3),
  ('ROOM-ENS-04-KUIPERSDIJK', 'LOC-ENS', 'Kuipersdijk', 4),
  ('ROOM-ENS-05-OLDENZAALSESTRAAT', 'LOC-ENS', 'Oldenzaalsestraat', 5)
on conflict (room_id) do update
set location_id = excluded.location_id,
    room_name = excluded.room_name,
    room_order = excluded.room_order;

insert into public.patients(
  patient_id, first_name, last_name, email, phone_number,
  street, house_number, house_number_addition, postcode, city, country, demo_role
)
values
  ('PAT-1001', 'Emma', 'de Jong', 'emma.dejong@example.com', 'DEMO-NL-1001', 'Stadhuisbrug', '1', null, '3511 KP', 'Utrecht', 'Netherlands', 'central_story_patient_a'),
  ('PAT-1002', 'Sophie', 'van Dijk', 'sophie.vandijk@example.com', 'DEMO-NL-1002', 'Neude', '11', null, '3512 AE', 'Utrecht', 'Netherlands', 'central_story_patient_b'),
  ('PAT-1003', 'Liam', 'de Vries', 'liam.devries@example.com', 'DEMO-NL-1003', 'Langestraat', '40', null, '7511 HC', 'Enschede', 'Netherlands', 'background_capacity'),
  ('PAT-1004', 'Noor', 'Bakker', 'noor.bakker@example.com', 'DEMO-NL-1004', 'Amstel', '1', null, '1011 PN', 'Amsterdam', 'Netherlands', 'existing_appointment_patient'),
  ('PAT-1005', 'Daan', 'Meijer', 'daan.meijer@example.com', 'DEMO-NL-1005', 'Hengelosestraat', '110', null, '7514 AJ', 'Enschede', 'Netherlands', 'existing_waitlist_patient'),
  ('PAT-1006', 'Max', 'Mustermann', 'max.mustermann.demo@example.com', '+4917646752711', 'Musterstraße', '12', null, '10115', 'Berlin', 'Germany', 'happy_path_patient'),
  ('PAT-BG-U10-01', 'Bram', 'Smit', 'bg.u10.01@example.com', 'DEMO-BG-U10-01', null, null, null, null, null, 'Netherlands', 'background_capacity'),
  ('PAT-BG-U10-02', 'Eva', 'de Boer', 'bg.u10.02@example.com', 'DEMO-BG-U10-02', null, null, null, null, null, 'Netherlands', 'background_capacity'),
  ('PAT-BG-U10-03', 'Lars', 'Visser', 'bg.u10.03@example.com', 'DEMO-BG-U10-03', null, null, null, null, null, 'Netherlands', 'background_capacity'),
  ('PAT-BG-U10-04', 'Mila', 'Mulder', 'bg.u10.04@example.com', 'DEMO-BG-U10-04', null, null, null, null, null, 'Netherlands', 'background_capacity'),
  ('PAT-BG-R15-01', 'Jan', 'Vos', 'bg.r15.01@example.com', 'DEMO-BG-R15-01', null, null, null, null, null, 'Netherlands', 'background_capacity'),
  ('PAT-BG-R15-02', 'Sanne', 'Dekker', 'bg.r15.02@example.com', 'DEMO-BG-R15-02', null, null, null, null, null, 'Netherlands', 'background_capacity'),
  ('PAT-BG-R15-03', 'Koen', 'Bos', 'bg.r15.03@example.com', 'DEMO-BG-R15-03', null, null, null, null, null, 'Netherlands', 'background_capacity'),
  ('PAT-BG-R15-04', 'Evi', 'Peters', 'bg.r15.04@example.com', 'DEMO-BG-R15-04', null, null, null, null, null, 'Netherlands', 'background_capacity'),
  ('PAT-BG-R15-05', 'Niels', 'Hendriks', 'bg.r15.05@example.com', 'DEMO-BG-R15-05', null, null, null, null, null, 'Netherlands', 'background_capacity')
on conflict (patient_id) do update
set first_name = excluded.first_name,
    last_name = excluded.last_name,
    email = excluded.email,
    phone_number = excluded.phone_number,
    street = excluded.street,
    house_number = excluded.house_number,
    house_number_addition = excluded.house_number_addition,
    postcode = excluded.postcode,
    city = excluded.city,
    country = excluded.country,
    demo_role = excluded.demo_role;

select public.reset_demo_scenario(
  (now() at time zone 'Europe/Amsterdam')::date + 1,
  7,
  5
);
