import 'dart:io';

void main() {
  print('PATH: ${Platform.environment['PATH']}');
  var result = Process.runSync('which', ['npx']);
  if (result.exitCode != 0) {
    print('which npx failed: ${result.stderr}');
  } else {
    print('which npx found: ${result.stdout}');
  }
}
