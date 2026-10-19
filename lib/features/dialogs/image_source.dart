// Resolving a dialog's image source into a Flutter [ImageProvider].
//
// The C layer's `image_load` (`lib/image.c`, used at `lib/script_dialog.c:199`
// and `:316`) accepts a filesystem path, an http(s) URL, or a `data:` URI, and
// decodes PNG/JPEG/BMP/GIF with stb_image. Flutter gets all of that for free —
// including animated GIF, which stb_image does not do — which is why the plan
// puts DIALOG image decoding in Dart ("弹窗的图片解码 | Dart",
// docs/FLUTTER_REWRITE_PLAN.md).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// What a dialog's image source turned out to be.
sealed class DialogImage {
  const DialogImage();
}

/// An http(s) source.
class DialogNetworkImage extends DialogImage {
  const DialogNetworkImage(this.url);

  final String url;

  @override
  bool operator ==(Object other) =>
      other is DialogNetworkImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// A `data:` URI, already decoded.
///
/// Decoded eagerly at parse time rather than lazily, because a malformed base64
/// payload should surface as "this item has no image" instead of an exception
/// inside the image pipeline.
class DialogMemoryImage extends DialogImage {
  const DialogMemoryImage(this.bytes);

  final Uint8List bytes;
}

/// A filesystem path.
class DialogFileImage extends DialogImage {
  const DialogFileImage(this.path);

  final String path;
}

/// A source that could not be understood. The renderer shows nothing for it
/// rather than a broken-image glyph: the C layer's `image_load` returning NULL
/// means the item simply draws without its icon (`lib/script_dialog.c:200`).
class DialogInvalidImage extends DialogImage {
  const DialogInvalidImage(this.reason);

  final String reason;
}

/// Classify an image source string.
///
/// Mirrors the source kinds `image_load` accepts. A relative path is resolved
/// against [baseDirectory] when one is supplied — the engine's path resolution
/// is the host's job (`taskpin_engine.h`: "The path is used as given ...
/// Path resolution is the host's job"), so a script that writes
/// `image = "pic.png"` means "next to whatever the host considers the working
/// directory".
DialogImage classifyImageSource(String source, {String? baseDirectory}) {
  if (source.isEmpty) {
    return const DialogInvalidImage('empty source');
  }

  if (source.startsWith('data:')) {
    final int comma = source.indexOf(',');
    if (comma < 0) {
      return const DialogInvalidImage('data URI without a comma');
    }
    final String meta = source.substring(5, comma);
    final String payload = source.substring(comma + 1);
    try {
      // `;base64` is the only encoding the C loader handles too.
      if (meta.contains('base64')) {
        return DialogMemoryImage(base64Decode(payload));
      }
      return DialogMemoryImage(
        Uint8List.fromList(Uri.decodeComponent(payload).codeUnits),
      );
    } on FormatException catch (e) {
      return DialogInvalidImage('bad data URI: ${e.message}');
    }
  }

  final Uri? uri = Uri.tryParse(source);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return DialogNetworkImage(source);
  }

  // Anything else is a path. `file://` is unwrapped; a bare path is resolved
  // against the base directory when the caller has one.
  if (uri != null && uri.scheme == 'file') {
    return DialogFileImage(uri.toFilePath());
  }
  if (baseDirectory != null && !File(source).isAbsolute) {
    return DialogFileImage('$baseDirectory${Platform.pathSeparator}$source');
  }
  return DialogFileImage(source);
}

/// Build the widget-tree provider for a classified source.
///
/// Returns null when there is nothing renderable, which the item widgets treat
/// as "draw without the image" (C parity, see [DialogInvalidImage]).
ImageProvider? imageProviderFor(DialogImage image) {
  switch (image) {
    case DialogNetworkImage(:final String url):
      return NetworkImage(url);
    case DialogMemoryImage(:final Uint8List bytes):
      return MemoryImage(bytes);
    case DialogFileImage(:final String path):
      final File f = File(path);
      // A missing file is the common case for a stale path in a long-lived
      // dialog; returning null keeps the item rendering as text-only, the same
      // as `image_load` failing.
      return f.existsSync() ? FileImage(f) : null;
    case DialogInvalidImage():
      return null;
  }
}
