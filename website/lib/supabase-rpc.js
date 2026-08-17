'use strict';

function sendJson(response, statusCode, payload) {
  response.status(statusCode).setHeader('Content-Type', 'application/json; charset=utf-8');
  response.end(JSON.stringify(payload));
}

function parseBody(request) {
  if (request.body == null || request.body === '') return {};
  if (typeof request.body === 'object') return request.body;
  if (typeof request.body === 'string') {
    try {
      return JSON.parse(request.body);
    } catch {
      const error = new Error('Request body must be valid JSON');
      error.statusCode = 400;
      error.code = 'invalid_json';
      throw error;
    }
  }
  const error = new Error('Unsupported request body');
  error.statusCode = 400;
  error.code = 'invalid_body';
  throw error;
}

function getHeader(request, name) {
  const value = request.headers?.[name] ?? request.headers?.[name.toLowerCase()];
  return Array.isArray(value) ? value[0] : value;
}

function requireApiKey(request) {
  const expected = process.env.UNILABS_API_KEY;
  if (!expected) {
    const error = new Error('UNILABS_API_KEY is not configured');
    error.statusCode = 500;
    error.code = 'server_configuration_error';
    throw error;
  }

  const provided = getHeader(request, 'x-api-key');
  if (!provided || provided !== expected) {
    const error = new Error('Unauthorized');
    error.statusCode = 401;
    error.code = 'unauthorized';
    throw error;
  }
}

function validateField(name, value) {
  if (value == null) return;
  if (typeof value !== 'string' || value.trim() === '') {
    const error = new Error(`${name} must be a non-empty string`);
    error.statusCode = 400;
    error.code = 'invalid_parameter';
    throw error;
  }

  if (name.endsWith('_date') && !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    const error = new Error(`${name} must use YYYY-MM-DD`);
    error.statusCode = 400;
    error.code = 'invalid_parameter';
    throw error;
  }

  if (name.endsWith('_time') && !/^\d{2}:\d{2}(:\d{2})?$/.test(value)) {
    const error = new Error(`${name} must use HH:MM or HH:MM:SS`);
    error.statusCode = 400;
    error.code = 'invalid_parameter';
    throw error;
  }
}

async function callSupabaseRpc(rpcName, params) {
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseServerKey = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !supabaseServerKey) {
    const error = new Error('Supabase server credentials are not configured');
    error.statusCode = 500;
    error.code = 'server_configuration_error';
    throw error;
  }

  const headers = {
    apikey: supabaseServerKey,
    'Content-Type': 'application/json',
    Accept: 'application/json',
  };

  // New sb_secret_* keys are not JWTs and must not be sent as Bearer tokens.
  // Legacy service_role JWTs still require Authorization for backward compatibility.
  if (!supabaseServerKey.startsWith('sb_secret_')) {
    headers.Authorization = `Bearer ${supabaseServerKey}`;
  }

  const response = await fetch(`${supabaseUrl.replace(/\/$/, '')}/rest/v1/rpc/${rpcName}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(params),
  });

  const raw = await response.text();
  let data = null;
  if (raw) {
    try {
      data = JSON.parse(raw);
    } catch {
      data = { message: raw };
    }
  }

  if (!response.ok) {
    const error = new Error(data?.message || `Supabase RPC ${rpcName} failed`);
    error.statusCode = response.status >= 400 && response.status < 500 ? 400 : 502;
    error.code = data?.code || 'supabase_rpc_error';
    error.details = data?.details || null;
    error.hint = data?.hint || null;
    throw error;
  }

  return data;
}

function createRpcHandler({ action, rpcName, required = [], optional = [], map }) {
  return async function handler(request, response) {
    if (request.method !== 'POST') {
      response.setHeader('Allow', 'POST');
      return sendJson(response, 405, {
        ok: false,
        action,
        error: { code: 'method_not_allowed', message: 'Use POST' },
      });
    }

    try {
      requireApiKey(request);
      const body = parseBody(request);

      for (const field of required) {
        if (body[field] == null || body[field] === '') {
          const error = new Error(`Missing required field: ${field}`);
          error.statusCode = 400;
          error.code = 'missing_parameter';
          throw error;
        }
      }

      for (const field of [...required, ...optional]) {
        validateField(field, body[field]);
      }

      const params = map(body);
      const data = await callSupabaseRpc(rpcName, params);

      return sendJson(response, 200, { ok: true, action, data });
    } catch (error) {
      return sendJson(response, error.statusCode || 500, {
        ok: false,
        action,
        error: {
          code: error.code || 'internal_error',
          message: error.message || 'Internal server error',
          details: error.details || null,
          hint: error.hint || null,
        },
      });
    }
  };
}

module.exports = { createRpcHandler };
