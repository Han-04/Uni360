import { openForm } from './form-dialog.js';
import { escape } from './html.js';
import { checkbox, field, optional, write } from './workforce-form.js';

const bucket = 'worker-certificates';
const fileTypes = new Map([
  ['image/jpeg', 'jpg'], ['image/png', 'png'], ['image/webp', 'webp'], ['application/pdf', 'pdf'],
]);

export function certificationSection(certificates) {
  return `<section class="card workforce-section" data-certificates>
    <header class="workforce-heading"><h2>Certifications</h2><button class="primary" data-add-cert>Add Certifications</button></header>
    <p class="error certificate-error" role="alert"></p>
    <div class="table-scroll"><table><thead><tr><th>Certification</th><th>Certificate ID</th><th>Expiry</th><th>Verification</th><th></th></tr></thead>
    <tbody>${certificates.map((certificate, index) => `<tr>
      <td><strong>${escape(certificate.certification_name)}</strong></td>
      <td><span class="certificate-id">${escape(certificate.certification_no ?? '—')}
      ${certificate.document_path ? `<button class="text-button certificate-file" data-document="${index}"
        title="Open certificate document" aria-label="Open certificate document for ${escape(certificate.certification_name)}">
        <span aria-hidden="true">${certificate.document_path.endsWith('.pdf') ? 'PDF' : '▧'}</span>
      </button>` : ''}</span></td>
      <td>${escape(certificate.expiry_date ?? '—')}</td>
      <td><span class="badge ${certificate.verified ? 'active' : ''}">${certificate.verified ? 'Verified' : 'Pending'}</span></td>
      <td><button class="text-button" data-cert="${index}">Edit certification</button></td></tr>`).join('')
      || '<tr><td colspan="5" class="empty">No certifications added.</td></tr>'}
    </tbody></table></div></section>`;
}

export function bindCertifications(content, client, workerId, certificates, updated) {
  const section = content.querySelector('[data-certificates]');
  const storage = client.storage.from(bucket);
  const errorBox = section.querySelector('[role=alert]');
  section.querySelector('[data-add-cert]').onclick = () => editCertificate();
  section.querySelectorAll('[data-cert]').forEach(button => {
    button.onclick = () => editCertificate(certificates[Number(button.dataset.cert)]);
  });
  section.querySelectorAll('[data-document]').forEach(button => {
    button.onclick = async () => {
      errorBox.textContent = '';
      const viewer = window.open('', '_blank');
      if (!viewer) {
        errorBox.textContent = 'Allow pop-ups for Uni360 to open the certificate.';
        return;
      }
      viewer.opener = null;
      try {
        const { data, error } = await storage.createSignedUrl(certificates[Number(button.dataset.document)].document_path, 120);
        if (error || !data?.signedUrl) throw new Error('Certificate unavailable');
        viewer.location.replace(data.signedUrl);
      } catch {
        viewer.close();
        errorBox.textContent = 'Could not open this certificate. Please try again.';
      }
    };
  });

  function editCertificate(certificate) {
    const certificateId = certificate?.certification_id ?? crypto.randomUUID();
    openForm(content, certificate ? 'Edit certification' : 'Add certification', `
      ${field('Certification name', 'certification_name', certificate?.certification_name, 'required maxlength="160"')}
      ${field('Certificate ID', 'certification_no', certificate?.certification_no, 'maxlength="120"')}
      ${field('Expiry date', 'expiry_date', certificate?.expiry_date, 'type="date"')}
      ${checkbox('Verified', 'verified', certificate?.verified)}
      <label>${certificate?.document_path ? 'Replace document' : 'Upload certificate'}
        <input type="file" name="document" accept="image/jpeg,image/png,image/webp,application/pdf">
        <span class="muted">JPG, PNG, WebP or PDF, up to 10 MB.</span></label>`,
    async values => {
      const name = optional(values.get('certification_name'));
      if (!name) throw new Error('Enter a certification name.');
      const file = values.get('document');
      const oldPath = certificate?.document_path ?? null;
      let path = oldPath;
      if (file?.name) {
        const extension = fileTypes.get(file.type);
        if (!extension || !file.size || file.size > 10485760) {
          throw new Error('Choose a JPG, PNG, WebP or PDF file up to 10 MB.');
        }
        path = `${workerId}/${certificateId}/${crypto.randomUUID()}.${extension}`;
        const { error } = await storage.upload(path, file, { contentType: file.type, cacheControl: '0' });
        if (error) throw new Error('Could not upload the certificate. Please try again.');
      }
      const changes = {
        certification_name: name,
        certification_no: optional(values.get('certification_no')),
        expiry_date: optional(values.get('expiry_date')),
        verified: values.has('verified'),
        document_path: path,
      };
      const table = client.from('worker_certification');
      try {
        await write(certificate
          ? table.update(changes).eq('worker_id', workerId).eq('certification_id', certificateId)
          : table.insert({ ...changes, worker_id: workerId, certification_id: certificateId }), 'certification_id');
      } catch (error) {
        if (path && path !== oldPath) await storage.remove([path]).catch(() => {});
        throw error;
      }
      if (oldPath && oldPath !== path) await storage.remove([oldPath]).catch(() => {});
    }, () => updated('Certification saved.'));
  }
}
