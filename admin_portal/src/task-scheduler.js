import { openForm } from './form-dialog.js';
import { escape } from './html.js';
import { taskCategory } from './task-checklists.js';

export async function scheduleResult(query) {
  const { data, error } = await query;
  if (!error) return data;
  if (error.code === 'PGRST202') throw new Error('Apply the latest Uni360 migrations in Supabase first.');
  if (['23514', '42501'].includes(error.code)) throw new Error(error.message);
  throw new Error('Supabase could not complete the scheduling request.');
}

export const taskStatus = {
  assigned: 'Assigned', in_progress: 'In progress', submitted: 'Awaiting approval', completed: 'Completed',
};

export async function loadWorkerDirectory(client) {
  const workers = new Map();
  for (let offset = 0; ; offset += 25) {
    const batch = await scheduleResult(client.rpc('workforce_directory', { search_text: '', start_at: offset }));
    for (const worker of batch.slice(0, 25)) workers.set(worker.worker_id, worker);
    if (batch.length <= 25) return workers;
  }
}

const malaysiaDate = () => new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Kuala_Lumpur' }).format(new Date());
const clock = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Kuala_Lumpur', timeStyle: 'short' });
const time = value => clock.format(new Date(value));
const workDate = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Kuala_Lumpur' });
const date = value => workDate.format(new Date(value));
const malaysiaMidnight = value => `${value}T00:00:00+08:00`;
const dayAfter = value => new Date(Date.parse(`${value}T00:00:00Z`) + 86400000).toISOString().slice(0, 10);

function locationPaths(facilities) {
  const byId = new Map(facilities.map(facility => [facility.id, facility]));
  return new Map(facilities.map(facility => {
    const names = [];
    const seen = new Set();
    for (let item = facility; item && !seen.has(item.id); item = byId.get(item.parent_id)) {
      names.unshift(item.name);
      seen.add(item.id);
    }
    return [facility.id, names.join(' / ')];
  }));
}

