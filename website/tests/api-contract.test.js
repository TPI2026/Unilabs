'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const bookAppointment = require('../api/book-appointment');
const findAppointment = require('../api/find-appointment');
const rescheduleAppointment = require('../api/reschedule-appointment');
const declineWaitlistOffer = require('../api/decline-waitlist-offer');

process.env.UNILABS_API_KEY = 'test-api-key';
process.env.SUPABASE_URL = 'https://example.supabase.co';
process.env.SUPABASE_SECRET_KEY = 'sb_secret_test';

function responseMock() {
  return {
    statusCode: null,
    headers: {},
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    setHeader(name, value) {
      this.headers[name.toLowerCase()] = value;
      return this;
    },
    end(value) {
      this.body = value;
    },
  };
}

function requestMock(body, headers = {}, method = 'POST') {
  return {
    method,
    body,
    headers: {
      'x-api-key': 'test-api-key',
      ...headers,
    },
  };
}

async function invoke(handler, body, rpcResult, options = {}) {
  const originalFetch = global.fetch;
  let captured = null;
  global.fetch = async (url, init) => {
    captured = { url, init, body: JSON.parse(init.body) };
    const status = options.status || 200;
    const responseBody = options.responseBody === undefined ? rpcResult : options.responseBody;
    return {
      ok: status >= 200 && status < 300,
      status,
      text: async () => JSON.stringify(responseBody),
    };
  };

  const response = responseMock();
  try {
    await handler(requestMock(body, options.headers, options.method || 'POST'), response);
  } finally {
    global.fetch = originalFetch;
  }

  return {
    response,
    json: JSON.parse(response.body),
    captured,
  };
}

test('BookAppointment passes request_id to Supabase and returns no-store response', async () => {
  const result = await invoke(bookAppointment, {
    request_id: 'int-1-book-1',
    patient_id: 'PAT-1001',
    location_id: 'LOC-UTR',
    slot_date: '2026-08-19',
    start_time: '10:00',
  }, {
    request_id: 'int-1-book-1',
    appointment_id: 'APT-LIVE-200001',
    status: 'confirmed',
  });

  assert.equal(result.response.statusCode, 200);
  assert.equal(result.response.headers['cache-control'], 'private, no-store');
  assert.equal(result.response.headers['x-request-id'], 'int-1-book-1');
  assert.equal(result.json.request_id, 'int-1-book-1');
  assert.deepEqual(result.captured.body, {
    p_request_id: 'int-1-book-1',
    p_patient_id: 'PAT-1001',
    p_location_id: 'LOC-UTR',
    p_slot_date: '2026-08-19',
    p_start_time: '10:00',
  });
});

test('write action rejects missing request_id before calling Supabase', async () => {
  const originalFetch = global.fetch;
  let called = false;
  global.fetch = async () => {
    called = true;
    throw new Error('should not run');
  };

  const response = responseMock();
  try {
    await bookAppointment(requestMock({
      patient_id: 'PAT-1001',
      location_id: 'LOC-UTR',
      slot_date: '2026-08-19',
      start_time: '10:00',
    }), response);
  } finally {
    global.fetch = originalFetch;
  }

  const json = JSON.parse(response.body);
  assert.equal(response.statusCode, 400);
  assert.equal(json.error.code, 'missing_parameter');
  assert.equal(called, false);
});

test('FindAppointment remains a read action without idempotency input', async () => {
  const result = await invoke(findAppointment, {
    patient_id: 'PAT-1004',
  }, {
    found: true,
    ambiguous: false,
    count: 1,
    appointment: { appointment_id: 'APT-C-1004' },
  }, { headers: { 'x-request-id': 'trace-find-1' } });

  assert.equal(result.response.statusCode, 200);
  assert.equal(result.json.request_id, 'trace-find-1');
  assert.deepEqual(result.captured.body, {
    p_patient_id: 'PAT-1004',
    p_booking_reference: null,
  });
});

test('waitlist acceptance requires waitlist_entry_id and offer_token together', async () => {
  const result = await invoke(rescheduleAppointment, {
    request_id: 'int-2-accept-1',
    appointment_id: 'APT-LIVE-200002',
    new_location_id: 'LOC-UTR',
    new_slot_date: '2026-08-19',
    new_start_time: '10:00',
    waitlist_entry_id: 'WL-LIVE-200001',
  }, null);

  assert.equal(result.response.statusCode, 400);
  assert.equal(result.json.request_id, 'int-2-accept-1');
  assert.equal(result.json.error.code, 'invalid_parameter');
  assert.equal(result.captured, null);
});

test('Supabase business errors are mapped to stable API errors without details or hints', async () => {
  const result = await invoke(bookAppointment, {
    request_id: 'int-3-book-1',
    patient_id: 'PAT-1002',
    location_id: 'LOC-UTR',
    slot_date: '2026-08-19',
    start_time: '10:00',
  }, null, {
    status: 400,
    responseBody: {
      code: 'P0001',
      message: 'Requested slot is fully booked',
      details: 'internal detail',
      hint: 'internal hint',
    },
  });

  assert.equal(result.response.statusCode, 409);
  assert.equal(result.json.request_id, 'int-3-book-1');
  assert.deepEqual(result.json.error, {
    code: 'slot_fully_booked',
    message: 'The requested slot is fully booked',
    retryable: false,
  });
  assert.equal('details' in result.json.error, false);
  assert.equal('hint' in result.json.error, false);
});

test('DeclineWaitlistOffer maps the complete decline contract', async () => {
  const result = await invoke(declineWaitlistOffer, {
    request_id: 'int-4-decline-1',
    patient_id: 'PAT-1002',
    waitlist_entry_id: 'WL-LIVE-200001',
    notification_id: 'NOT-LIVE-200001',
  }, {
    request_id: 'int-4-decline-1',
    status: 'declined',
    appointment_unchanged: true,
  });

  assert.equal(result.response.statusCode, 200);
  assert.deepEqual(result.captured.body, {
    p_request_id: 'int-4-decline-1',
    p_patient_id: 'PAT-1002',
    p_waitlist_entry_id: 'WL-LIVE-200001',
    p_notification_id: 'NOT-LIVE-200001',
  });
});

test('unauthorized requests fail before Supabase is called', async () => {
  const originalFetch = global.fetch;
  let called = false;
  global.fetch = async () => {
    called = true;
    throw new Error('should not run');
  };

  const response = responseMock();
  try {
    await bookAppointment({
      method: 'POST',
      headers: { 'x-api-key': 'wrong-key' },
      body: {
        request_id: 'int-5-book-1',
        patient_id: 'PAT-1001',
        location_id: 'LOC-UTR',
        slot_date: '2026-08-19',
        start_time: '10:00',
      },
    }, response);
  } finally {
    global.fetch = originalFetch;
  }

  const json = JSON.parse(response.body);
  assert.equal(response.statusCode, 401);
  assert.equal(json.error.code, 'unauthorized');
  assert.equal(called, false);
});
