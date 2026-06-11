import 'package:flutter_test/flutter_test.dart';
import 'package:meshagent_flutter_auth/shared_profiles_io.dart';

void main() {
  test('shared profiles are supported only on macOS and Windows', () {
    expect(sharedProfilesSupportedForPlatform(isMacOS: true, isWindows: false), isTrue);
    expect(sharedProfilesSupportedForPlatform(isMacOS: false, isWindows: true), isTrue);
    expect(sharedProfilesSupportedForPlatform(isMacOS: false, isWindows: false), isFalse);
  });
}
