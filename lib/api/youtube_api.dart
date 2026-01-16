import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter_utube/models/my_video.dart';
import 'package:flutter_utube/models/video_data.dart';
import 'package:html/parser.dart' as parser;
import 'package:http/http.dart' as http;
import 'package:xml2json/xml2json.dart';

import '/api/retry.dart';
import '/models/channel_data.dart';
import 'helpers/extract_json.dart';
import 'helpers/helpers_extention.dart';

class YoutubeApi {
  // ==============================
  // State
  // ==============================
  String? _searchToken;
  String? _channelToken;
  String? _playListToken;
  String? _lastQuery;

  static const _webClientContext = {
    'client': {
      'hl': 'en',
      'clientName': 'WEB',
      'clientVersion': '2.20200911.04.00',
    }
  };

  // ==============================
  // SEARCH
  // ==============================
  Future<List> fetchSearchVideo(String query) async {
    if (_searchToken != null && query == _lastQuery) {
      return _fetchSearchContinuation();
    }

    _lastQuery = query;
    final response = await http.get(
      Uri.parse('https://www.youtube.com/results?search_query=$query'),
    );

    final jsonMap = _extractJson(response);
    if (jsonMap == null) return [];

    final items = jsonMap
        .get('contents')
        ?.get('twoColumnSearchResultsRenderer')
        ?.get('primaryContents')
        ?.get('sectionListRenderer')
        ?.getList('contents')
        ?.firstOrNull
        ?.get('itemSectionRenderer')
        ?.getList('contents')
        ?.toList() ??
        [];

    _searchToken = _getContinuationToken(jsonMap);
    return items;
  }

  Future<List> _fetchSearchContinuation() {
    const url =
        'https://www.youtube.com/youtubei/v1/search?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

    return retry(() async {
      final response = await http.post(
        Uri.parse(url),
        body: json.encode({
          'context': _webClientContext,
          'continuation': _searchToken,
        }),
      );

      final jsonMap = json.decode(response.body);
      final items = jsonMap
          .getList('onResponseReceivedCommands')
          ?.firstOrNull
          ?.get('appendContinuationItemsAction')
          ?.getList('continuationItems')
          ?.firstOrNull
          ?.get('itemSectionRenderer')
          ?.getList('contents')
          ?.toList() ??
          [];

      _searchToken = _getContinuationToken(jsonMap);
      return items;
    });
  }

  // ==============================
  // TRENDING (SEARCH BASED)
  // ==============================
  Future<TrendingResult> navBarFetchTrending() async {
    // Always show stable primary chips.
    final filters = primaryTrendingFilters;
    final items = await fetchTrendingByPrimaryFilter(filters.first);
    return TrendingResult(items: items, filters: filters);
  }

  /// Stable, primary trending categories.
  ///
  /// Note: YouTube's `searchSubMenuRenderer` filters are *secondary* (Upload date,
  /// Type, Duration, etc.) and are not reliable for top-level categories.
  static const List<YoutubeFilter> primaryTrendingFilters = [
    YoutubeFilter(title: 'All', params: ''),
    YoutubeFilter(title: 'Music', params: 'music'),
    YoutubeFilter(title: 'Gaming', params: 'gaming'),
    YoutubeFilter(title: 'Movies', params: 'movie trailers'),
    YoutubeFilter(title: 'News', params: 'news'),
  ];

  /// Fetch trending videos using a primary filter.
  ///
  /// For `All`, this uses the query `trending`. For others, it scopes it like
  /// `music trending`.
  Future<List> fetchTrendingByPrimaryFilter(YoutubeFilter filter) {
    final scope = filter.params.trim();
    if (scope.isEmpty) return fetchSearchVideo('trending');
    return fetchSearchVideo('$scope trending');
  }

  /// Backward compatible: if params is empty, load general trending.
  Future<List> fetchTrendingByFilter(YoutubeFilter filter) {
    if (filter.params.isEmpty) {
      return fetchSearchVideo('trending');
    }
    return fetchSearchByFilter('trending', filter.params);
  }

  /// Secondary search filters (Upload date, Type, Duration, ...).
  ///
  /// Returns a safe default if YouTube changes markup.
  Future<List<YoutubeFilter>> fetchTrendingFiltersFromSearch() async {
    final response = await http.get(
      Uri.parse('https://www.youtube.com/results?search_query=trending'),
      headers: const {'User-Agent': 'Mozilla/5.0'},
    );

    final jsonMap = _extractJson(response);
    if (jsonMap == null) {
      return const [YoutubeFilter(title: 'All', params: '')];
    }

    // IMPORTANT: call the instance method declared below, not a global.
    final raw = extractSearchFilters(jsonMap);

    return [
      const YoutubeFilter(title: 'All', params: ''),
      ...raw
          .where((f) => (f['title']?.isNotEmpty ?? false))
          .where((f) => f['params'] != null)
          .map((f) => YoutubeFilter(title: f['title']!, params: f['params']!)),
    ];
  }

