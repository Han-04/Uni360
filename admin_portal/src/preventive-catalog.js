import { openForm } from './form-dialog.js';
import { escape } from './html.js';
import { mountFacilitySchedules } from './facility-schedules.js';
import { taskCategory, taskChecklists, taskJobRoles } from './task-checklists.js';
import { reviewSchedule, scheduleTemplate } from './task-scheduler.js';
import './preventive-catalog.css';

const pageSize = 25;
const types = {
  building: 'Building', floor: 'Floor', room: 'Room', outdoor_area: 'Outdoor area', asset: 'Asset', other: 'Other',
};
const catalogs = {
  facilities: {
    table: 'preventive_facility', heading: 'Facilities', noun: 'facility', name: 'name', detail: 'Type',
    fields: 'id,name,zone_id,parent_id,facility_type,metadata,is_active,effective_active:preventive_facility_is_active',
    description: 'Open a building to see its floors and rooms.',
    subtitle: row => types[row.facility_type],
  },
  tasks: {
    table: 'preventive_task_definition', heading: 'Schedule Task', noun: 'task template', name: 'title', detail: 'Category',
    fields: 'id,title,category,zone_id,instructions,required_job_role,checklist,is_active,duration_minutes',
    description: 'Manage task templates, set recurring times, and review staff assignments.',
    subtitle: taskCategory,
  },
};

const option = (value, text, selected) =>
  `<option value="${escape(value)}" ${value === selected ? 'selected' : ''}>${escape(text)}</option>`;
const input = (label, name, value, attributes = '') =>
  `<label>${label}<input name="${name}" value="${escape(value)}" ${attributes}></label>`;
const area = (label, name, value, attributes = '') =>
  `<label>${label}<textarea name="${name}" rows="3" ${attributes}>${escape(value)}</textarea></label>`;
const textValue = (values, name) => String(values.get(name) ?? '').trim();
const valueOrNull = (values, name) => textValue(values, name) || null;

async function read(query) {
  const { data, error } = await query;
  if (!error) return data;
  if (error.code === '42501') throw new Error('Your account does not have access to make this change.');
  if (error.code === '23503') throw new Error('Choose a valid zone or parent facility.');
  if (error.code === '23514') throw new Error('Check the values. A facility cannot be placed under itself or a descendant.');
  if (['PGRST204', 'PGRST205', '42703'].includes(error.code)) {
    throw new Error('Apply the facility and task management migration in Supabase to use this page.');
  }
  throw new Error('Supabase could not complete the request. Please try again.');
}

async function allOptions(table, columns, order, idField = 'id', filter = query => query) {
  const rows = [];
  const batchSize = 500;
  for (let offset = 0; ; offset += batchSize) {
    const batch = await read(filter(table.select(columns)).order(order).order(idField).range(offset, offset + batchSize - 1));
    rows.push(...batch);
    if (batch.length < batchSize) return rows;
  }
}

