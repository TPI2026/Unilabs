-- Reset the complete fictional demo state transactionally.
-- Replace the first argument with any desired scenario date.
select public.reset_demo_scenario(
  (now() at time zone 'Europe/Amsterdam')::date + 1,
  7,
  5
);
