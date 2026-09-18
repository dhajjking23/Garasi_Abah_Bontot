class UserModel {
  final int? id;
  final String nama;
  final String username;
  final String passwordHash;
  final String role; // OWNER_ADMIN | VIEWER
  final String status; // ACTIVE | NONAKTIF
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserModel({
    this.id,
    required this.nama,
    required this.username,
    required this.passwordHash,
    required this.role,
    this.status = 'ACTIVE',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isOwnerAdmin => role == 'OWNER_ADMIN';
  bool get isViewer => role == 'VIEWER';
  bool get isActive => status == 'ACTIVE';

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as int?,
      nama: map['nama'] as String,
      username: map['username'] as String,
      passwordHash: map['password_hash'] as String,
      role: map['role'] as String,
      status: map['status'] as String? ?? 'ACTIVE',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nama': nama,
      'username': username,
      'password_hash': passwordHash,
      'role': role,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? nama,
    String? username,
    String? passwordHash,
    String? role,
    String? status,
    DateTime? updatedAt,
  }) {
    return UserModel(
      id: id,
      nama: nama ?? this.nama,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      role: role ?? this.role,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