export function scheduleTemplate(content, client, template, facilities, back) {
  const toiletCleaning = taskCategory(template) === 'Toilet Cleaning';
  const paths = locationPaths(facilities);
  const choices = facilities.filter(facility => facility.effective_active
    && (!template.zone_id || facility.zone_id === template.zone_id)
    && (!toiletCleaning || (facility.facility_type === 'room' && facility.metadata.room_type === 'toilet')))
    .map(facility => {
      const name = paths.get(facility.id);
      return { id: facility.id, name, building: name.split(' / ')[0] };
    })
    .sort((first, second) => first.name.localeCompare(second.name));
  const buildings = [...new Set(choices.map(choice => choice.building))];
  let generated;
  const modal = openForm(content, 'Schedule task', `<p><strong>${escape(template.title)}</strong></p>
    <fieldset class="task-checklist"><legend>${toiletCleaning ? 'Toilets to clean' : 'Facilities'}</legend>
      ${choices.length ? `<label>Search facilities<input type="search" data-location-search placeholder="Search by building, floor or room"></label>
      <label>Building or site<select data-location-building><option value="">All locations</option>
        ${buildings.map(name => `<option value="${escape(name)}">${escape(name)}</option>`).join('')}</select></label>
      <label class="check-field"><input type="checkbox" data-select-all>Select all results</label>
      <p class="muted" data-selection-count role="status"></p>
      <div class="schedule-locations">${choices.map(choice => `<label class="check-field" data-location-row>
        <input type="checkbox" name="facility" value="${escape(choice.id)}">${escape(choice.name)}</label>`).join('')}</div>`
    : '<p class="muted">No active locations are available for this template.</p>'}</fieldset>
    <label>Repeat<select name="frequency"><option value="daily">Daily</option><option value="weekly">Weekly</option><option value="monthly">Monthly</option></select></label>
    <label>Starts on<input type="date" name="starts_on" value="${malaysiaDate()}" required></label>
    <label>Ends on<input type="date" name="ends_on" required></label>
    <label>Work time per location (minutes)<input type="number" name="work_minutes" min="1" max="720" step="1" value="${template.duration_minutes}" required></label>
    <fieldset class="task-checklist"><legend>Start times (Malaysia time)</legend>
      <div data-times><label>Time<input type="time" name="time" required></label></div>
      <button type="button" class="text-button" data-add-time>Add time</button>
    </fieldset>
    <p class="muted">Tasks can be staggered after each start time. Sundays are skipped.</p>`,
  choices.length ? async values => {
    const selected = values.getAll('facility');
    if (!selected.length) throw new Error('Select at least one location.');
    const times = values.getAll('time').map(value => value + ':00');
    if (new Set(times).size !== times.length) throw new Error('Each time must be different.');
    const first = values.get('starts_on');
    const last = values.get('ends_on');
    if (last < first) throw new Error('The end date must be on or after the start date.');
    const parameters = {
      target_facilities: selected, target_template: template.id, repeat_frequency: values.get('frequency'),
      first_date: first, last_date: last, times, work_minutes: Number(values.get('work_minutes')),
    };
    const draft = await scheduleResult(client.rpc('review_preventive_range', parameters));
    generated = { ...draft, parameters };
  } : null, () => {
    if (!content.isConnected || !generated) return;
    const { rows, warnings, parameters } = generated;
    content.innerHTML = `<button class="text-button" data-back>← Task templates</button>
      <header class="section-head"><div><h1>Review auto schedule</h1>
      <p class="muted">${escape(template.title)} · ${escape(parameters.first_date)} to ${escape(parameters.last_date)}</p></div></header>
      <div data-range-review></div>`;
    content.querySelector('[data-back]').onclick = back;
    renderDraft(content, content.querySelector('[data-range-review]'), rows, warnings,
      row => paths.get(row.facility_id), verified => scheduleResult(client.rpc('review_preventive_range', { ...parameters, reviewed: rows, verified })),
      () => {
        const list = document.createElement('div');
        content.querySelector('[data-range-review]').append(list);
        mountScheduledTasks(list, client)({
          first: parameters.first_date, last: parameters.last_date,
          template: parameters.target_template, facilities: parameters.target_facilities,
        });
      });
  }, 'Auto Schedule');
  if (!choices.length) return;
  const all = modal.querySelector('[data-select-all]');
  const checks = [...modal.querySelectorAll('[name=facility]')];
  const search = modal.querySelector('[data-location-search]');
  const building = modal.querySelector('[data-location-building]');
  const count = modal.querySelector('[data-selection-count]');
  const visible = () => checks.filter(check => !check.closest('[data-location-row]').hidden);
  function syncSelection() {
    const matches = visible();
    const checked = matches.filter(item => item.checked).length;
    all.disabled = !matches.length;
    all.checked = matches.length > 0 && checked === matches.length;
    all.indeterminate = checked > 0 && !all.checked;
    count.textContent = `${matches.length} shown · ${checks.filter(item => item.checked).length} selected`;
  }
  function filterLocations() {
    const term = search.value.trim().toLowerCase();
    checks.forEach((check, index) => {
      const choice = choices[index];
      check.closest('[data-location-row]').hidden = !choice.name.toLowerCase().includes(term)
        || Boolean(building.value && choice.building !== building.value);
    });
    syncSelection();
  }
  search.oninput = building.onchange = filterLocations;
  all.onchange = () => {
    visible().forEach(check => { check.checked = all.checked; });
    syncSelection();
  };
  checks.forEach(check => { check.onchange = syncSelection; });
  syncSelection();
  const times = modal.querySelector('[data-times]');
  modal.querySelector('[data-add-time]').onclick = () => {
    times.insertAdjacentHTML('beforeend', '<div class="schedule-time"><label>Time<input type="time" name="time" required></label><button type="button" class="text-button" data-remove>Remove time</button></div>');
    times.lastElementChild.querySelector('input').focus();
  };
  times.onclick = event => event.target.closest('[data-remove]')?.parentElement.remove();
}

