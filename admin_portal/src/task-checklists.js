export const taskChecklists = {
  'Toilet Cleaning': [
    'Clean fixtures',
    'Mop floor',
    'Refill soap and paper',
    'Empty waste bins',
    'Report leaks or damaged fixtures',
  ],
  'Security Patrol': [
    'Check entrances and exits',
    'Check doors and gates',
    'Inspect corridors and common areas',
    'Record incidents or hazards',
  ],
  'Facility Safety Inspection': [
    'Check lighting',
    'Check exit access',
    'Record defects',
    'Inspect floors and walkways',
  ],
  'Gardening and Weeding': [
    'Remove weeds',
    'Water plants',
    'Trim overgrowth',
    'Clear garden waste',
    'Report damaged plants or equipment',
  ],
  'Mosquito Control Site Check': [
    'Check for standing water',
    'Record affected locations',
    'Submit site notes',
    'Check drains and gutters',
  ],
};

export const taskJobRoles = [
  'Cleaner',
  'Facilities Maintenance Technician',
  'Gardener',
  'Pest Control Technician',
  'Security Guard',
];

const earlierCategories = {
  'Toilet Cleaning': 'Cleaning',
  'Facility Safety Inspection': 'Inspection',
  'Mosquito Control Site Check': 'Pest Control',
};

export function taskCategory(task) {
  if (!task) return '';
  return Object.hasOwn(earlierCategories, task.title) && earlierCategories[task.title] === task.category
    ? task.title
    : task.category;
}
