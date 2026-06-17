// Demo sales data (50 items)
final List<Map<String, dynamic>> demoSales = List.generate(50, (i) {
	final id = i + 1;
	final total = 10000 + id * 250;
	final initialPaid = (id % 5 == 0) ? (total * 0.5).toInt() : (total * 0.1).toInt();
	final balance = total - initialPaid;
	return {
		'id': id,
		'syncId': 'S-${1000 + id}',
		'status': (i % 4 == 0) ? 'Completado' : 'Pendiente',
		'total': total,
		'initialPaid': initialPaid,
		'balance': balance,
		'saleDate': DateTime.now().subtract(Duration(days: id)).toIso8601String(),
	};
});
