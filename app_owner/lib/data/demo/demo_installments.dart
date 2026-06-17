// Demo installments data (50 items)
final List<Map<String, dynamic>> demoInstallments = List.generate(50, (i) {
	final id = i + 1;
	final total = 200 + id * 10;
	final paid = (i % 4 == 0) ? total : (total * 0.3).toInt();
	return {
		'id': id,
		'installmentNumber': id,
		'status': (i % 5 == 0) ? 'Atrasada' : 'Activa',
		'totalAmount': total,
		'paidAmount': paid,
		'endingBalance': total - paid,
		'dueDate': DateTime.now().add(Duration(days: id * 15)).toIso8601String(),
	};
});
