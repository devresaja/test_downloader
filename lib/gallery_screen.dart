import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'dart:typed_data';

// Simple gallery screen using `photo_manager` to display images from the device
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<AssetEntity> _assets = [];
  bool _loading = true;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _fetchAssets();
  }

  Future<void> _fetchAssets() async {
    setState(() {
      _loading = true;
    });

    // Request permissions using photo_manager's specific method
    final PermissionState ps = await PhotoManager.requestPermissionExtend();

    if (!ps.isAuth && !ps.hasAccess) {
      setState(() {
        _hasPermission = false;
        _loading = false;
      });
      return;
    }

    setState(() {
      _hasPermission = true;
    });

    // Get assets
    final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
    );

    if (albums.isEmpty) {
      setState(() {
        _assets = [];
        _loading = false;
      });
      return;
    }

    final AssetPathEntity recentAlbum = albums.first;
    final List<AssetEntity> assets = await recentAlbum.getAssetListPaged(
      page: 0,
      size: 100,
    );

    setState(() {
      _assets = assets;
      _loading = false;
    });
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: _assets.length,
      itemBuilder: (context, index) {
        final asset = _assets[index];

        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => FullImageScreen(asset: asset)),
            );
          },
          child: FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes == null) {
                return Container(color: Colors.grey[300]);
              }
              return Image.memory(bytes, fit: BoxFit.cover);
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchAssets),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!_hasPermission) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Permission to access photos was denied.'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () async {
                      PhotoManager.openSetting();
                    },
                    child: const Text('Open Settings'),
                  ),
                ],
              ),
            );
          }

          if (_assets.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text('No images found'),
                ],
              ),
            );
          }

          return _buildGrid();
        },
      ),
    );
  }
}

class FullImageScreen extends StatelessWidget {
  final AssetEntity asset;

  const FullImageScreen({super.key, required this.asset});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: FutureBuilder<Uint8List?>(
          future: asset.originBytes,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null) {
              return const CircularProgressIndicator(color: Colors.white);
            }
            return InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.memory(bytes, fit: BoxFit.contain),
            );
          },
        ),
      ),
    );
  }
}
