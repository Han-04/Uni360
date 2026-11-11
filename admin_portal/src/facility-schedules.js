import { openForm } from './form-dialog.js';
import { escape } from './html.js';

const frequencies = { daily: 'Daily', weekly: 'Weekly', monthly: 'Monthly' };

async function read(query) {
  const { data, error } = await query;
  if (!error) return data;
  if (error.code === 'PGRST202') throw new Error('Apply the facility scheduling migration in Supabase to save schedules.');
  if (error.code === '23514' || error.code === '42501') throw new Error(error.message);
  throw new Error('Supabase could not complete the schedule request. Please try again.');
}

function localToday() {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Kuala_Lumpur', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts();
  const date = Object.fromEntries(parts.map(part => [part.type, part.value]));
  return `${date.year}-${date.month}-${date.day}`;
}

export function mountFacilitySchedules(content, client, facility, back, path) {
  const parents = path.slice(0, -1).map(parent => escape(parent.name)).join(' / ');
  const heading = `<button class="text-button" data-back>← Back to facilities</button>
    <header class="section-head"><div><h1>${escape(facility.name)}</h1>
    <p class="muted">${parents ? `${parents} · ` : ''}Facility schedules · Malaysia time</p></div>`;
  let templates = [];
  let active = true;
  const returnToFacilities = () => {
    active = false;
    back();
  };

  async function load(message = '') {
    content.innerHTML = `${heading}</header><p class="muted" role="status">Loading…</p>`;
    content.querySelector('[data-back]').onclick = returnToFacilities;
    try {
      const [plans, availableTemplates] = await Promise.all([
        read(client.from('preventive_task_plan')
          .select('is_active,preventive_task_definition(id,title,is_active),preventive_schedule(id,frequency,starts_on,ends_on,local_time,is_active)')
          .eq('facility_id', facility.id)),
        read(client.from('preventive_task_definition').select('id,title').eq('is_active', true)
          .or(`zone_id.is.null,zone_id.eq.${facility.zone_id}`).order('title').order('id')),
      ]);
      if (!active || !content.isConnected) return;
      templates = availableTemplates;
      const slots = plans.flatMap(plan => plan.preventive_schedule.filter(slot => slot.is_active)
        .map(slot => ({ ...slot, template: plan.preventive_task_definition, planActive: plan.is_active })))
        .sort((first, second) => first.template.title.localeCompare(second.template.title)
          || first.local_time.localeCompare(second.local_time));
      const canAdd = facility.effective_active && templates.length;
      content.innerHTML = `${heading}<button class="primary" data-add ${canAdd ? '' : 'disabled'}>Assign task template</button></header>
        ${!facility.effective_active ? '<p class="muted catalog-note">Activate the facility and its parent locations to add schedules.</p>' : ''}
        ${facility.effective_active && !templates.length ? '<p class="muted catalog-note">Create an active task template for this zone first.</p>' : ''}
        <p class="feedback" role="status">${escape(message)}</p>
        <div class="card table-scroll"><table><thead><tr><th>Task template</th><th>Repeats</th><th>Time</th>
          <th>Starts</th><th>Ends</th><th>Actions</th></tr></thead><tbody>
        ${slots.map((slot, index) => `<tr><td><strong>${escape(slot.template.title)}</strong>
          ${slot.planActive && slot.template.is_active ? '' : '<span class="badge">Inactive assignment</span>'}</td>
          <td>${frequencies[slot.frequency]}</td><td>${escape(formatTime(slot.local_time))}</td>
          <td>${escape(slot.starts_on)}</td><td>${escape(slot.ends_on ?? '—')}</td>
          <td class="actions">
            ${facility.effective_active && slot.template.is_active ? `<button class="text-button" data-edit="${index}">Edit</button>` : ''}
            <button class="text-button danger" data-stop="${index}">Deactivate</button></td></tr>`).join('')
          || '<tr><td colspan="6" class="empty">No task schedules for this facility.</td></tr>'}
        </tbody></table></div>`;
      content.querySelector('[data-back]').onclick = returnToFacilities;
      content.querySelector('[data-add]').onclick = () => edit();
      content.querySelectorAll('[data-edit]').forEach(button => { button.onclick = () => edit(slots[button.dataset.edit]); });
      content.querySelectorAll('[data-stop]').forEach(button => { button.onclick = () => deactivate(slots[button.dataset.stop]); });
    } catch (error) {
      if (!active || !content.isConnected) return;
      content.innerHTML = `${heading}</header><p class="error" role="alert">${escape(error.message)}</p>
        <button class="secondary" data-retry>Retry</button>`;
      content.querySelector('[data-back]').onclick = returnToFacilities;
      content.querySelector('[data-retry]').onclick = () => load();
    }
  }

  function edit(slot) {
    const templateField = slot
      ? `<p><strong>${escape(slot.template.title)}</strong></p>`
      : `<label>Task template<select name="template" required><option value="">Choose a task template</option>
        ${templates.map(template => `<option value="${escape(template.id)}">${escape(template.title)}</option>`).join('')}
        </select></label>`;
    const dialog = openForm(content, slot ? 'Edit schedule time' : 'Assign task template', `
      ${templateField}
      <label>Repeat<select name="frequency" required>${Object.entries(frequencies).map(([value, name]) =>
        `<option value="${value}" ${value === slot?.frequency ? 'selected' : ''}>${name}</option>`).join('')}</select></label>
      <label>Starts on<input type="date" name="starts_on" value="${escape(slot?.starts_on ?? localToday())}" required></label>
      <p class="muted schedule-anchor"></p>
      <label>Ends on (optional)<input type="date" name="ends_on" value="${escape(slot?.ends_on)}"></label>
      <fieldset class="task-checklist"><legend>Times (Malaysia time)</legend>
        <div data-times>${timeField(slot?.local_time, !slot)}</div>
        ${slot ? '' : '<button class="text-button" type="button" data-more>Add time</button>'}
      </fieldset>`, async values => {
      const times = values.getAll('time').map(value => value.length === 5 ? `${value}:00` : value);
      if (new Set(times).size !== times.length) throw new Error('Each time must be different.');
      const firstDate = values.get('starts_on');
      const lastDate = values.get('ends_on') || null;
      if (lastDate && lastDate < firstDate) throw new Error('The end date must be on or after the start date.');
      await read(client.rpc('save_preventive_facility_schedule', {
        target_facility: facility.id,
        target_template: slot?.template.id ?? values.get('template'),
        repeat_frequency: values.get('frequency'),
        first_date: firstDate,
        last_date: lastDate,
        times,
        replaced_schedule: slot?.id ?? null,
      }));
    }, () => load('Schedule saved.'), 'Save schedule');

    const frequency = dialog.querySelector('[name=frequency]');
    const anchor = dialog.querySelector('.schedule-anchor');
    const updateAnchor = () => {
      anchor.textContent = {
        daily: '', weekly: 'Repeats on the weekday of the start date.',
        monthly: 'Repeats on the day of the month of the start date.',
      }[frequency.value];
    };
    frequency.onchange = updateAnchor;
    updateAnchor();
    const times = dialog.querySelector('[data-times]');
    const more = dialog.querySelector('[data-more]');
    if (more) {
      more.onclick = () => {
        times.insertAdjacentHTML('beforeend', timeField('', true));
        times.lastElementChild.querySelector('input').focus();
      };
      times.onclick = event => {
        const remove = event.target.closest('[data-remove-time]');
        if (remove && times.children.length > 1) {
          remove.parentElement.remove();
          more.focus();
        }
      };
    }
  }

  function deactivate(slot) {
    openForm(content, 'Deactivate schedule time?',
      `<p>${escape(slot.template.title)} · ${frequencies[slot.frequency]} at ${escape(formatTime(slot.local_time))}</p>
        <p>Existing work orders will be kept.</p>`, async () => {
        const updated = await read(client.from('preventive_schedule').update({ is_active: false })
          .eq('id', slot.id).eq('is_active', true).select('id').maybeSingle());
        if (!updated) throw new Error('This schedule has changed. Refresh and try again.');
      }, () => load('Schedule time deactivated.'), 'Deactivate');
  }

  load();
}

function formatTime(value) {
  return value.endsWith(':00') ? value.slice(0, 5) : value;
}

function timeField(value = '', removable) {
  return `<div class="schedule-time">
    <label>Time<input type="time" name="time" step="1" required value="${escape(value ? formatTime(value) : '')}"></label>
    ${removable ? '<button type="button" class="text-button" data-remove-time>Remove time</button>' : ''}</div>`;
}
