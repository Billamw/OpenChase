class CaesarCipher {
  static const String alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

  // Encrypt a string
  static String encrypt(String input, String key) {
    if (key.length != 4) {
      throw ArgumentError("Key must be exactly 4 letters long");
    }

    List<String> parts = _splitIntoFour(input);
    List<int> shifts = _getShiftsFromKey(key);

    // Encrypt each part with corresponding shift value
    List<String> encryptedParts = [
      _shiftString(parts[0], shifts[0]),
      _shiftString(parts[1], shifts[1]),
      _shiftString(parts[2], shifts[2]),
      _shiftString(parts[3], shifts[3]),
    ];

    return encryptedParts.join('');
  }

  // Decrypt a string
  static String decrypt(String input, String key) {
    if (key.length != 4) {
      throw ArgumentError("Key must be exactly 4 letters long");
    }

    List<String> parts = _splitIntoFour(input);
    List<int> shifts = _getShiftsFromKey(key);

    // Decrypt each part by reversing the shift
    List<String> decryptedParts = [
      _shiftString(parts[0], -shifts[0]),
      _shiftString(parts[1], -shifts[1]),
      _shiftString(parts[2], -shifts[2]),
      _shiftString(parts[3], -shifts[3]),
    ];

    return decryptedParts.join('');
  }

  // Helper: Split string into 4 parts
  static List<String> _splitIntoFour(String input) {
    int partSize = (input.length / 4).ceil();
    List<String> parts = List.generate(4, (i) {
      int start = i * partSize;
      int end = start + partSize;
      return input.substring(start, end > input.length ? input.length : end);
    });

    return parts;
  }

  // Helper: Convert key letters to shift values
  static List<int> _getShiftsFromKey(String key) {
    return key.split('').map((char) => alphabet.indexOf(char)).toList();
  }

  // Helper: Shift characters in a string
  static String _shiftString(String text, int shift) {
    return text
        .split('')
        .map((char) {
          int index = alphabet.indexOf(char);
          if (index == -1) {
            return char; // If character not in allowed set, return as is
          }

          int newIndex = (index + shift) % alphabet.length;
          if (newIndex < 0) {
            newIndex += alphabet.length; // Handle negative shifts
          }

          return alphabet[newIndex];
        })
        .join('');
  }
}
