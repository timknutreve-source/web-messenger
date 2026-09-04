import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_messenger/features/profile/presentation/profile_validators.dart';

void main() {
  group('ProfileValidators.aboutMe', () {
    test('accepts null', () => expect(ProfileValidators.aboutMe(null), isNull));

    test('accepts a bio within the limit', () {
      expect(ProfileValidators.aboutMe('a' * 500), isNull);
    });

    test('rejects a bio over the limit', () {
      expect(ProfileValidators.aboutMe('a' * 501), isNotNull);
    });
  });

  group('ProfileValidators.pickedImage', () {
    test('accepts a small jpg', () {
      expect(
        ProfileValidators.pickedImage(fileExtension: 'jpg', sizeBytes: 1024),
        isNull,
      );
    });

    test('accepts a small png regardless of case', () {
      expect(
        ProfileValidators.pickedImage(fileExtension: 'PNG', sizeBytes: 1024),
        isNull,
      );
    });

    test('rejects an unsupported extension', () {
      expect(
        ProfileValidators.pickedImage(fileExtension: 'gif', sizeBytes: 1024),
        isNotNull,
      );
    });

    test('rejects a file larger than 5MB', () {
      expect(
        ProfileValidators.pickedImage(
          fileExtension: 'jpg',
          sizeBytes: 5 * 1024 * 1024 + 1,
        ),
        isNotNull,
      );
    });

    test('accepts a file exactly at the 5MB limit', () {
      expect(
        ProfileValidators.pickedImage(fileExtension: 'jpg', sizeBytes: 5 * 1024 * 1024),
        isNull,
      );
    });
  });
}