export function mountPreventiveCatalog(content, client, kind, superAdmin) {
  const catalog = catalogs[kind];
  const isFacility = kind === 'facilities';
  let search = '';
  let page = 0;
  let zones = [];
  let trail = [];
  let standalone = false;
  let opening = false;
  const table = () => client.from(catalog.table);
  const loadLocations = () => allOptions(client.from('preventive_facility'), catalogs.facilities.fields, 'name');
  const zoneName = id => id ? zones.find(zone => zone.id === id)?.name ?? 'Assigned zone' : 'Campus-wide';

  async function descendants(parentId) {
    const children = new Map();
    const seen = new Set([parentId]);
    let parents = [parentId];
    while (parents.length) {
      const next = [];
      // Limit each filter to a small set of UUIDs so the request URL stays short.
      for (let start = 0; start < parents.length; start += 40) {
        const ids = parents.slice(start, start + 40);
        const rows = await allOptions(table(), catalog.fields, 'name', 'id', query => query.in('parent_id', ids));
        for (const row of rows) {
          if (seen.has(row.id)) continue;
          seen.add(row.id);
          if (!children.has(row.parent_id)) children.set(row.parent_id, []);
          children.get(row.parent_id).push(row);
          next.push(row.id);
        }
      }
      parents = next;
    }
    return children;
  }

  function navigate(nextTrail, otherLocations = false) {
    trail = nextTrail;
    standalone = otherLocations;
    page = 0;
    search = '';
    load();
  }

  function breadcrumb() {
    if (!trail.length) return '';
    return `<nav class="facility-breadcrumb" aria-label="Facility path">
      <button class="text-button" data-ancestor="0">${standalone ? 'Other locations' : 'Facilities'}</button>
      ${trail.map((row, index) => `<span aria-hidden="true">/</span>` + (index === trail.length - 1
        ? `<span aria-current="location">${escape(row.name)}</span>`
        : `<button class="text-button" data-ancestor="${index + 1}">${escape(row.name)}</button>`)).join('')}
    </nav>`;
  }

  function bindBreadcrumb() {
    content.querySelectorAll('[data-ancestor]').forEach(button => {
      button.onclick = () => navigate(trail.slice(0, Number(button.dataset.ancestor)), standalone);
    });
  }

  async function load(message = '') {
    const location = trail.at(-1);
    const heading = location?.name ?? (standalone ? 'Other locations' : catalog.heading);
    content.innerHTML = `<header class="section-head"><h1>${escape(heading)}</h1></header><p class="muted" role="status">Loading…</p>`;
    try {
      let listing;
      if (location) {
        listing = descendants(location.id).then(children => flattenFacilities(children, trail, search));
      } else {
        let query = table().select(catalog.fields).order(catalog.name).order('id').range(page * pageSize, (page + 1) * pageSize);
        if (isFacility) {
          query = query.is('parent_id', null);
          query = standalone ? query.neq('facility_type', 'building') : query.eq('facility_type', 'building');
        }
        if (search) query = query.ilike(catalog.name, `%${search.replace(/[\\%_]/g, '\\$&')}%`);
        listing = read(query).then(rows => rows.map(row => ({ row, path: [row], depth: 0 })));
      }
      const [entries, availableZones] = await Promise.all([
        listing,
        allOptions(client.from('preventive_zone'), 'id,name', 'name'),
      ]);
      if (!content.isConnected) return;
      zones = availableZones;
      const createAllowed = zones.length || (!isFacility && superAdmin);
      const description = location ? 'Floors, rooms and other spaces in this location.' :
        standalone ? 'Outdoor areas and other standalone facilities.' : catalog.description;
      const visible = location ? entries : entries.slice(0, pageSize);
      const createLabel = location ? 'Add sub-location' : `Create ${catalog.noun}`;
      content.innerHTML = `${breadcrumb()}<header class="section-head"><div><h1>${escape(heading)}</h1><p class="muted">${description}</p></div>
        <div class="workforce-actions">${isFacility && !location ? `<button class="secondary" data-root-view>${standalone ? 'Buildings' : 'Other locations'}</button>` : ''}
        ${location ? '<button class="secondary" data-location-schedules>Schedules for this location</button>' : ''}
        ${!isFacility ? '<button class="secondary" data-auto-schedule>Review auto schedule</button>' : ''}
        <button class="primary" data-create ${createAllowed ? '' : 'disabled'}>${createLabel}</button></div></header>
        ${createAllowed ? '' : '<p class="muted catalog-note">A zone is required to create records here.</p>'}
        <div class="card"><form class="toolbar"><label><span class="sr-only">Search ${kind}</span>
        <input type="search" name="search" maxlength="120" value="${escape(search)}" placeholder="Search by ${catalog.name}"></label>
        <button class="secondary">Search</button></form>
        <p class="feedback" role="status">${escape(message)}</p>
        <p class="error catalog-error" role="alert"></p>
        <div class="table-scroll"><table><thead><tr><th>${isFacility ? 'Name' : 'Title'}</th>
        <th>${catalog.detail}</th><th>Zone</th><th>Status</th><th>Actions</th></tr></thead>
        <tbody>${visible.map(renderRow).join('') ||
          `<tr><td colspan="5" class="empty">${location && !search ? 'No sub-locations yet.' : `No matching ${kind}.`}</td></tr>`}</tbody></table></div>
        ${location ? '' : `<footer class="pagination"><span>Page ${page + 1}</span>
        <button class="secondary" data-previous ${page ? '' : 'disabled'}>Previous</button>
        <button class="secondary" data-next ${entries.length > pageSize ? '' : 'disabled'}>Next</button></footer>`}</div>`;
      content.querySelector('form').onsubmit = event => {
        event.preventDefault();
        search = textValue(new FormData(event.currentTarget), 'search');
        page = 0;
        load();
      };
      bindBreadcrumb();
      content.querySelector('[data-create]').onclick = () => edit();
      if (!isFacility) {
        content.querySelector('[data-auto-schedule]').onclick = () => {
          if (!opening) reviewSchedule(content, client, zones, loadLocations, load);
        };
      }
      if (location) {
        content.querySelector('[data-location-schedules]').onclick = () =>
          mountFacilitySchedules(content, client, location, load, trail);
      } else {
        const rootView = content.querySelector('[data-root-view]');
        if (rootView) rootView.onclick = () => navigate([], !standalone);
        content.querySelector('[data-previous]').onclick = () => { page--; load(); };
        content.querySelector('[data-next]').onclick = () => { page++; load(); };
      }
      content.querySelectorAll('[data-action]').forEach(button => {
        const { row, path } = visible[Number(button.dataset.row)];
        button.onclick = () => {
          if (opening) return;
          if (button.dataset.action === 'open') navigate(path, standalone);
          if (button.dataset.action === 'view') view(row, path.at(-2));
          if (button.dataset.action === 'edit') edit(row);
          if (button.dataset.action === 'deactivate') deactivate(row);
          if (button.dataset.action === 'schedules') mountFacilitySchedules(content, client, row, load, path);
          if (button.dataset.action === 'schedule-template') schedule(row);
        };
      });
    } catch (error) {
      if (!content.isConnected) return;
      content.innerHTML = `${breadcrumb()}<header class="section-head"><h1>${escape(heading)}</h1></header>
        <p class="error" role="alert">${escape(error.message)}</p><button class="secondary" data-retry>Retry</button>`;
      bindBreadcrumb();
      content.querySelector('[data-retry]').onclick = () => load();
    }
  }

  function renderRow({ row, depth, hasChildren }, index) {
    const active = row.is_active && row.effective_active !== false;
    const status = !row.is_active ? 'Inactive' : active ? 'Active' : 'Parent inactive';
    const browsable = isFacility && (hasChildren === undefined || hasChildren || ['building', 'floor'].includes(row.facility_type));
    const name = escape(row[catalog.name]);
    return `<tr><td><div class="facility-row-name" style="--facility-depth: ${Math.min(depth, 6)}">
      ${browsable ? `<button class="text-button facility-open" data-action="open" data-row="${index}">${name} <span aria-hidden="true">›</span></button>`
        : `<strong>${name}</strong>`}</div></td><td>${escape(catalog.subtitle(row))}</td>
      <td>${escape(zoneName(row.zone_id))}</td><td><span class="badge ${active ? 'active' : ''}">${status}</span></td>
      <td class="actions"><button class="text-button" data-action="view" data-row="${index}">View</button>
      <button class="text-button" data-action="edit" data-row="${index}">Edit</button>
      ${isFacility ? `<button class="text-button" data-action="schedules" data-row="${index}">Schedules</button>` : ''}
      ${!isFacility && row.is_active ? `<button class="text-button" data-action="schedule-template" data-row="${index}">Schedule</button>` : ''}
      ${row.is_active ? `<button class="text-button danger" data-action="deactivate" data-row="${index}">Deactivate</button>` : ''}</td></tr>`;
  }

  function view(row, parent) {
    const fields = isFacility
      ? `<p>${escape(types[row.facility_type])} · ${escape(zoneName(row.zone_id))}</p>
        <p>Parent facility · ${escape(parent?.name ?? 'None')}</p>
        <label>Facility details</label><pre class="catalog-metadata">${escape(JSON.stringify(row.metadata, null, 2))}</pre>`
      : `<p>${escape(taskCategory(row))} · ${escape(zoneName(row.zone_id))}</p>
        <p class="catalog-instructions">${escape(row.instructions)}</p>
        <p>Work time · ${row.duration_minutes} min</p>
        <p>Required job role · ${escape(row.required_job_role ?? 'Any')}</p>
        ${row.checklist.length ? `<ol>${row.checklist.map(item => `<li>${escape(item)}</li>`).join('')}</ol>` : ''}`;
    openForm(content, escape(row[catalog.name]), fields);
  }

  function zoneField(row) {
    if (row) return `<p class="muted">${escape(zoneName(row.zone_id))}</p>${row.zone_id ? '' :
      '<p class="muted">Changes to this shared template apply to future work orders across its facilities.</p>'}`;
    return `<label>Zone<select name="zone_id" ${isFacility || !superAdmin ? 'required' : ''}>
      ${!isFacility && superAdmin ? option('', 'Campus-wide', '') : option('', 'Choose a zone', '')}
      ${zones.map(zone => option(zone.id, zone.name)).join('')}</select></label>`;
  }

  async function edit(row) {
    if (opening) return;
    opening = true;
    const errorBox = content.querySelector('.catalog-error');
    errorBox.textContent = '';
    try {
      const parent = !row ? trail.at(-1) : undefined;
      const lookup = isFacility
        ? row ? await allOptions(table(), 'id,name,zone_id,effective_active:preventive_facility_is_active',
          'name', 'id', query => query.eq('zone_id', row.zone_id)) : []
        : await allOptions(client.from('worker_profile'), 'job_role', 'job_role', 'worker_id');
      if (!content.isConnected || !errorBox.isConnected) return;
      const defaultType = parent ? 'room' : standalone ? 'outdoor_area' : 'building';
      const fields = isFacility ? facilityFields(row, defaultType) : taskFields(row, lookup);
      const scope = parent ? `<p class="muted">Inside ${escape(parent.name)}</p>` : zoneField(row);
      const dialog = openForm(content, `${row ? 'Edit' : 'Create'} ${catalog.noun}`, scope + fields, async values => {
        const payload = isFacility ? facilityValues(values) : taskValues(values);
        if (!row) {
          payload.zone_id = parent?.zone_id ?? valueOrNull(values, 'zone_id');
          if (isFacility) payload.parent_id = parent?.id ?? null;
        }
        await write(row ? table().update(payload).eq('id', row.id) : table().insert(payload));
        if (isFacility && !row && !parent) standalone = payload.facility_type !== 'building';
      }, () => {
        if (!row) { search = ''; page = 0; }
        load(row ? 'Changes saved.' : 'Record created.');
      }, row ? 'Save changes' : `Create ${catalog.noun}`);
      if (isFacility && row) {
        const parentSelect = dialog.querySelector('[name=parent_id]');
        const available = lookup.filter(facility =>
          facility.id !== row.id && (facility.effective_active || facility.id === row.parent_id));
        parentSelect.innerHTML = option('', 'No parent', row.parent_id ?? '') +
          available.map(facility => option(facility.id, facility.name, row.parent_id)).join('');
      } else if (!isFacility) {
        bindTaskChecklist(dialog, row);
      }
    } catch (error) {
      errorBox.textContent = error.message;
    } finally {
      opening = false;
    }
  }

  async function schedule(row) {
    opening = true;
    const errorBox = content.querySelector('.catalog-error');
    errorBox.textContent = '';
    try {
      const facilities = await loadLocations();
      if (errorBox.isConnected) scheduleTemplate(content, client, row, facilities, () => load());
    } catch (error) {
      if (errorBox.isConnected) errorBox.textContent = error.message;
    } finally {
      opening = false;
    }
  }

  function deactivate(row) {
    const impact = isFacility
      ? 'New work orders will be blocked for this facility and its sub-locations.'
      : 'New work orders will be blocked for schedules that use this template.';
    openForm(content, `Deactivate ${catalog.noun}?`,
      `<p><strong>${escape(row[catalog.name])}</strong></p><p>${impact} Existing work orders will be kept.</p>`,
      () => write(table().update({ is_active: false }).eq('id', row.id).eq('is_active', true)),
      () => load('Record deactivated.'), 'Deactivate');
  }

  async function write(query) {
    const saved = await read(query.select('id').maybeSingle());
    if (!saved) throw new Error('This record has changed or is unavailable. Refresh the list and try again.');
  }

  load();
}

