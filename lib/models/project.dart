class Project {
  final String id;
  final String name;
  final String? client;
  final DateTime createdAt;

  Project({
    required this.id,
    required this.name,
    this.client,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'client': client,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Project.fromMap(Map<String, dynamic> map) => Project(
        id: map['id'],
        name: map['name'],
        client: map['client'],
        createdAt: DateTime.parse(map['createdAt']),
      );
}
