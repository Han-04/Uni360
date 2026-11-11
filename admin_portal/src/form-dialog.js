export function openForm(content, title, fields, save, saved, submitLabel = 'Save changes') {
  const modal = document.createElement('dialog');
  modal.setAttribute('aria-labelledby', 'record-dialog-title');
  modal.innerHTML = `<form><h2 id="record-dialog-title">${title}</h2>${fields}
    <p class="error" role="alert"></p><div class="dialog-actions">
    <button class="secondary" type="button" data-cancel>${save ? 'Cancel' : 'Close'}</button>
    ${save ? `<button class="primary">${submitLabel}</button>` : ''}</div></form>`;
  content.append(modal);
  const form = modal.querySelector('form');
  const cancel = form.querySelector('[data-cancel]');
  let saving = false;
  cancel.onclick = () => modal.close();
  modal.addEventListener('cancel', event => { if (saving) event.preventDefault(); });
  modal.addEventListener('close', () => modal.remove(), { once: true });
  form.onsubmit = async event => {
    event.preventDefault();
    if (saving || !save) return;
    const values = new FormData(form);
    const controls = [...form.elements];
    const errorBox = form.querySelector('[role=alert]');
    saving = true;
    controls.forEach(control => { control.disabled = true; });
    errorBox.textContent = '';
    try {
      await save(values);
      modal.close();
      saved();
    } catch (error) {
      errorBox.textContent = error.message;
    } finally {
      saving = false;
      controls.forEach(control => { control.disabled = false; });
    }
  };
  modal.showModal();
  return modal;
}