function flattenFacilities(children, trail, search) {
  const term = search.toLowerCase();
  function branch(path, depth) {
    return (children.get(path.at(-1).id) ?? []).flatMap(row => {
      const childPath = [...path, row];
      const nested = branch(childPath, depth + 1);
      if (!row.name.toLowerCase().includes(term) && !nested.length) return [];
      return [{ row, path: childPath, depth, hasChildren: children.has(row.id) }, ...nested];
    });
  }
  return branch(trail, 0);
}

function facilityFields(row, defaultType) {
  return input('Name', 'name', row?.name, 'required maxlength="120"') +
    `<label>Type<select name="facility_type">${Object.entries(types)
      .map(([value, label]) => option(value, label, row?.facility_type ?? defaultType)).join('')}</select></label>` +
    (row ? '<label>Parent facility<select name="parent_id"></select></label>' : '') +
    `<label class="check-field"><input type="checkbox" name="toilet" ${row?.metadata.room_type === 'toilet' ? 'checked' : ''}>Toilet room</label>` +
    `<details><summary>Additional facility details</summary>${area('Metadata (JSON object)', 'metadata',
      row && Object.keys(row.metadata).length ? JSON.stringify(row.metadata, null, 2) : '',
      'placeholder=\'{"floors": 3}\'')}</details>`;
}

