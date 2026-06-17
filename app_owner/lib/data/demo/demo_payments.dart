// Demo payments data (50 items)
final List<Map<String, dynamic>> demoPayments = List.generate(50, (i) {
	final id = i + 1;
	return {
		'id': id,
		'amount': (100 + id * 20),
		'method': (i % 2 == 0) ? 'Efectivo' : 'Transferencia',
		'paymentType': (i % 3 == 0) ? 'Cuota' : 'Extra',
		'paidAt': DateTime.now().subtract(Duration(days: id)).toIso8601String(),
		'reference': 'REF${10000 + id}',
		'yearToPay': DateTime.now().year.toString(),
	};
});
