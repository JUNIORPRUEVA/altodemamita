import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_solares_ui/features/shell/admin_shell.dart';

void main() {
  test('el shell entra en modo escritorio desde anchos de laptop', () {
    expect(isCompactShellWidth(759), isTrue);
    expect(isCompactShellWidth(760), isFalse);

    expect(isDesktopShellWidth(1023), isFalse);
    expect(isDesktopShellWidth(1024), isTrue);

    expect(shellSidebarWidthFor(1023), 0);
    expect(shellSidebarWidthFor(1024), shellSidebarLaptopWidth);
    expect(shellSidebarWidthFor(1366), shellSidebarDesktopWidth);
  });
}
