import 'dart:convert';
import 'package:flutter_utube/models/my_video.dart';
import 'package:flutter_utube/models/video_data.dart';
import 'package:xml2json/xml2json.dart';
import '/api/retry.dart';
import '/helpers/suggestion_history.dart';
import '/models/channel_data.dart';
import 'helpers/extract_json.dart';
import 'helpers/helpers_extention.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:collection/collection.dart';

class YoutubeApi {
  String? _searchToken;
  String? _channelToken;
  String? _playListToken;
  String? lastQuery;

  Future fetchSearchVideo(String query) async {
    List list = [];
    var client = http.Client();
    if (_searchToken != null && query == lastQuery) {
      var url =
          'https://www.youtube.com/youtubei/v1/search?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

      return retry(() async {
        var body = {
          'context': const {
            'client': {
              'hl': 'en',
              'clientName': 'WEB',
              'clientVersion': '2.20200911.04.00'
            }
          },
          'continuation': _searchToken
        };
        var raw = await client.post(Uri.parse(url), body: json.encode(body));
        Map<String, dynamic> jsonMap = json.decode(raw.body);
        var contents = jsonMap
            .getList('onResponseReceivedCommands')
            ?.firstOrNull
            ?.get('appendContinuationItemsAction')
            ?.getList('continuationItems')
            ?.firstOrNull
            ?.get('itemSectionRenderer')
            ?.getList('contents');
        list = contents!.toList();
        _searchToken = _getContinuationToken(jsonMap);
        return list;
      });
    } else {
      lastQuery = query;
      var response = await client.get(
        Uri.parse(
          'https://www.youtube.com/results?search_query=$query',
        ),
      );
      var jsonMap = _getJsonMap(response);
      if (jsonMap != null) {
        var contents = jsonMap
            .get('contents')
            ?.get('twoColumnSearchResultsRenderer')
            ?.get('primaryContents')
            ?.get('sectionListRenderer')
            ?.getList('contents')
            ?.firstOrNull
            ?.get('itemSectionRenderer')
            ?.getList('contents');

        list = contents!.toList();
        _searchToken = _getContinuationToken(jsonMap);
      }
    }
    return list;
  }

  Future<List<YoutubeFilter>> fetchExploreFiltersFromWeb() async {
    final client = http.Client();
    final response = await client.get(
      Uri.parse('https://www.youtube.com/feed/explore'),
      headers: const {'User-Agent': 'Mozilla/5.0'},
    );

    final jsonMap = _getJsonMap(response);
    if (jsonMap == null) {
      return const [YoutubeFilter(title: 'All', params: '')];
    }

    final List<YoutubeFilter> filters = [];

    try {
      final chips = jsonMap
          .get('contents')
          ?.get('twoColumnBrowseResultsRenderer')
          ?.getList('tabs')
          ?.firstOrNull
          ?.get('tabRenderer')
          ?.get('content')
          ?.get('sectionListRenderer')
          ?.getList('contents')
          ?.firstWhereOrNull((e) => e['feedFilterChipBarRenderer'] != null)
          ?.get('feedFilterChipBarRenderer')
          ?.getList('contents');

      if (chips != null) {
        for (final chip in chips) {
          final renderer = chip['feedFilterChipRenderer'];
          if (renderer == null) continue;

          final title = renderer['text']?['runs']?[0]?['text'];
          final params = renderer['navigationEndpoint']
                  ?['browseEndpoint']
                  ?['params'] ??
              '';

          if (title != null) {
            filters.add(YoutubeFilter(title: title, params: params));
          }
        }
      }
    } catch (_) {}

    if (filters.isEmpty) {
      filters.add(const YoutubeFilter(title: 'All', params: ''));
    }

    return filters;
  }

  Future<TrendingResult> fetchExplore() async {
    final filters = await fetchExploreFiltersFromWeb();
    final query = filters.isNotEmpty
        ? '${filters.first.title.toLowerCase()} trending'
        : 'trending';
    final items = await fetchSearchVideo(query);

    return TrendingResult(
      items: items,
      filters: filters,
    );
  }

