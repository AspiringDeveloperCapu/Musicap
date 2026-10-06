import 'dart:io';

import 'package:flutter/material.dart';
import 'package:music_player/providers/download_manager.dart';

import 'download_art_common.dart';

/// IO platforms prefer the cover art saved next to the audio file, so the
/// Downloads list keeps its pictures offline. Falls back to the remote
/// image, then a placeholder.
Widget buildDownloadArt(BuildContext context, DownloadState dl) {
  final path = dl.artPath;
  if (path != null && path.isNotEmpty) {
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) =>
          buildNetworkDownloadArt(context, dl),
    );
  }
  return buildNetworkDownloadArt(context, dl);
}
