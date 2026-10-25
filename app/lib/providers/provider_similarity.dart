import '../domain/models.dart';
import '../player/similarity.dart';
import 'music_provider.dart';

/// Adaptor Tangga Kemiripan di atas kontrak provider.
class ProviderSimilaritySource implements SimilaritySource {
  final MusicProvider provider;
  ProviderSimilaritySource(this.provider);
  @override
  Future<List<Track>> sameArtist(Track seed) => provider.getSameArtist(seed);
  @override
  Future<List<Track>> related(Track seed) => provider.getRelated(seed);
  @override
  Future<List<Artist>> similarArtists(Track seed) => provider.getSimilarArtists(seed);
  @override
  Future<List<Track>> artistTopTracks(String artistId) async => (await provider.getArtist(artistId)).tracks;
  @override
  Future<List<Track>> sameGenre(Track seed) => provider.getSameGenre(seed);
}
