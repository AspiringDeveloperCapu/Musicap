import 'package:flutter/material.dart';
import 'package:music_player/providers/download_manager.dart';

/// Network-based cover art: the remote image, or a music-note placeholder.
Widget buildNetworkDownloadArt(BuildContext context, DownloadState dl) {
  final placeholder = Container(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Icon(
      Icons.music_note,
      size: 22,
      color: Theme.of(context).colorScheme.primary,
    ),
  );
  final url = dl.imageUrl;
  if (url == null || url.isEmpty) return placeholder;
  return Image.network(
    url,
    fit: BoxFit.cover,
    errorBuilder: (context, url, error) => placeholder,
  );
}
