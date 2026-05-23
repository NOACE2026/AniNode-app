import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/anime_provider.dart';
import '../theme/cp.dart';
import 'details_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: ref.read(searchQueryProvider));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _ctrl.text.trim();
    final resultsAsync = ref.watch(searchMetadataProvider(query));

    return Scaffold(
      backgroundColor: CP.bg,
      appBar: AppBar(
        backgroundColor: CP.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: CP.cyan, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          style: CP.mono(size: 14, color: CP.text),
          decoration: InputDecoration(
            hintText: 'SEARCH ANIME...',
            hintStyle: CP.mono(size: 13, color: CP.textMuted),
            border: InputBorder.none,
            prefixIcon: Icon(Icons.search_rounded, color: CP.cyan.withValues(alpha: 0.6), size: 20),
          ),
          onChanged: (v) {
            // Search query updated
            setState(() {});
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                CP.cyan.withValues(alpha: 0),
                CP.cyan.withValues(alpha: 0.4),
                CP.cyan.withValues(alpha: 0),
              ]),
            ),
          ),
        ),
      ),
      body: resultsAsync.when(
        data: (results) {
          if (query.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_rounded, color: CP.textMuted, size: 48),
                  const SizedBox(height: 12),
                  Text('TYPE TO SEARCH', style: CP.mono(size: 12, color: CP.textMuted)),
                ],
              ),
            );
          }
          if (results.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off_rounded, color: CP.textMuted, size: 48),
                  const SizedBox(height: 12),
                  Text('NO RESULTS FOUND', style: CP.mono(size: 12, color: CP.textMuted)),
                  const SizedBox(height: 4),
                  Text('"$query"', style: CP.rajdhani(size: 14, color: CP.textDim)),
                ],
              ),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final cols = w >= 1200 ? 6 : w >= 900 ? 5 : w >= 700 ? 4 : 3;

              return GridView.builder(
                padding: const EdgeInsets.all(14),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  childAspectRatio: 0.68,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: results.length,
                itemBuilder: (_, i) {
                  final anime = results[i];
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => DetailsScreen(media: anime)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: CP.cardDecor,
                            clipBehavior: Clip.hardEdge,
                            child: Stack(
                              children: [
                                CachedNetworkImage(
                                  imageUrl: anime.imageUrl,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  placeholder: (_, _) => Container(color: CP.surface),
                                  errorWidget: (_, _, _) => Container(color: CP.surface),
                                ),
                                // Rating badge
                                if (anime.rating != null)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: CP.bg.withValues(alpha: 0.8),
                                        border: Border.all(
                                            color: CP.cyan.withValues(alpha: 0.4)),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Text(
                                        anime.rating!,
                                        style: CP.mono(size: 9, color: CP.cyan),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          anime.title.toString(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: CP.rajdhani(size: 12, weight: FontWeight.w600),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: CP.cyan)),
        error: (e, _) => Center(child: Text('Error: $e', style: CP.mono(color: CP.magenta))),
      ),
    );
  }
}
