'use strict';
const { createRpcHandler } = require('../lib/supabase-rpc');

module.exports = createRpcHandler({
  action: 'JoinWaitlist',
  rpcName: 'join_waitlist',
  required: ['request_id', 'patient_id', 'location_id', 'slot_date', 'start_time'],
  optional: ['current_appointment_id'],
  map: (body) => ({
    p_request_id: body.request_id,
    p_patient_id: body.patient_id,
    p_location_id: body.location_id,
    p_slot_date: body.slot_date,
    p_start_time: body.start_time,
    p_current_appointment_id: body.current_appointment_id ?? null,
  }),
});
