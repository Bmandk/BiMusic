import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux);
