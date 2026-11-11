import { openForm } from './form-dialog.js';
import { escape } from './html.js';
import { field, result, write } from './workforce-form.js';
import { taskStatus } from './task-scheduler.js';

const timezone = 'Asia/Kuala_Lumpur';
const day = 86400000;
const localDate = new Intl.DateTimeFormat('sv-SE', { timeZone: timezone, dateStyle: 'short' });
const localTime = new Intl.DateTimeFormat('en-GB', { timeZone: timezone, timeStyle: 'medium' });
const fullDate = new Intl.DateTimeFormat('en-MY', { timeZone: 'UTC', dateStyle: 'full' });
const monthName = new Intl.DateTimeFormat('en-MY', { timeZone: 'UTC', month: 'long', year: 'numeric' });
const isoDay = value => new Date(value).toISOString().slice(0, 10);
const dayStart = value => `${isoDay(value)}T00:00:00+08:00`;
const toLocalInput = value => `${localDate.format(new Date(value))}T${localTime.format(new Date(value))}`;
const displayTime = value => localTime.format(new Date(value)).slice(0, 5);
const displayDate = value => `${localDate.format(new Date(value))} · ${displayTime(value)}`;
const normalized = value => String(value ?? '').trim().toLowerCase();

export function calendarDays(month, availability) {
  const year = month.getUTCFullYear();
  const monthIndex = month.getUTCMonth();
  const start = Date.UTC(year, monthIndex, 1);
  const end = Date.UTC(year, monthIndex + 1, 1);
  const shifts = availability.map(record => ({
    start: Date.parse(record.shift_start),
    end: Date.parse(record.shift_end),
    leave: normalized(record.leave_status) === 'approved',
    available: normalized(record.availability_status) === 'available',
  }));
  const days = [];
  for (let value = start; value < end; value += day) {
    const startTime = Date.parse(dayStart(value));
    const records = shifts.filter(shift => shift.start < startTime + day && shift.end > startTime);
    const leave = records.some(shift => shift.leave);
    const sunday = new Date(value).getUTCDay() === 0;
    days.push({ value, leave, sunday, available: records.some(shift => shift.available), disabled: leave || sunday });
  }
  return days;
}

