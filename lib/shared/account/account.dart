enum AccountRole {
  superAdministrator('super_administrator', 'Super Administrator'),
  administrator('administrator', 'Administrator'),
  worker('worker', 'Worker'),
  reporter('reporter', 'Reporter');

  const AccountRole(this.value, this.label);
  final String value, label;
  bool get isAdministrator =>
      this == administrator || this == superAdministrator;
}

class Account {
  const Account({
    required this.id,
    required this.employeeId,
    required this.email,
    required this.name,
    required this.phone,
    required this.role,
  });

  final String id, employeeId, email, name, phone;
  final AccountRole role;

  Account withContact({required String name, required String phone}) => Account(
    id: id,
    employeeId: employeeId,
    email: email,
    name: name,
    phone: phone,
    role: role,
  );
}