export function reviewSchedule(content, client, zones, loadLocations, back) {
  content.innerHTML = `<button class="text-button" data-back>← Task templates</button>
    <header class="section-head"><h1>Review auto schedule</h1></header>
    <div class="card"><form class="toolbar schedule-controls">
      <label>Zone<select name="zone"><option value="">All accessible zones</option>
        ${zones.map(zone => `<option value="${escape(zone.id)}">${escape(zone.name)}</option>`).join('')}</select></label>
      <label>Work date<input type="date" name="date"></label>
      <button class="primary" disabled>Generate draft</button></form>
      <p class="muted catalog-note">Select a zone and date to generate a draft. Leave the date empty to see upcoming tasks.</p></div>
    <div data-review></div><div data-scheduled-tasks></div>`;
  content.querySelector('[data-back]').onclick = back;
  const form = content.querySelector('form');
  const review = content.querySelector('[data-review]');
  const generate = form.querySelector('button');
  const showScheduled = mountScheduledTasks(content.querySelector('[data-scheduled-tasks]'), client);
  function refreshScheduled() {
    const zone = form.elements.zone.value;
    const day = form.elements.date.value;
    generate.disabled = !zone || !day;
    showScheduled({ zone, first: day || malaysiaDate(), last: day });
  }
  let request = 0;
  form.onchange = () => {
    request++;
    review.innerHTML = '';
    refreshScheduled();
  };
  refreshScheduled();
  form.onsubmit = async event => {
    event.preventDefault();
    if (generate.disabled) return;
    const current = ++request;
    const values = new FormData(form);
    const parameters = { work_date: values.get('date'), target_zone: values.get('zone') };
    review.innerHTML = '<p class="catalog-note muted" role="status">Checking tasks and staff availability…</p>';
    try {
      const { rows, warnings } = await scheduleResult(client.rpc('review_preventive_day', parameters));
      if (current !== request || !review.isConnected) return;
      const names = await planLocations(rows);
      if (current !== request || !review.isConnected) return;
      renderDraft(content, review, rows, warnings, row => names.get(row.plan_id),
        verified => scheduleResult(client.rpc('review_preventive_day', { ...parameters, reviewed: rows, verified })),
        refreshScheduled);
    } catch (error) {
      if (current === request && review.isConnected) review.innerHTML = `<p class="error" role="alert">${escape(error.message)}</p>`;
    }
  };

  async function planLocations(rows) {
    const ids = [...new Set(rows.map(row => row.plan_id))];
    if (!ids.length) return new Map();
    const paths = locationPaths(await loadLocations());
    const names = new Map();
    for (let offset = 0; offset < ids.length; offset += 50) {
      const plans = await scheduleResult(client.from('preventive_task_plan').select('id,facility_id')
        .in('id', ids.slice(offset, offset + 50)));
      for (const plan of plans) names.set(plan.id, paths.get(plan.facility_id));
    }
    return names;
  }

}

