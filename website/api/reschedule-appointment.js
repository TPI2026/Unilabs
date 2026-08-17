'use strict';
const { createRpcHandler } = require('../lib/supabase-rpc');

module.exports = createRpcHandler({
  action: 'RescheduleAppointment',
  rpcName: 'reschedule_appointment',
  required: ['appointment_id', 'new_location_id', 'new_slot_date', 'new_start_time'],
  optional: ['waitlist_entry_id'],
  map: (body) => ({
    p_appointment_id: body.appointment_id,
    p_new_location_id: body.new_location_id,
    p_new_slot_date: body.new_slot_date,
    p_new_start_time: body.new_start_time,
    p_waitlist_entry_id: body.waitlist_entry_id ?? null,
  }),
});