  // ==============================
  // SEARCH FILTERS
  // ==============================
  List<Map<String, String>> extractSearchFilters(
      Map<String, dynamic> jsonMap) {
    final filters = <Map<String, String>>[];

    final filterList = jsonMap
        .get('contents')
        ?.get('twoColumnSearchResultsRenderer')
        ?.get('primaryContents')
        ?.get('sectionListRenderer')
        ?.getList('contents')
        ?.firstWhereOrNull((e) => e['searchSubMenuRenderer'] != null)
        ?.get('searchSubMenuRenderer')
        ?.getList('groups')
        ?.firstOrNull
        ?.get('searchFilterGroupRenderer')
        ?.getList('filters');

    if (filterList == null) return filters;

    for (final f in filterList) {
      final r = f['searchFilterRenderer'];
      if (r == null) continue;

      filters.add({
        'title': r['label']['simpleText'],
        'params': r['navigationEndpoint']['searchEndpoint']['params'],
      });
    }
    return filters;
  }

  Future<List> fetchSearchByFilter(String query, String params) async {
    final response = await http.get(
      Uri.parse('https://www.youtube.com/results?search_query=$query&sp=$params'),
      headers: const {'User-Agent': 'Mozilla/5.0'},
    );

    final jsonMap = _extractJson(response);
    if (jsonMap == null) return [];

    return jsonMap
        .get('contents')
        ?.get('twoColumnSearchResultsRenderer')
        ?.get('primaryContents')
        ?.get('sectionListRenderer')
        ?.getList('contents')
        ?.firstOrNull
        ?.get('itemSectionRenderer')
        ?.getList('contents') ??
        [];
  }

  // ==============================
  // CHANNEL
  // ==============================
  Future<ChannelData?> fetchChannelData(String channelId) async {
    final response = await http.get(
      Uri.parse('https://www.youtube.com/channel/$channelId/videos'),
    );

    final jsonMap = _extractJson(response);
    if (jsonMap == null) return null;

    final channel = ChannelData.fromMap(jsonMap);
    channel.checkIsSubscribed(channelId);
    _channelToken = _getContinuationToken(jsonMap);
    return channel;
  }

  Future<List?> loadMoreInChannel() =>
      _loadContinuation(_channelToken, (t) => _channelToken = t);

  Future<List?> loadMoreInPlayList() =>
      _loadContinuation(_playListToken, (t) => _playListToken = t);

  Future<List?> _loadContinuation(
      String? token,
      void Function(String?) onUpdate,
      ) async {
    if (token == null) return null;

    final response = await http.post(
      Uri.parse(
          'https://www.youtube.com/youtubei/v1/browse?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8'),
      body: json.encode({
        'context': _webClientContext,
        'continuation': token,
      }),
    );

    final jsonMap = json.decode(response.body);
    final items = jsonMap
        .getList('onResponseReceivedActions')
        ?.firstOrNull
        ?.get('appendContinuationItemsAction')
        ?.getList('continuationItems');

    onUpdate(_getContinuationToken(jsonMap));
    return items?.toList();
  }