function facilityValues(values) {
  let metadata;
  try {
    metadata = JSON.parse(textValue(values, 'metadata') || '{}');
  } catch {
    throw new Error('Enter facility details as a valid JSON object.');
  }
  if (!metadata || typeof metadata !== 'object' || Array.isArray(metadata)) {
    throw new Error('Enter facility details as a JSON object.');
  }
  const facilityType = values.get('facility_type');
  if (values.has('toilet') && facilityType !== 'room') throw new Error('Choose Room as the facility type for a toilet.');
  if (values.has('toilet')) metadata.room_type = 'toilet';
  else if (metadata.room_type === 'toilet') delete metadata.room_type;
  return {
    name: requiredText(values, 'name', 'a name'),
    facility_type: facilityType,
    parent_id: valueOrNull(values, 'parent_id'),
    metadata,
  };
}

function taskFields(row, workers) {
  const selectedCategory = taskCategory(row);
  const categories = [...new Set([...Object.keys(taskChecklists), selectedCategory].filter(Boolean))];
  const roles = [...new Set([...taskJobRoles, ...workers.map(worker => worker.job_role), row?.required_job_role]
    .filter(Boolean))].sort((first, second) => first.localeCompare(second));
  return input('Title', 'title', row?.title, 'required maxlength="120"') +
    `<label>Category<select name="category" required>${option('', 'Choose a category', selectedCategory)}
    ${categories.map(category => option(category, category, selectedCategory)).join('')}</select></label>` +
    area('Instructions', 'instructions', row?.instructions, 'required maxlength="4000"') +
    input('Work time (minutes)', 'duration_minutes', row?.duration_minutes ?? 30, 'type="number" min="1" max="720" step="1" required') +
    `<fieldset class="task-checklist"><legend>Checklist</legend><div data-checklist></div></fieldset>
    <label>Required job role<select name="required_job_role">${option('', 'Any job role', row?.required_job_role ?? '')}
    ${roles.map(role => option(role, role, row?.required_job_role)).join('')}</select></label>`;
}

