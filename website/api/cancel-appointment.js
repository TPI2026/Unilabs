'use strict';
const { createRpcHandler } = require('../lib/supabase-rpc');

module.exports = createRpcHandler({
  action: 'CancelAppointment',
  rpcName: 'cancel_appointment',
  required: ['request_id', 'appointment_id'],
  map: (body) => ({
    p_request_id: body.request_id,
    p_appointment_id: body.appointment_id,
  }),
});