  // ==============================
  // VIDEO DATA
  // ==============================
  Future<VideoData?> fetchVideoData(String videoId) async {
    final response = await http.get(
      Uri.parse('https://www.youtube.com/watch?v=$videoId'),
    );

    final jsonMap = _extractJson(response);
    if (jsonMap == null) return null;

    final contents =
    jsonMap.get('contents')?.get('twoColumnWatchNextResults');
    if (contents == null) return null;

    return VideoData(
      video: MyVideo(
        videoId: videoId,
        title: contents['results']['results']['contents'][0]
        ['videoPrimaryInfoRenderer']['title']['runs'][0]['text'],
        username: contents['results']['results']['contents'][1]
        ['videoSecondaryInfoRenderer']['owner']['videoOwnerRenderer']
        ['title']['runs'][0]['text'],
        viewCount: contents['results']['results']['contents'][0]
        ['videoPrimaryInfoRenderer']['viewCount']
        ['videoViewCountRenderer']['shortViewCount']['simpleText'],
        subscribeCount: contents['results']['results']['contents'][1]
        ['videoSecondaryInfoRenderer']['owner']['videoOwnerRenderer']
        ['subscriberCountText']?['simpleText'],
        likeCount: contents['results']['results']['contents'][0]
        ['videoPrimaryInfoRenderer']['videoActions']['menuRenderer']
        ['topLevelButtons'][0]['toggleButtonRenderer']['defaultText']
        ['simpleText'],
        unlikeCount: '',
        date: contents['results']['results']['contents'][0]
        ['videoPrimaryInfoRenderer']['dateText']['simpleText'],
        channelThumb: contents['results']['results']['contents'][1]
        ['videoSecondaryInfoRenderer']['owner']['videoOwnerRenderer']
        ['thumbnail']['thumbnails'][1]['url'],
        channelId: contents['results']['results']['contents'][1]
        ['videoSecondaryInfoRenderer']['owner']['videoOwnerRenderer']
        ['navigationEndpoint']['browseEndpoint']['browseId'],
      ),
      videosList: contents
          .get('secondaryResults')
          ?.get('secondaryResults')
          ?.getList('results'),
    );
  }

  // ==============================
  // HELPERS
  // ==============================
  Map<String, dynamic>? _extractJson(http.Response response) {
    final document = parser.parse(response.body);
    final script = document
        .querySelectorAll('script')
        .map((e) => e.text)
        .firstWhereOrNull(
            (e) => e.contains('ytInitialData'));

    return script == null ? null : extractJson(script);
  }

  String? _getContinuationToken(Map<String, dynamic>? root) {
    if (root == null) return null;
    return root
        .getList('onResponseReceivedCommands')
        ?.firstOrNull
        ?.get('appendContinuationItemsAction')
        ?.getList('continuationItems')
        ?.firstOrNull
        ?.get('continuationItemRenderer')
        ?.get('continuationEndpoint')
        ?.get('continuationCommand')
        ?.getT<String>('token');
  }

  /// Backward-compatible: HomePage still calls this.
  /// In this app it effectively loads Trending/Explore.
  Future<TrendingResult> fetchExplore() => navBarFetchTrending();

  /// Backward-compatible: HomePage calls this to populate top chips.
  ///
  /// We return stable primary trending filters here.
  Future<List<YoutubeFilter>> fetchExploreFiltersFromWeb() async =>
      primaryTrendingFilters;

  /// Suggestions used by search UI.
  Future<List<String>> fetchSuggestions(String query) async {
    final suggestions = <String>[];
    const baseUrl =
        'http://suggestqueries.google.com/complete/search?output=toolbar&ds=yt&q=';

    final response = await http.get(Uri.parse('$baseUrl$query'));

    final transformer = Xml2Json();
    transformer.parse(response.body);
    final jsonStr = transformer.toGData();

    final data = jsonDecode(jsonStr);
    final list = (data['toplevel']?['CompleteSuggestion'] as List?) ?? const [];

    for (final item in list) {
      final text = item?['suggestion']?['data']?.toString();
      if (text != null && text.isNotEmpty) suggestions.add(text);
    }

    return suggestions;
  }

  /// Playlist loading used by PlaylistPage.
  ///
  /// `loaded` is currently ignored but kept for API compatibility.
  Future<List> fetchPlayListVideos(String id, int loaded) async {
    final url = 'https://www.youtube.com/playlist?list=$id&hl=en&persist_hl=1';

    final response = await http.get(Uri.parse(url));
    final jsonMap = _extractJson(response);
    if (jsonMap == null) return [];

    final contents = jsonMap
        .get('contents')
        ?.get('twoColumnBrowseResultsRenderer')
        ?.getList('tabs')
        ?.firstOrNull
        ?.get('tabRenderer')
        ?.get('content')
        ?.get('sectionListRenderer')
        ?.getList('contents')
        ?.firstOrNull
        ?.get('itemSectionRenderer')
        ?.getList('contents')
        ?.firstOrNull
        ?.get('playlistVideoListRenderer')
        ?.getList('contents')
        ?.toList();

    // Best-effort: update playlist continuation token if present.
    _playListToken = _getContinuationToken(jsonMap);

    return contents ?? [];
  }
}

// ==============================
// MODELS
// ==============================
class YoutubeFilter {
  final String title;
  final String params;
  const YoutubeFilter({required this.title, required this.params});
}

class TrendingResult {
  final List items;
  final List<YoutubeFilter> filters;
  const TrendingResult({required this.items, required this.filters});
}
