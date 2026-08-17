'use strict';
const { createRpcHandler } = require('../lib/supabase-rpc');

module.exports = createRpcHandler({
  action: 'CancelAppointment',
  rpcName: 'cancel_appointment',
  required: ['appointment_id'],
  map: (body) => ({
    p_appointment_id: body.appointment_id,
  }),
});
