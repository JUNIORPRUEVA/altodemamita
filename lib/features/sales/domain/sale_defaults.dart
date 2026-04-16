class SaleDefaults {
  const SaleDefaults({
    required this.downPaymentPercentage,
    required this.monthlyInterest,
    required this.installmentCount,
  });

  final double downPaymentPercentage;
  final double monthlyInterest;
  final int installmentCount;
}