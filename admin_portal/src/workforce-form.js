import { escape } from './html.js';

export const optional = value => value.trim() || null;

export async function result(query) {
  const { data, error } = await query;
  if (!error) return data;
  if (error.code === '42501') throw new Error('An active administrator account is required.');
  if (error.code === '23505') throw new Error('This record already exists.');
  if (['PGRST202', 'PGRST205'].includes(error.code)) {
    throw new Error('Apply the worker certifications migration in Supabase to use this feature.');
  }
  throw new Error('Supabase could not complete the request. Please try again.');
}

export async function write(query, id) {
  const row = await result(query.select(id).maybeSingle());
  if (!row) throw new Error('The record is no longer available for editing.');
}

export function field(label, name, value = '', options = '') {
  return `<label>${label}<input name="${name}" value="${escape(value)}" ${options}></label>`;
}

export function checkbox(label, name, checked) {
  return `<label class="check-field"><input name="${name}" type="checkbox" ${checked ? 'checked' : ''}>${label}</label>`;
}