function bindTaskChecklist(dialog, row) {
  const category = dialog.querySelector('[name=category]');
  const checklist = dialog.querySelector('[data-checklist]');
  const originalCategory = taskCategory(row);
  const savedItems = row?.checklist ?? [];
  const selections = new Map([[originalCategory, savedItems]]);
  let currentCategory = category.value;

  function render() {
    const defaults = Object.hasOwn(taskChecklists, currentCategory) ? taskChecklists[currentCategory] : [];
    const existing = currentCategory === originalCategory ? savedItems : [];
    const items = [...new Set([...existing, ...defaults])];
    const selected = new Set(selections.get(currentCategory));
    checklist.innerHTML = items.map(item =>
      `<label class="check-field"><input type="checkbox" name="checklist" value="${escape(item)}"
        ${selected.has(item) ? 'checked' : ''}>${escape(item)}</label>`
    ).join('') || `<p class="muted">${currentCategory ? 'No checklist options for this category.' : 'Choose a category to see checklist options.'}</p>`;
  }

  category.onchange = () => {
    selections.set(currentCategory, Array.from(checklist.querySelectorAll(':checked'), checkbox => checkbox.value));
    currentCategory = category.value;
    render();
  };
  render();
}

function taskValues(values) {
  return {
    title: requiredText(values, 'title', 'a title'),
    category: requiredText(values, 'category', 'a category'),
    instructions: requiredText(values, 'instructions', 'instructions'),
    checklist: values.getAll('checklist'),
    required_job_role: valueOrNull(values, 'required_job_role'),
    required_skill_id: null,
    duration_minutes: Number(values.get('duration_minutes')),
  };
}

function requiredText(values, name, label) {
  const value = textValue(values, name);
  if (!value) throw new Error(`Enter ${label}.`);
  return value;
}