  Future<TrendingResult> fetchTrendingWithFilters({String? bpParam}) async {
    print('🌐 API: fetchTrendingWithFilters (bpParam=$bpParam) using explore/search flow');
    SuggestionHistory.init();

    if (bpParam != null && bpParam.isNotEmpty) {
      final items = await fetchSearchByFilter('trending', bpParam);
      final filters = await fetchExploreFiltersFromWeb();
      return TrendingResult(items: items, filters: filters);
    }

    return fetchExplore();
  }

  Future<List<String>> fetchSuggestions(String query) async {
    List<String> suggestions = [];
    String baseUrl =
        'http://suggestqueries.google.com/complete/search?output=toolbar&ds=yt&q=';
    var client = http.Client();
    final myTranformer = Xml2Json();
    var response = await client.get(Uri.parse(baseUrl + query));
    var body = response.body;
    myTranformer.parse(body);
    var json = myTranformer.toGData();
    List suggestionsData = jsonDecode(json)['toplevel']['CompleteSuggestion'];
    suggestionsData.forEach((suggestion) {
      suggestions.add(suggestion['suggestion']['data'].toString());
    });
    return suggestions;
  }

  String? _getContinuationToken(Map<String, dynamic>? root) {
    if (root?['contents'] != null) {
      if (root?['contents']?['twoColumnBrowseResultsRenderer'] != null) {
        return root!
            .get('contents')
            ?.get('twoColumnBrowseResultsRenderer')
            ?.getList('tabs')
            ?.elementAtSafe(1)
            ?.get('tabRenderer')
            ?.get('content')
            ?.get('sectionListRenderer')
            ?.getList('contents')
            ?.firstOrNull
            ?.get('itemSectionRenderer')
            ?.getList('contents')
            ?.firstOrNull
            ?.get('gridRenderer')
            ?.getList('items')
            ?.elementAtSafe(30)
            ?.get('continuationItemRenderer')
            ?.get('continuationEndpoint')
            ?.get('continuationCommand')
            ?.getT<String>('token');
      }
      var contents = root!
          .get('contents')
          ?.get('twoColumnSearchResultsRenderer')
          ?.get('primaryContents')
          ?.get('sectionListRenderer')
          ?.getList('contents');

      if (contents == null || contents.length <= 1) {
        return null;
      }
      return contents
          .elementAtSafe(1)
          ?.get('continuationItemRenderer')
          ?.get('continuationEndpoint')
          ?.get('continuationCommand')
          ?.getT<String>('token');
    }
    if (root?['onResponseReceivedCommands'] != null) {
      return root!
          .getList('onResponseReceivedCommands')
          ?.firstOrNull
          ?.get('appendContinuationItemsAction')
          ?.getList('continuationItems')
          ?.elementAtSafe(1)
          ?.get('continuationItemRenderer')
          ?.get('continuationEndpoint')
          ?.get('continuationCommand')
          ?.getT<String>('token');
    }
    return null;
  }

  Future fetchChannelData(String channelId) async {
    var client = http.Client();
    var response = await client.get(
      Uri.parse(
        'https://www.youtube.com/channel/$channelId/videos',
      ),
    );
    var raw = response.body;
    var root = parser.parse(raw);
    final scriptText = root
        .querySelectorAll('script')
        .map((e) => e.text)
        .toList(growable: false);
    var initialData =
        scriptText.firstWhereOrNull((e) => e.contains('var ytInitialData = '));
    initialData ??= scriptText
        .firstWhereOrNull((e) => e.contains('window["ytInitialData"] ='));
    var jsonMap = extractJson(initialData!);
    if (jsonMap != null) {
      ChannelData channelData = ChannelData.fromMap(jsonMap);
      channelData.checkIsSubscribed(channelId);
      _channelToken = _getContinuationToken(jsonMap);
      return channelData;
    }
    return null;
  }