function mountScheduledTasks(panel, client) {
  const pageSize = 20;
  let request = 0;
  let workerDirectory;

  return async function load(filters, page = 0) {
    if (!panel.isConnected) return;
    const current = ++request;
    const { zone, first, last, template, facilities } = filters;
    const period = last && last !== first ? `${first} to ${last}` : last || `Upcoming from ${first}`;
    const heading = `<header class="workforce-heading"><div><h2>Scheduled tasks</h2>
      <p class="muted">${escape(period)} · Malaysia time</p></div></header>`;
    panel.innerHTML = `<section class="card workforce-section">${heading}<p class="catalog-note muted" role="status">Loading scheduled tasks…</p></section>`;
    try {
      const plan = zone || template || facilities ? ',preventive_task_plan!inner(zone_id)' : '';
      let query = client.from('preventive_work_order')
        .select(`id,title,worker_id,scheduled_for,due_at,status,preventive_work_order_target(facility_path)${plan}`)
        .is('cancelled_at', null).not('worker_id', 'is', null).gte('scheduled_for', malaysiaMidnight(first))
        .order('scheduled_for').order('id').range(page * pageSize, (page + 1) * pageSize);
      if (last) query = query.lt('scheduled_for', malaysiaMidnight(dayAfter(last)));
      if (zone) query = query.eq('preventive_task_plan.zone_id', zone);
      if (template) query = query.eq('preventive_task_plan.task_definition_id', template);
      if (facilities) query = query.in('preventive_task_plan.facility_id', facilities);
      const rows = await scheduleResult(query);
      if (current !== request || !panel.isConnected) return;
      const workers = rows.length ? await (workerDirectory ??= loadWorkerDirectory(client).catch(error => {
        workerDirectory = undefined;
        throw error;
      })) : new Map();
      if (current !== request || !panel.isConnected) return;
      panel.innerHTML = `<section class="card workforce-section">${heading}
        <div class="table-scroll"><table><thead><tr><th>Date</th><th>Task</th><th>Location</th><th>Time</th><th>Worker</th><th>Status</th></tr></thead>
        <tbody>${rows.slice(0, pageSize).map(row => {
          const worker = workers.get(row.worker_id);
          const end = date(row.due_at) === date(row.scheduled_for) ? time(row.due_at) : `${date(row.due_at)} ${time(row.due_at)}`;
          return `<tr><td>${date(row.scheduled_for)}</td><td>${escape(row.title)}</td>
            <td>${escape(row.preventive_work_order_target.map(target => target.facility_path).sort().join(', '))}</td>
            <td>${time(row.scheduled_for)}–${end}</td>
            <td>${escape(worker ? `${worker.full_name} · ${worker.employee_id}` : 'Assigned worker')}</td>
            <td><span class="badge ${row.status === 'completed' ? 'active' : ''}">${escape(taskStatus[row.status])}</span></td></tr>`;
        }).join('') || '<tr><td colspan="6" class="empty">No scheduled assignments match these filters.</td></tr>'}</tbody></table></div>
        ${page || rows.length > pageSize ? `<footer class="pagination"><span>Page ${page + 1}</span>
          <button class="secondary" data-prev-saved ${page ? '' : 'disabled'}>Previous</button>
          <button class="secondary" data-next-saved ${rows.length > pageSize ? '' : 'disabled'}>Next</button></footer>` : ''}</section>`;
      const previous = panel.querySelector('[data-prev-saved]');
      const next = panel.querySelector('[data-next-saved]');
      if (previous) previous.onclick = () => load(filters, page - 1);
      if (next) next.onclick = () => load(filters, page + 1);
    } catch (error) {
      if (current !== request || !panel.isConnected) return;
      panel.innerHTML = `<section class="card workforce-section">${heading}<p class="error catalog-note" role="alert">${escape(error.message)}</p>
        <button class="secondary catalog-note" data-retry-saved>Retry</button></section>`;
      panel.querySelector('[data-retry-saved]').onclick = () => load(filters, page);
    }
  };
}

