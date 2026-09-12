class SettlementQuote {
  const SettlementQuote({
    required this.saleId,
    required this.asOfDate,
    required this.principalOutstanding,
    required this.dueInterest,
    required this.lateFees,
    required this.futureInterestWaived,
    required this.settlementAmount,
    required this.quoteVersion,
  });

  final String saleId;
  final DateTime asOfDate;
  final double principalOutstanding;
  final double dueInterest;
  final double lateFees;
  final double futureInterestWaived;
  final double settlementAmount;
  final String quoteVersion;

  factory SettlementQuote.fromMap(Map<String, dynamic> map) {
    return SettlementQuote(
      saleId: map['saleId']?.toString() ?? '',
      asOfDate:
          DateTime.tryParse(map['asOfDate']?.toString() ?? '') ??
          DateTime.now(),
      principalOutstanding: _toDouble(map['principalOutstanding']),
      dueInterest: _toDouble(map['dueInterest']),
      lateFees: _toDouble(map['lateFees']),
      futureInterestWaived: _toDouble(map['futureInterestWaived']),
      settlementAmount: _toDouble(map['settlementAmount']),
      quoteVersion: map['quoteVersion']?.toString() ?? '',
    );
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
