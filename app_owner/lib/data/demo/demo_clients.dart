// Demo clients data (50 items)
final List<Map<String, dynamic>> demoClients = List.generate(50, (i) {
	final id = i + 1;
	return {
		'id': id,
		'name': 'Cliente $id',
		'document': '000$id',
		'phone': '+1-809-555-${(1000 + id).toString().padLeft(4, '0')}',
		'address': 'Calle $id, Ciudad',
		'updatedAt': DateTime.now().subtract(Duration(days: id)).toIso8601String(),
	};
});