function renderDraft(content, review, rows, warnings, locationName, approve, onApproved) {
    const staff = new Map();
    const period = new Map();
    const dates = new Set(rows.map(row => date(row.occurrence)));
    for (const row of rows) {
      if (!row.worker_id) continue;
      const workDay = date(row.occurrence);
      const key = `${row.worker_id}/${workDay}`;
      const person = staff.get(key) ?? { ...row, added: 0, workDay };
      person.added += row.duration_minutes;
      staff.set(key, person);
      const total = period.get(row.worker_id) ?? { name: row.worker_name, employee: row.employee_id, tasks: 0, minutes: 0 };
      total.tasks++;
      total.minutes += row.duration_minutes;
      period.set(row.worker_id, total);
    }
    const assigned = rows.filter(row => row.worker_id).length;
    review.innerHTML = `${warnings.length ? `<section class="card workforce-section schedule-warning" aria-labelledby="schedule-warning-title">
      <header class="workforce-heading"><div><h2 id="schedule-warning-title">Verify existing tasks</h2>
        <p class="muted">These locations already have the same task on the listed dates. Confirm that another visit is intentional before approving.</p></div></header>
      <div class="table-scroll"><table><thead><tr><th>Date</th><th>Location</th><th>Task</th><th>Existing time</th><th>Source</th></tr></thead><tbody>
      ${warnings.map(item => `<tr><td>${escape(item.date)}</td><td>${escape(item.location ?? 'Campaign')}</td>
        <td>${escape(item.task)}</td><td>${escape(item.time.slice(0, 5))}</td><td>${escape(item.source)}</td></tr>`).join('')}</tbody></table></div>
      <label class="check-field schedule-verification"><input type="checkbox" data-verified>I verified these existing tasks and intend to proceed.</label>
      </section>` : ''}<section class="card workforce-section">
      <header class="workforce-heading"><div><h2>Draft assignments</h2>
        <p class="muted">${assigned} assigned · ${rows.length - assigned} unassigned · Malaysia time</p></div>
      <button class="primary" data-approve ${assigned && !warnings.length ? '' : 'disabled'}>Approve assignments</button></header>
      <div class="table-scroll"><table><thead><tr><th>Date</th><th>Task</th><th>Location</th><th>Time</th><th>Duration</th><th>Worker</th></tr></thead><tbody>
      ${rows.map(row => `<tr><td>${date(row.occurrence)}</td><td>${escape(row.title)}</td><td>${escape(locationName(row) ?? row.facility)}</td>
        <td>${row.starts ? `${time(row.starts)}–${time(row.ends)}` : `From ${time(row.occurrence)}`}</td>
        <td>${row.duration_minutes} min</td><td>${row.worker_id ? escape(row.worker_name) :
          '<span class="badge">Unassigned</span><div class="muted">No eligible worker with enough time</div>'}</td></tr>`).join('')
        || '<tr><td colspan="6" class="empty">No outstanding tasks match this schedule.</td></tr>'}</tbody></table></div></section>
      ${dates.size > 1 && period.size ? `<section class="card workforce-section"><header class="workforce-heading"><h2>Work added across this period</h2></header>
      <div class="table-scroll"><table><thead><tr><th>Worker</th><th>Tasks</th><th>Draft work time</th></tr></thead><tbody>
      ${[...period.values()].map(person => `<tr><td>${escape(person.name)} · ${escape(person.employee)}</td>
        <td>${person.tasks}</td><td>${person.minutes} min</td></tr>`).join('')}</tbody></table></div></section>` : ''}
      ${staff.size ? `<section class="card workforce-section"><header class="workforce-heading"><h2>Staff workload by date</h2></header>
      <div class="table-scroll"><table><thead><tr><th>Date</th><th>Worker</th><th>Worked</th><th>Existing load (incl. worked)</th><th>Added</th><th>Projected / daily limit</th></tr></thead>
      <tbody>${[...staff.values()].map(person => `<tr><td>${person.workDay}</td><td>${escape(person.worker_name)} · ${escape(person.employee_id)}</td>
        <td>${person.worked_minutes} min</td><td>${person.booked_before} min</td><td>${person.added} min</td>
        <td>${person.booked_before + person.added} / ${person.work_limit} min</td></tr>`).join('')}</tbody></table></div></section>` : ''}`;
    const approval = review.querySelector('[data-approve]');
    const verify = review.querySelector('[data-verified]');
    if (verify) verify.onchange = () => { approval.disabled = !assigned || !verify.checked; };
    approval.onclick = () => openForm(content, 'Approve schedule?',
      `<p>Publish ${assigned} reviewed assignments as work orders. Unassigned tasks will stay available for another draft.</p>`,
      async () => {
        const count = await approve(verify?.checked ? warnings : null);
        review.innerHTML = `<p class="catalog-note" role="status">${count} ${count === 1 ? 'assignment' : 'assignments'} approved.</p>`;
        if (review.isConnected) onApproved();
      }, () => {}, 'Approve assignments');
}
