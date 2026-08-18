'use strict';

const crypto = require('node:crypto');

const RPC_TIMEOUT_MS = 8000;

function getHeader(request, name) {
  const value = request.headers?.[name] ?? request.headers?.[name.toLowerCase()];
  return Array.isArray(value) ? value[0] : value;
}

function correlationId(request) {
  const supplied = getHeader(request, 'x-request-id');
  if (typeof supplied === 'string' && supplied.trim() !== '') return supplied.trim();
  return crypto.randomUUID();
}

function sendJson(response, statusCode, payload, requestId) {
  response.status(statusCode);
  response.setHeader('Content-Type', 'application/json; charset=utf-8');
  response.setHeader('Cache-Control', 'private, no-store');
  if (requestId) response.setHeader('x-request-id', requestId);
  response.end(JSON.stringify(payload));
}

function apiError(message, code, statusCode, retryable = false) {
  const error = new Error(message);
  error.code = code;
  error.statusCode = statusCode;
  error.retryable = retryable;
  return error;
}

function parseBody(request) {
  if (request.body == null || request.body === '') return {};
  if (typeof request.body === 'object') return request.body;
  if (typeof request.body === 'string') {
    try {
      return JSON.parse(request.body);
    } catch {
      throw apiError('Request body must be valid JSON', 'invalid_json', 400);
    }
  }
  throw apiError('Unsupported request body', 'invalid_body', 400);
}

function requireApiKey(request) {
  const expected = process.env.UNILABS_API_KEY;
  if (!expected) {
    throw apiError('Server configuration error', 'server_configuration_error', 500, true);
  }

  const provided = getHeader(request, 'x-api-key');
  if (!provided || provided !== expected) {
    throw apiError('Unauthorized', 'unauthorized', 401);
  }
}

function validateField(name, value) {
  if (value == null) return;
  if (typeof value !== 'string' || value.trim() === '') {
    throw apiError(`${name} must be a non-empty string`, 'invalid_parameter', 400);
  }

  if (value.length > 256) {
    throw apiError(`${name} is too long`, 'invalid_parameter', 400);
  }

  if (name.endsWith('_date') && !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw apiError(`${name} must use YYYY-MM-DD`, 'invalid_parameter', 400);
  }

  if (name.endsWith('_time') && !/^\d{2}:\d{2}(:\d{2})?$/.test(value)) {
    throw apiError(`${name} must use HH:MM or HH:MM:SS`, 'invalid_parameter', 400);
  }
}

function mapSupabaseError(code, message, statusCode) {
  const text = String(message || '').toLowerCase();

  if (code === '22023') return apiError('Invalid request', 'invalid_request', 400);
  if (code === '23505' && text.includes('request_id')) {
    return apiError('request_id already exists with a different action or payload', 'idempotency_conflict', 409);
  }
  if (code === '55P03') return apiError('The request is already being processed', 'request_in_progress', 409, true);

  if (text.includes('patient') && text.includes('not found')) return apiError('Patient not found', 'patient_not_found', 404);
  if (text.includes('appointment') && text.includes('not found')) return apiError('Appointment not found', 'appointment_not_found', 404);
  if (text.includes('waitlist entry') && text.includes('not found')) return apiError('Waitlist entry not found', 'waitlist_not_found', 404);
  if (text.includes('notification') && text.includes('not found')) return apiError('Notification not found', 'notification_not_found', 404);
  if (text.includes('slot') && text.includes('does not exist')) return apiError('Appointment slot not found', 'slot_not_found', 404);
  if (text.includes('fully booked') || text.includes('no free room')) return apiError('The requested slot is fully booked', 'slot_fully_booked', 409);
  if (text.includes('not bookable')) return apiError('The requested slot is not bookable', 'slot_not_bookable', 409);
  if (text.includes('currently available') && text.includes('book it instead')) {
    return apiError('The requested slot is available and should be booked instead', 'slot_available', 409);
  }
  if (text.includes('waitlist offer') && (text.includes('invalid') || text.includes('expired') || text.includes('not active'))) {
    return apiError('The waitlist offer is invalid or expired', 'offer_invalid_or_expired', 409);
  }
  if (text.includes('only a confirmed appointment can be cancelled')) {
    return apiError('The appointment cannot be cancelled', 'appointment_not_cancellable', 409);
  }
  if (text.includes('does not belong to the patient') || text.includes('not confirmed')) {
    return apiError('The appointment or waitlist entry is not valid for this patient', 'invalid_patient_context', 409);
  }

  if (code === 'P0002') return apiError('Requested record not found', 'not_found', 404);
  if (code === 'P0001') return apiError('The request violates an appointment business rule', 'business_rule_violation', 409);
  if (code && String(code).startsWith('PGRST')) return apiError('Backend configuration error', 'backend_configuration_error', 502, true);

  if (statusCode >= 500) return apiError('Temporary backend error', 'temporary_backend_error', 502, true);
  return apiError('Backend request failed', 'backend_error', 502, true);
}

