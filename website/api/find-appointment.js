'use strict';
const { createRpcHandler } = require('../lib/supabase-rpc');

module.exports = createRpcHandler({
  action: 'FindAppointment',
  rpcName: 'find_appointment',
  required: ['patient_id'],
  optional: ['booking_reference'],
  map: (body) => ({
    p_patient_id: body.patient_id,
    p_booking_reference: body.booking_reference ?? null,
  }),
});
