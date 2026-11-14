/// Bucket-center sampling avoids the usual black opening/end frames.
/// Decoder previews may use a nearby keyframe; timestamps remain seek targets.
List<int> contactSheetTimes(int durationUs, {int count = 12}) {
  if (durationUs <= 0 || durationUs > (1 << 52) || count < 1 || count > 24) {
    throw const FormatException(
      'Invalid contact-sheet duration or frame count',
    );
  }
  final size = count < durationUs ? count : durationUs;
  return List.generate(size, (i) => ((2 * i + 1) * durationUs) ~/ (2 * size));
}

String contactSheetTimeLabel(int timeUs) {
  final seconds = timeUs ~/ 1000000;
  final hours = seconds ~/ 3600;
  final minutes = (seconds ~/ 60) % 60;
  final tail = (seconds % 60).toString().padLeft(2, '0');
  final whole = hours == 0
      ? '$minutes:$tail'
      : '$hours:${minutes.toString().padLeft(2, '0')}:$tail';
  final millis = (timeUs ~/ 1000) % 1000;
  return millis == 0 ? whole : '$whole.${millis.toString().padLeft(3, '0')}';
}
