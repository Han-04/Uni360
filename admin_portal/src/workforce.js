import { escape } from './html.js';
import { openForm } from './form-dialog.js';
import { checkbox, field, optional, result, write } from './workforce-form.js';
import { bindCertifications, certificationSection } from './worker-certifications.js';
import { mountWorkerAvailability } from './worker-availability.js';

const pageSize = 25;
const profileFields = 'worker_id,job_role,assigned_zone,employment_status,current_workload,standby_status,daily_work_limit_minutes';
export function mountWorkforce(content, client) {
  let query = '';
  let page = 0;

  function pending(title) {
    content.innerHTML = `<header class="section-head"><h1>${title}</h1></header><p class="muted" role="status">Loading…</p>`;
  }

  function failure(error, retry) {
    if (!content.isConnected) return;
    content.innerHTML = `<header class="section-head"><h1>Workforce management</h1></header>
      <p class="error" role="alert">${escape(error.message)}</p><button class="secondary" data-retry>Retry</button>`;
    content.querySelector('[data-retry]').onclick = retry;
  }

  async function directory() {
    pending('Workforce management');
    try {
      const workers = await result(client.rpc('workforce_directory', { search_text: query, start_at: page * pageSize }));
      if (!content.isConnected) return;
      content.innerHTML = `<header class="section-head"><div><h1>Workforce management</h1>
        <p class="muted">Manage worker profiles, skills, certifications and date availability.</p></div></header>
        <div class="card"><form class="toolbar"><label><span class="sr-only">Search workers</span>
          <input name="search" type="search" maxlength="120" placeholder="Search by name or employee ID" value="${escape(query)}"></label>
          <button class="secondary">Search</button></form>
        <div class="table-scroll"><table><thead><tr><th>Worker</th><th>Employee ID</th><th>Job role</th><th>Zone</th><th>Employment</th><th></th></tr></thead>
          <tbody>${workers.slice(0, pageSize).map((worker, index) => `<tr><td><strong>${escape(worker.full_name)}</strong></td>
          <td>${escape(worker.employee_id)}</td><td>${escape(worker.job_role ?? '—')}</td><td>${escape(worker.assigned_zone ?? '—')}</td>
          <td>${escape(worker.employment_status)}</td><td><button class="text-button" data-worker="${index}">Open profile</button></td></tr>`).join('') ||
          '<tr><td colspan="6" class="empty">No matching workers.</td></tr>'}</tbody></table></div>
        <footer class="pagination"><span>Page ${page + 1}</span><button class="secondary" data-previous ${page === 0 ? 'disabled' : ''}>Previous</button>
          <button class="secondary" data-next ${workers.length <= pageSize ? 'disabled' : ''}>Next</button></footer></div>`;
      content.querySelector('form').onsubmit = event => {
        event.preventDefault();
        query = new FormData(event.currentTarget).get('search').trim();
        page = 0;
        directory();
      };
      content.querySelector('[data-previous]').onclick = () => { page--; directory(); };
      content.querySelector('[data-next]').onclick = () => { page++; directory(); };
      content.querySelectorAll('[data-worker]').forEach(button => {
        button.onclick = () => openWorker(workers[Number(button.dataset.worker)]);
      });
    } catch (error) {
      failure(error, directory);
    }
  }

  async function openWorker(worker, message = '') {
    if (!content.isConnected) return;
    pending('Worker profile');
    try {
      const [profile, assignments, certificates] = await Promise.all([
        result(client.from('worker_profile').select(profileFields).eq('worker_id', worker.worker_id).single()),
        result(client.from('worker_skill').select('worker_skill_id,skill(skill_name)').eq('worker_id', worker.worker_id)),
        result(client.from('worker_certification')
          .select('certification_id,certification_name,certification_no,expiry_date,verified,document_path')
          .eq('worker_id', worker.worker_id).order('certification_name').order('certification_id')),
      ]);
      if (!content.isConnected) return;
      assignments.sort((first, second) => first.skill.skill_name.localeCompare(second.skill.skill_name));
      content.innerHTML = `<button class="text-button" data-back>← All workers</button>
        <header class="section-head"><div><h1>${escape(worker.full_name)}</h1><p class="muted">${escape(worker.employee_id)}</p></div></header>
        <p class="feedback" role="status">${escape(message)}</p>
        <section class="card workforce-section"><header class="workforce-heading"><h2>Worker profile</h2><button class="secondary" data-profile>Edit profile</button></header>
          <dl class="worker-facts"><div><dt>Job role</dt><dd>${escape(profile.job_role ?? '—')}</dd></div>
          <div><dt>Assigned zone</dt><dd>${escape(profile.assigned_zone ?? '—')}</dd></div>
          <div><dt>Employment status</dt><dd>${escape(profile.employment_status)}</dd></div>
          <div><dt>Current workload</dt><dd>${escape(profile.current_workload)}</dd></div>
          <div><dt>Daily work limit</dt><dd>${escape(profile.daily_work_limit_minutes)} min</dd></div>
          <div><dt>Standby</dt><dd>${profile.standby_status ? 'Yes' : 'No'}</dd></div></dl></section>
        <section class="card workforce-section"><header class="workforce-heading"><h2>Skills</h2>
          <button class="primary" data-add-skill>Add Skill</button></header>
          ${assignments.length
            ? `<ul class="worker-skills">${assignments.map(item => `<li>${escape(item.skill.skill_name)}</li>`).join('')}</ul>`
            : '<p class="empty">No skills added.</p>'}</section>
        ${certificationSection(certificates)}
        <section class="card workforce-section" data-worker-availability></section>`;
      content.querySelector('[data-back]').onclick = directory;
      const updated = message => openWorker(worker, message);
      content.querySelector('[data-profile]').onclick = () => editProfile(profile, updated);
      content.querySelector('[data-add-skill]').onclick = () => addSkill(worker.worker_id, updated);
      bindCertifications(content, client, worker.worker_id, certificates, updated);
      mountWorkerAvailability(content.querySelector('[data-worker-availability]'), client, worker.worker_id);
    } catch (error) {
      failure(error, () => openWorker(worker));
    }
  }

  function editProfile(profile, updated) {
    openForm(content, 'Edit worker profile', `${field('Job role', 'job_role', profile.job_role, 'maxlength="120"')}
      ${field('Assigned zone', 'assigned_zone', profile.assigned_zone, 'maxlength="120"')}
      ${field('Employment status', 'employment_status', profile.employment_status, 'required maxlength="60"')}
      ${field('Current workload', 'current_workload', profile.current_workload, 'type="number" min="0" max="2147483647" step="1" required')}
      ${field('Daily work limit (minutes)', 'daily_work_limit_minutes', profile.daily_work_limit_minutes, 'type="number" min="1" max="1440" step="1" required')}
      ${checkbox('Available for standby', 'standby_status', profile.standby_status)}`,
    values => write(client.from('worker_profile').update({
      job_role: optional(values.get('job_role')),
      assigned_zone: optional(values.get('assigned_zone')),
      employment_status: values.get('employment_status').trim(),
      current_workload: Number(values.get('current_workload')),
      daily_work_limit_minutes: Number(values.get('daily_work_limit_minutes')),
      standby_status: values.has('standby_status'),
    }).eq('worker_id', profile.worker_id), 'worker_id'), () => updated('Worker profile saved.'));
  }

  function addSkill(workerId, updated) {
    openForm(content, 'Add skill', field('Skill name', 'skill_name', '', 'required maxlength="120"'),
      async values => {
        const name = optional(values.get('skill_name'));
        if (!name) throw new Error('Enter a skill name.');
        await result(client.rpc('add_worker_skill', { target_worker: workerId, name }));
      }, () => updated('Skill added.'), 'Add skill');
  }

  directory();
}
