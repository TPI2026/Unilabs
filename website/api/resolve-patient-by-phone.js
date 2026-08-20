'use strict';
const { createRpcHandler } = require('../lib/supabase-rpc');

module.exports = createRpcHandler({
  action: 'ResolvePatientByPhone',
  rpcName: 'resolve_patient_by_phone',
  required: ['mobile_number'],
  map: (body) => ({
    p_phone_number: body.mobile_number,
  }),
});
