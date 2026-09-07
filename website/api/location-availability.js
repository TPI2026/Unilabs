'use strict';

const TIMEOUT_MS = 8000;

function sendJson(response, statusCode, payload) {
  response.status(statusCode);
  response.setHeader('Content-Type', 'application/json; charset=utf-8');
  response.setHeader('Cache-Control', 'no-store, max-age=0');
  response.end(JSON.stringify(payload));
}

async function supabaseGet(path, signal) {
  const supabaseUrl = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !key) throw new Error('Server configuration error');

  const headers = { apikey: key, Accept: 'application/json' };
  if (!key.startsWith('sb_secret_')) headers.Authorization = `Bearer ${key}`;

  const result = await fetch(`${supabaseUrl.replace(/\/$/, '')}/rest/v1/${path}`, { headers, signal });
  if (!result.ok) throw new Error(`Backend request failed (${result.status})`);
  return result.json();
}

module.exports = async function handler(request, response) {
  if (request.method !== 'GET') {
    response.setHeader('Allow', 'GET');
    return sendJson(response, 405, { ok: false, error: 'Use GET' });
  }

  const locationId = String(request.query?.location_id || 'LOC-AMS').trim();
  const slotDate = String(request.query?.slot_date || '').trim();
  if (!/^LOC-[A-Z0-9-]+$/.test(locationId) || !/^\d{4}-\d{2}-\d{2}$/.test(slotDate)) {
    return sendJson(response, 400, { ok: false, error: 'Invalid location_id or slot_date' });
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const location = encodeURIComponent(locationId);
    const date = encodeURIComponent(slotDate);
    const [slots, rooms, appointments] = await Promise.all([
      supabaseGet(`appointment_slots?location_id=eq.${location}&slot_date=eq.${date}&select=slot_id,start_time,bookable&order=start_time.asc`, controller.signal),
      supabaseGet(`rooms?location_id=eq.${location}&select=room_id,room_name,room_order&order=room_order.asc`, controller.signal),
      supabaseGet(`appointments?location_id=eq.${location}&status=eq.confirmed&select=slot_id,room_id`, controller.signal),
    ]);

    const capacity = rooms.length;
    const data = slots.map((slot) => {
      const bookedAppointments = appointments.filter((a) => a.slot_id === slot.slot_id);
      const busyRoomIds = new Set(bookedAppointments.map((a) => a.room_id).filter(Boolean));
      const bookedCount = bookedAppointments.length;
      const freeCount = Math.max(0, capacity - bookedCount);
      return {
        slot_id: slot.slot_id,
        time: String(slot.start_time).slice(0, 5),
        bookable: Boolean(slot.bookable),
        capacity,
        booked_count: bookedCount,
        free_count: slot.bookable ? freeCount : null,
        available: Boolean(slot.bookable) && freeCount > 0,
        rooms: rooms.map((room) => ({
          room_id: room.room_id,
          room_name: room.room_name,
          busy: busyRoomIds.has(room.room_id),
        })),
      };
    });

    return sendJson(response, 200, {
      ok: true,
      location_id: locationId,
      slot_date: slotDate,
      capacity,
      slots: data,
      generated_at: new Date().toISOString(),
    });
  } catch (error) {
    const message = error?.name === 'AbortError' ? 'Backend request timed out' : 'Could not load live availability';
    return sendJson(response, 502, { ok: false, error: message });
  } finally {
    clearTimeout(timer);
  }
};