async function callSupabaseRpc(rpcName, params) {
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseServerKey = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !supabaseServerKey) {
    throw apiError('Server configuration error', 'server_configuration_error', 500, true);
  }

  const headers = {
    apikey: supabaseServerKey,
    'Content-Type': 'application/json',
    Accept: 'application/json',
  };

  if (!supabaseServerKey.startsWith('sb_secret_')) {
    headers.Authorization = `Bearer ${supabaseServerKey}`;
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), RPC_TIMEOUT_MS);

  try {
    const rpcResponse = await fetch(`${supabaseUrl.replace(/\/$/, '')}/rest/v1/rpc/${rpcName}`, {
      method: 'POST',
      headers,
      body: JSON.stringify(params),
      signal: controller.signal,
    });

    const raw = await rpcResponse.text();
    let data = null;
    if (raw) {
      try {
        data = JSON.parse(raw);
      } catch {
        data = null;
      }
    }

    if (!rpcResponse.ok) {
      throw mapSupabaseError(data?.code, data?.message, rpcResponse.status);
    }

    return data;
  } catch (error) {
    if (error?.name === 'AbortError') {
      throw apiError('Backend request timed out', 'backend_timeout', 504, true);
    }
    if (error?.code && error?.statusCode) throw error;
    throw apiError('Temporary backend error', 'temporary_backend_error', 502, true);
  } finally {
    clearTimeout(timer);
  }
}

function createRpcHandler({ action, rpcName, required = [], optional = [], map, validate }) {
  return async function handler(request, response) {
    const traceId = correlationId(request);

    if (request.method !== 'POST') {
      response.setHeader('Allow', 'POST');
      return sendJson(response, 405, {
        ok: false,
        action,
        request_id: traceId,
        error: { code: 'method_not_allowed', message: 'Use POST', retryable: false },
      }, traceId);
    }

    try {
      requireApiKey(request);
      const body = parseBody(request);

      for (const field of required) {
        if (body[field] == null || body[field] === '') {
          throw apiError(`Missing required field: ${field}`, 'missing_parameter', 400);
        }
      }

      for (const field of [...required, ...optional]) {
        validateField(field, body[field]);
      }

      if (validate) validate(body);

      const params = map(body);
      const data = await callSupabaseRpc(rpcName, params);
      const requestId = data?.request_id || body.request_id || traceId;

      return sendJson(response, 200, {
        ok: true,
        action,
        request_id: requestId,
        data,
      }, requestId);
    } catch (error) {
      const requestId = error?.requestId || traceId;
      return sendJson(response, error.statusCode || 500, {
        ok: false,
        action,
        request_id: requestId,
        error: {
          code: error.code || 'internal_error',
          message: error.message || 'Internal server error',
          retryable: Boolean(error.retryable),
        },
      }, requestId);
    }
  };
}

module.exports = { createRpcHandler, apiError, mapSupabaseError };