  Future<List?> loadMoreInChannel() async {
    List? list;
    var client = http.Client();
    var url =
        'https://www.youtube.com/youtubei/v1/browse?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
    var body = {
      'context': const {
        'client': {
          'hl': 'en',
          'clientName': 'WEB',
          'clientVersion': '2.20200911.04.00'
        }
      },
      'continuation': _channelToken
    };
    var raw = await client.post(Uri.parse(url), body: json.encode(body));
    Map<String, dynamic> jsonMap = json.decode(raw.body);
    var contents = jsonMap
        .getList('onResponseReceivedActions')
        ?.firstOrNull
        ?.get('appendContinuationItemsAction')
        ?.getList('continuationItems');
    if (contents != null) {
      list = contents.toList();
      _channelToken = _getChannelContinuationToken(jsonMap);
    }
    return list;
  }

  Future<List?> loadMoreInPlayList() async {
    List? list;
    var client = http.Client();
    var url =
        'https://www.youtube.com/youtubei/v1/browse?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
    var body = {
      'context': const {
        'client': {
          'hl': 'en',
          'clientName': 'WEB',
          'clientVersion': '2.20200911.04.00'
        }
      },
      'continuation': _playListToken
    };
    var raw = await client.post(Uri.parse(url), body: json.encode(body));
    Map<String, dynamic> jsonMap = json.decode(raw.body);
    var contents = jsonMap
        .getList('onResponseReceivedActions')
        ?.firstOrNull
        ?.get('appendContinuationItemsAction')
        ?.getList('continuationItems');
    if (contents != null) {
      list = contents.toList();
      _playListToken = _getChannelContinuationToken(jsonMap);
    }
    return list;
  }

  String? _getChannelContinuationToken(Map<String, dynamic>? root) {
    return root!
        .getList('onResponseReceivedActions')
        ?.firstOrNull
        ?.get('appendContinuationItemsAction')
        ?.getList('continuationItems')
        ?.elementAtSafe(30)
        ?.get('continuationItemRenderer')
        ?.get('continuationEndpoint')
        ?.get('continuationCommand')
        ?.getT<String>('token');
  }

  String? _getPlayListContinuationToken(Map<String, dynamic>? root) {
    return root!
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
        ?.elementAtSafe(100)
        ?.get('continuationItemRenderer')
        ?.get('continuationEndpoint')
        ?.get('continuationCommand')
        ?.getT<String>('token');
  }

  Future<List> fetchPlayListVideos(String id, int loaded) async {
    List videos = [];
    var url = 'https://www.youtube.com/playlist?list=$id&hl=en&persist_hl=1';
    var client = http.Client();
    var response = await client.get(
      Uri.parse(url),
    );
    var jsonMap = _getJsonMap(response);
    if (jsonMap != null) {
      var contents = jsonMap
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
          ?.getList('contents');
      videos = contents!.toList();
      _playListToken = _getPlayListContinuationToken(jsonMap);
    }
    return videos;
  }

  Future<VideoData?> fetchVideoData(String videoId) async {
    VideoData? videoData;
    var client = http.Client();
    var response =
        await client.get(Uri.parse('https://www.youtube.com/watch?v=$videoId'));
    var raw = response.body;
    var root = parser.parse(raw);
    final scriptText = root
        .querySelectorAll('script')
        .map((e) => e.text)
        .toList(growable: false);
    var initialData =
        scriptText.firstWhereOrNull((e) => e.contains('var ytInitialData = '));
    initialData ??= scriptText
        .firstWhereOrNull((e) => e.contains('window["ytInitialData"] ='));
    var jsonMap = extractJson(initialData!);
    if (jsonMap != null) {
      var contents = jsonMap.get('contents')?.get('twoColumnWatchNextResults');

      var videosList = contents
          ?.get('secondaryResults')
          ?.get('secondaryResults')
          ?.getList('results')
          ?.toList();

      videoData = VideoData(
          video: MyVideo(
              videoId: videoId,
              title: contents!['results']['results']['contents'][0]
                  ['videoPrimaryInfoRenderer']['title']['runs'][0]['text'],
              username: contents['results']['results']['contents'][1]['videoSecondaryInfoRenderer']
                  ['owner']['videoOwnerRenderer']['title']['runs'][0]['text'],
              viewCount: contents['results']['results']['contents'][0]['videoPrimaryInfoRenderer']['viewCount']
                  ['videoViewCountRenderer']['shortViewCount']['simpleText'],
              subscribeCount: contents['results']?['results']?['contents']?[1]?['videoSecondaryInfoRenderer']?['owner']
                  ?['videoOwnerRenderer']?['subscriberCountText']?['simpleText'],
              likeCount: contents['results']['results']['contents'][0]['videoPrimaryInfoRenderer']['videoActions']['menuRenderer']['topLevelButtons'][0]['toggleButtonRenderer']['defaultText']['simpleText'],
              unlikeCount: '',
              date: contents['results']['results']['contents'][0]['videoPrimaryInfoRenderer']['dateText']['simpleText'],
              channelThumb: contents['results']['results']['contents'][1]['videoSecondaryInfoRenderer']['owner']['videoOwnerRenderer']['thumbnail']['thumbnails'][1]['url'],
              channelId: contents['results']['results']['contents'][1]['videoSecondaryInfoRenderer']['owner']['videoOwnerRenderer']['navigationEndpoint']['browseEndpoint']['browseId']),
          videosList: videosList);
    }
    return videoData;
  }

