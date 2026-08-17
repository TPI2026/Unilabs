'use strict';
const { createRpcHandler } = require('../lib/supabase-rpc');

module.exports = createRpcHandler({
  action: 'CheckAvailability',
  rpcName: 'check_availability',
  required: ['location_id', 'slot_date', 'start_time'],
  optional: ['patient_id'],
  map: (body) => ({
    p_location_id: body.location_id,
    p_slot_date: body.slot_date,
    p_start_time: body.start_time,
    p_patient_id: body.patient_id ?? null,
  }),
});
