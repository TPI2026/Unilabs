'use strict';
const { createRpcHandler, apiError } = require('../lib/supabase-rpc');

module.exports = createRpcHandler({
  action: 'RescheduleAppointment',
  rpcName: 'reschedule_appointment',
  required: ['request_id', 'appointment_id', 'new_location_id', 'new_slot_date', 'new_start_time'],
  optional: ['waitlist_entry_id', 'offer_token'],
  validate: (body) => {
    const hasWaitlistEntry = Boolean(body.waitlist_entry_id);
    const hasOfferToken = Boolean(body.offer_token);
    if (hasWaitlistEntry !== hasOfferToken) {
      throw apiError('waitlist_entry_id and offer_token must be provided together', 'invalid_parameter', 400);
    }
  },
  map: (body) => ({
    p_request_id: body.request_id,
    p_appointment_id: body.appointment_id,
    p_new_location_id: body.new_location_id,
    p_new_slot_date: body.new_slot_date,
    p_new_start_time: body.new_start_time,
    p_waitlist_entry_id: body.waitlist_entry_id ?? null,
    p_offer_token: body.offer_token ?? null,
  }),
});