  Map<String, dynamic>? _getJsonMap(http.Response response) {
    var raw = response.body;
    var root = parser.parse(raw);
    final scriptText = root
        .querySelectorAll('script')
        .map((e) => e.text)
        .toList(growable: false);
    var initialData =
        scriptText.firstWhereOrNull((e) => e.contains('var ytInitialData = '));
    initialData ??= scriptText
        .firstWhereOrNull((e) => e.contains('window["ytInitialData"] ='));
    if (initialData == null) return null;
    var jsonMap = extractJson(initialData);
    return jsonMap;
  }

  List<YoutubeFilter> _ensureDefaultFilter(List<YoutubeFilter> filters) {
    if (filters.isEmpty || filters.every((f) => f.params.isNotEmpty)) {
      filters.insert(0, const YoutubeFilter(title: 'All', params: ''));
    }
    return filters;
  }

  List _parseTrendingItems(Map<String, dynamic> jsonMap) {
    final List items = [];

    void collect(dynamic node) {
      if (node == null) return;
      if (node is Map) {
        if (node.containsKey('richItemRenderer')) {
          items.add(node);
          return;
        }
        if (node.containsKey('videoRenderer')) {
          items.add({'richItemRenderer': {'content': {'videoRenderer': node['videoRenderer']}}});
          return;
        }
        for (final value in node.values) {
          collect(value);
        }
      } else if (node is List) {
        for (final v in node) {
          collect(v);
        }
      }
    }

    final tabs = jsonMap
        .get('contents')
        ?.get('twoColumnBrowseResultsRenderer')
        ?.getList('tabs');
    if (tabs != null) {
      for (final tab in tabs) {
        collect(tab);
      }
    }

    print('🌐 API: Collected ${items.length} rich items recursively');
    return items;
  }

  List<Map<String, String>> extractSearchFilters(Map<String, dynamic> jsonMap) {
    final List<Map<String, String>> filters = [];

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
      final renderer = f['searchFilterRenderer'];
      if (renderer == null) continue;

      filters.add({
        'title': renderer['label']['simpleText'],
        'params': renderer['navigationEndpoint']['searchEndpoint']['params'],
      });
    }

    return filters;
  }

  Future<List> fetchSearchByFilter(String query, String params) async {
    final client = http.Client();
    final response = await client.get(
      Uri.parse(
        'https://www.youtube.com/results?search_query=$query&sp=$params',
      ),
      headers: const {'User-Agent': 'Mozilla/5.0'},
    );

    final jsonMap = _getJsonMap(response);
    if (jsonMap == null) return [];

    final contents = jsonMap
        .get('contents')
        ?.get('twoColumnSearchResultsRenderer')
        ?.get('primaryContents')
        ?.get('sectionListRenderer')
        ?.getList('contents')
        ?.firstOrNull
        ?.get('itemSectionRenderer')
        ?.getList('contents');

    return contents ?? [];
  }
}

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
