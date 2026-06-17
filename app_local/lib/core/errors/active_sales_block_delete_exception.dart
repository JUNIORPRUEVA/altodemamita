/// Thrown when attempting to delete an entity that has one or more
/// active sales referencing it (client, seller, or product/lot).
///
/// "Active sale" means: deleted_at IS NULL and estado is not in the
/// cancelled/voided set.
class ActiveSalesBlockDeleteException implements Exception {
  const ActiveSalesBlockDeleteException(this.message);

  final String message;

  @override
  String toString() => message;
}
