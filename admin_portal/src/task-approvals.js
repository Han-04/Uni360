import { openForm } from './form-dialog.js';
import { escape } from './html.js';
import { loadWorkerDirectory, scheduleResult } from './task-scheduler.js';

const dateTime = new Intl.DateTimeFormat('en-MY', {
  timeZone: 'Asia/Kuala_Lumpur', dateStyle: 'medium', timeStyle: 'short',
});
const when = value => value ? dateTime.format(new Date(value)) : '—';
const pageSize = 25;

export function mountTaskApprovals(content, client) {
  const photos = client.storage.from('preventive-work-evidence');
  let page = 0;
  let directory;

  async function load(message = '') {
    content.innerHTML = '<header class="section-head"><h1>Task approvals</h1></header><p class="muted" role="status">Loading submissions…</p>';
    try {
      const orders = await scheduleResult(client.from('preventive_work_order')
        .select('id,title,worker_id,scheduled_for,submitted_at,preventive_work_order_target(facility_path)')
        .eq('status', 'submitted').is('cancelled_at', null).order('submitted_at').order('id')
        .range(page * pageSize, (page + 1) * pageSize));
      if (!content.isConnected) return;
      if (!orders.length && page > 0) {
        page--;
        return load(message);
      }
      if (orders.length) directory ??= await loadWorkerDirectory(client);
      if (!content.isConnected) return;
      content.innerHTML = `<header class="section-head"><div><h1>Task approvals</h1>
        <p class="muted">Review the checklist and evidence for submitted work.</p></div>
        <button class="secondary" data-refresh>Refresh</button></header>
        <p class="feedback" role="status">${escape(message)}</p>
        <div class="card"><div class="table-scroll"><table><thead><tr><th>Task</th><th>Worker</th><th>Location</th>
        <th>Scheduled</th><th>Submitted</th><th></th></tr></thead><tbody>
        ${orders.slice(0, pageSize).map((order, index) => `<tr><td><strong>${escape(order.title)}</strong></td>
          <td>${escape(workerName(order.worker_id))}</td><td>${escape(location(order))}</td>
          <td>${escape(when(order.scheduled_for))}</td><td>${escape(when(order.submitted_at))}</td>
          <td><button class="text-button" data-review="${index}">Review</button></td></tr>`).join('')
          || '<tr><td colspan="6" class="empty">No tasks are awaiting approval.</td></tr>'}</tbody></table></div>
        ${page || orders.length > pageSize ? `<footer class="pagination"><span>Page ${page + 1}</span>
          <button class="secondary" data-prev ${page ? '' : 'disabled'}>Previous</button>
          <button class="secondary" data-next ${orders.length > pageSize ? '' : 'disabled'}>Next</button></footer>` : ''}</div>`;
      content.querySelector('[data-refresh]').onclick = () => load();
      const previous = content.querySelector('[data-prev]');
      const next = content.querySelector('[data-next]');
      if (previous) previous.onclick = () => { page--; load(); };
      if (next) next.onclick = () => { page++; load(); };
      content.querySelectorAll('[data-review]').forEach(button => {
        button.onclick = () => detail(orders[Number(button.dataset.review)].id);
      });
    } catch (error) {
      showError(error);
    }
  }

  function workerName(workerId) {
    const worker = directory?.get(workerId);
    return worker ? `${worker.full_name} · ${worker.employee_id}` : 'Assigned worker';
  }

  function location(order) {
    return order.preventive_work_order_target.map(target => target.facility_path).sort().join(', ');
  }

  function showError(error) {
    if (!content.isConnected) return;
    content.innerHTML = `<header class="section-head"><h1>Task approvals</h1></header>
      <p class="error" role="alert">${escape(error.message)}</p><button class="secondary" data-refresh>Back to submissions</button>`;
    content.querySelector('[data-refresh]').onclick = () => load();
  }

  async function detail(id) {
    content.innerHTML = '<p class="muted" role="status">Loading submitted work…</p>';
    try {
      const order = await scheduleResult(client.from('preventive_work_order')
        .select('id,title,worker_id,instructions,checklist,checked_items,worker_notes,scheduled_for,submitted_at,status,preventive_work_order_target(facility_path),preventive_work_evidence(path)')
        .eq('id', id).is('cancelled_at', null).maybeSingle());
      if (!content.isConnected) return;
      if (!order || order.status !== 'submitted') return load('This task is no longer awaiting review.');
      const evidence = await Promise.all(order.preventive_work_evidence.map(async ({ path }) => {
        const { data, error } = await photos.createSignedUrl(path, 300);
        return error ? null : data?.signedUrl;
      }));
      if (!content.isConnected) return;
      content.innerHTML = `<button class="text-button" data-back>← Task approvals</button>
        <header class="section-head"><div><h1>${escape(order.title)}</h1>
        <p class="muted">${escape(workerName(order.worker_id))} · ${escape(location(order))}</p>
        <p class="muted">Submitted ${escape(when(order.submitted_at))}</p></div>
        <div class="workforce-actions"><button class="secondary" data-return>Return for changes</button>
        <button class="primary" data-approve ${!evidence.length || evidence.some(url => !url) ? 'disabled' : ''}>Approve completion</button></div></header>
        <section class="card task-review-detail"><h2>Checklist</h2>
          <p class="catalog-instructions">${escape(order.instructions)}</p>
          ${order.checklist.length ? `<ul>${order.checklist.map((item, index) => `<li>${order.checked_items.includes(index) ? '✓' : '○'} ${escape(item)}</li>`).join('')}</ul>`
          : '<p class="muted">This task has no checklist.</p>'}
          ${order.worker_notes ? `<h2>Worker notes</h2><p class="catalog-instructions">${escape(order.worker_notes)}</p>` : ''}
          <h2>Photo evidence</h2>
          <div class="task-evidence-grid">${evidence.map((url, index) => url
            ? `<a href="${escape(url)}" target="_blank" rel="noopener noreferrer"><img src="${escape(url)}" alt="Evidence photo ${index + 1}"></a>`
            : '<p class="error">Could not open an evidence photo. Reopen this submission to try again.</p>').join('')
            || '<p class="error">No evidence photos are available.</p>'}</div></section>`;
      content.querySelector('[data-back]').onclick = () => load();
      content.querySelector('[data-approve]').onclick = () => confirmReview(order, true);
      content.querySelector('[data-return]').onclick = () => confirmReview(order, false);
    } catch (error) {
      showError(error);
    }
  }

  function confirmReview(order, approve) {
    const label = approve ? 'Approve completion' : 'Return for changes';
    openForm(content, label, approve
      ? `<p>Mark <strong>${escape(order.title)}</strong> as completed?</p>`
      : '<label>Feedback<textarea name="feedback" rows="3" required></textarea></label>',
    async values => {
      await scheduleResult(client.rpc('review_work_submission', {
        target_order: order.id, approve, feedback: approve ? null : values.get('feedback'),
      }));
    }, () => load(approve ? 'Work order completed.' : 'Work order returned to the worker.'), label);
  }

  load();
}