export function mountWorkerAvailability(section, client, workerId) {
  const today = localDate.format(new Date());
  let month = new Date(`${today.slice(0, 7)}-01T00:00:00Z`);
  let selected;
  let monthRequest = 0;
  let dayRequest = 0;

  async function load(message = '') {
    const request = ++monthRequest;
    dayRequest++;
    const year = month.getUTCFullYear();
    const monthIndex = month.getUTCMonth();
    section.innerHTML = `<header class="workforce-heading"><h2>Date availability</h2></header>
      <p class="calendar-notice muted" role="status">Loading availability…</p>`;
    try {
      const shifts = await result(client.from('worker_availability')
        .select('availability_id,availability,shift_start,shift_end,availability_status,leave_status')
        .eq('worker_id', workerId).lt('shift_start', dayStart(Date.UTC(year, monthIndex + 1, 1)))
        .gt('shift_end', dayStart(month)).order('shift_start'));
      if (!section.isConnected || request !== monthRequest) return;
      const days = calendarDays(month, shifts);
      if (!days.some(date => date.value === selected && !date.disabled)) selected = undefined;
      const blanks = (month.getUTCDay() + 6) % 7;
      section.innerHTML = `<header class="workforce-heading"><div><h2>Date availability</h2>
        <p class="muted">Malaysia time</p></div><button class="primary" data-add-availability>Add availability</button></header>
        <p class="feedback" role="status">${escape(message)}</p>
        <div class="availability-layout"><div class="workforce-calendar">
          <div class="calendar-month"><button class="secondary" type="button" data-prev-month aria-label="Previous month">‹</button>
            <h3>${monthName.format(month)}</h3>
            <button class="secondary" type="button" data-next-month aria-label="Next month">›</button></div>
          <div class="calendar-grid">
            ${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map(name => `<span class="calendar-weekday">${name}</span>`).join('')}
            ${'<span aria-hidden="true"></span>'.repeat(blanks)}
            ${days.map(date => {
              const status = date.leave ? 'Approved leave' : date.sunday ? 'Sunday' : date.available ? 'Available' : '';
              const label = `${fullDate.format(date.value)}${status ? ` · ${status}` : ''}`;
              return `<button type="button" class="calendar-day ${date.leave ? 'on-leave' : ''} ${date.available && !date.disabled ? 'has-availability' : ''}"
                data-date="${date.value}" aria-label="${escape(label)}" title="${escape(label)}"
                aria-pressed="${date.value === selected}" ${date.disabled ? 'disabled' : ''}>
                ${new Date(date.value).getUTCDate()}</button>`;
            }).join('')}
          </div>
          <div class="calendar-legend"><span><i class="calendar-available-key"></i>Availability recorded</span>
            <span><i class="calendar-leave-key"></i>Approved leave</span><span>Sunday closed</span></div>
        </div><section class="calendar-tasks" data-day-tasks>
          <h3>Assigned tasks</h3><p class="muted">Select a date to see this worker’s tasks.</p>
        </section></div>
        <details class="availability-records"><summary>Availability records for this month</summary>
          <div class="table-scroll"><table><thead><tr><th>Record</th><th>Starts</th><th>Ends</th>
            <th>Availability</th><th>Leave</th><th></th></tr></thead><tbody>
          ${shifts.map((shift, index) => `<tr><td><strong>${escape(shift.availability)}</strong></td>
            <td>${escape(displayDate(shift.shift_start))}</td><td>${escape(displayDate(shift.shift_end))}</td>
            <td>${escape(shift.availability_status)}</td><td>${escape(shift.leave_status)}</td>
            <td><button class="text-button" data-availability="${index}">Edit availability</button></td></tr>`).join('')
            || '<tr><td colspan="6" class="empty">No availability records for this month.</td></tr>'}
          </tbody></table></div></details>`;
      section.querySelector('[data-prev-month]').onclick = () => changeMonth(-1);
      section.querySelector('[data-next-month]').onclick = () => changeMonth(1);
      section.querySelector('[data-add-availability]').onclick = () => editAvailability();
      section.querySelectorAll('[data-availability]').forEach(button => {
        button.onclick = () => editAvailability(shifts[Number(button.dataset.availability)]);
      });
      section.querySelectorAll('[data-date]:not(:disabled)').forEach(button => {
        button.onclick = () => showDay(Number(button.dataset.date));
      });
      if (selected !== undefined) showDay(selected);
    } catch (error) {
      if (!section.isConnected || request !== monthRequest) return;
      section.innerHTML = `<header class="workforce-heading"><h2>Date availability</h2></header>
        <p class="error calendar-notice" role="alert">${escape(error.message)}</p>
        <button class="secondary calendar-notice" data-retry>Retry</button>`;
      section.querySelector('[data-retry]').onclick = () => load();
    }
  }

  function changeMonth(offset) {
    month = new Date(Date.UTC(month.getUTCFullYear(), month.getUTCMonth() + offset, 1));
    selected = undefined;
    load();
  }

  async function showDay(value) {
    selected = value;
    const request = ++dayRequest;
    const panel = section.querySelector('[data-day-tasks]');
    section.querySelectorAll('[data-date]').forEach(button => {
      button.setAttribute('aria-pressed', String(Number(button.dataset.date) === value));
    });
    const heading = `<h3>${fullDate.format(value)}</h3>`;
    panel.innerHTML = `${heading}<p class="muted" role="status">Loading assigned tasks…</p>`;
    try {
      const tasks = await result(client.from('preventive_work_order')
        .select('id,title,scheduled_for,due_at,status,preventive_work_order_target(facility_name),preventive_work_completion(work_order_id,actual_minutes)')
        .eq('worker_id', workerId).is('cancelled_at', null).gte('scheduled_for', dayStart(value))
        .lt('scheduled_for', dayStart(value + day)).order('scheduled_for'));
      if (request !== dayRequest || !panel.isConnected) return;
      panel.innerHTML = `${heading}${tasks.length ? `<ul class="calendar-task-list">${tasks.map((task, index) => {
        const locations = task.preventive_work_order_target.map(target => target.facility_name).join(', ');
        const completion = task.preventive_work_completion;
        return `<li><strong>${escape(task.title)}</strong>
          <p class="muted">${displayTime(task.scheduled_for)}–${displayTime(task.due_at)}${locations ? ` · ${escape(locations)}` : ''}</p>
          <span class="badge ${completion ? 'active' : ''}">${escape(taskStatus[task.status])}</span>
          ${completion ? `<button class="text-button" data-worked="${index}">${completion.actual_minutes ?
            `Worked ${completion.actual_minutes} min · Edit` : 'Record worked time'}</button>` : ''}</li>`;
      }).join('')}</ul>` : '<p class="muted">No assigned tasks for this date.</p>'}`;
      panel.querySelectorAll('[data-worked]').forEach(button => {
        const task = tasks[Number(button.dataset.worked)];
        button.onclick = () => openForm(section, 'Record worked time',
          field('Minutes worked', 'minutes', task.preventive_work_completion.actual_minutes, 'type="number" min="1" max="1440" required'),
          values => write(client.from('preventive_work_completion').update({ actual_minutes: Number(values.get('minutes')) })
            .eq('work_order_id', task.id), 'work_order_id'), () => showDay(value));
      });
    } catch (error) {
      if (request !== dayRequest || !panel.isConnected) return;
      panel.innerHTML = `${heading}<p class="error" role="alert">${escape(error.message)}</p>`;
    }
  }

  function editAvailability(shift) {
    const date = selected === undefined ? '' : isoDay(selected);
    const first = shift ? toLocalInput(shift.shift_start) : date && `${date}T08:00`;
    const last = shift ? toLocalInput(shift.shift_end) : date && `${date}T17:00`;
    openForm(section, shift ? 'Edit availability' : 'Add availability', `<p class="muted">Enter times in Malaysia time.</p>
      ${field('Label', 'availability', shift?.availability, 'required maxlength="120"')}
      ${field('Starts', 'shift_start', first, 'type="datetime-local" step="1" required')}
      ${field('Ends', 'shift_end', last, 'type="datetime-local" step="1" required')}
      ${statusSelect('Availability', 'availability_status', shift?.availability_status ?? 'available', ['available', 'unavailable'])}
      ${statusSelect('Leave status', 'leave_status', shift?.leave_status ?? 'none', ['none', 'pending', 'approved', 'rejected'])}`,
    async values => {
      const name = values.get('availability').trim();
      const start = values.get('shift_start');
      const end = values.get('shift_end');
      if (!name) throw new Error('Enter an availability label.');
      if (Date.parse(end + '+08:00') <= Date.parse(start + '+08:00')) {
        throw new Error('The end must be after the start.');
      }
      const changes = {
        availability: name,
        shift_start: shift && toLocalInput(shift.shift_start).replace(/:00$/, '') === start.replace(/:00$/, '')
          ? shift.shift_start : start + '+08:00',
        shift_end: shift && toLocalInput(shift.shift_end).replace(/:00$/, '') === end.replace(/:00$/, '')
          ? shift.shift_end : end + '+08:00',
        availability_status: values.get('availability_status'),
        leave_status: values.get('leave_status'),
      };
      const table = client.from('worker_availability');
      await write(shift
        ? table.update(changes).eq('worker_id', workerId).eq('availability_id', shift.availability_id)
        : table.insert({ ...changes, worker_id: workerId }), 'availability_id');
      const savedMonth = start.slice(0, 7);
      if (savedMonth !== isoDay(month).slice(0, 7)) {
        month = new Date(`${savedMonth}-01T00:00:00Z`);
        selected = undefined;
      }
    }, () => load('Availability saved.'));
  }

  load();
}

function statusSelect(label, name, selected, statuses) {
  const choices = [...new Set([...statuses, selected])];
  return `<label>${label}<select name="${name}">
    ${choices.map(status => `<option value="${escape(status)}" ${status === selected ? 'selected' : ''}>
      ${escape(status.charAt(0).toUpperCase() + status.slice(1))}</option>`).join('')}
    </select></label>`;
}
