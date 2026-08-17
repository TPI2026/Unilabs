'use strict';
const { createRpcHandler } = require('../lib/supabase-rpc');

module.exports = createRpcHandler({
  action: 'BookAppointment',
  rpcName: 'book_appointment',
  required: ['patient_id', 'location_id', 'slot_date', 'start_time'],
  map: (body) => ({
    p_patient_id: body.patient_id,
    p_location_id: body.location_id,
    p_slot_date: body.slot_date,
    p_start_time: body.start_time,
  }),
});
