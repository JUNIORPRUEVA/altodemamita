// Demo lots / solares data (50 items)
final List<Map<String, dynamic>> demoLots = List.generate(50, (i) {
	final id = i + 1;
	return {
		'id': id,
		'number': id,
		'block': (id % 10) + 1,
		'status': (i % 3 == 0) ? 'Disponible' : (i % 3 == 1) ? 'Reservado' : 'Vendido',
		'area': 100 + id * 2,
		'price': 500 + id * 10,
		'updatedAt': DateTime.now().subtract(Duration(days: id)).toIso8601String(),
	};
});
