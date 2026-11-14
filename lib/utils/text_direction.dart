import 'dart:ui' show TextDirection;

import 'package:intl/intl.dart' show Bidi;

/// Whether [text] is mostly written in a right-to-left script (Arabic,
/// Hebrew, ...).
bool isRightToLeft(String text) => Bidi.detectRtlDirectionality(text);

/// The direction to lay [text] out in: right-to-left for right-to-left
/// scripts, otherwise `null`, which means the direction of the app.
TextDirection? directionOf(String text) =>
    isRightToLeft(text) ? TextDirection.rtl : null;
