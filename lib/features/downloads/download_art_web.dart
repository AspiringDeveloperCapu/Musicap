import 'package:flutter/material.dart';
import 'package:music_player/providers/download_manager.dart';

import 'download_art_common.dart';

/// Web: art history keeps the remote URL (browser can't read local paths).
Widget buildDownloadArt(BuildContext context, DownloadState dl) =>
    buildNetworkDownloadArt(context, dl);
