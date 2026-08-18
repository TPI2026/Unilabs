'use strict';
const { createRpcHandler } = require('../lib/supabase-rpc');

module.exports = createRpcHandler({
  action: 'DeclineWaitlistOffer',
  rpcName: 'decline_waitlist_offer',
  required: ['request_id', 'patient_id', 'waitlist_entry_id', 'notification_id'],
  map: (body) => ({
    p_request_id: body.request_id,
    p_patient_id: body.patient_id,
    p_waitlist_entry_id: body.waitlist_entry_id,
    p_notification_id: body.notification_id,
  }),
});
