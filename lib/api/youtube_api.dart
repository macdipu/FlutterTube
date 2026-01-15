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

  Future fetchTrendingVideo() async {
    print('🌐 API: fetchTrendingVideo started');
    SuggestionHistory.init();
    List list = [];
    var client = http.Client();
    try {
      print('🌐 API: Making HTTP request to YouTube trending...');
      var response = await client.get(
        Uri.parse(
          'https://www.youtube.com/feed/trending',
        ),
      );
      print('🌐 API: Response status code: ${response.statusCode}');
      print('🌐 API: Response body length: ${response.body.length}');

      var raw = response.body;
      var root = parser.parse(raw);
      final scriptText = root
          .querySelectorAll('script')
          .map((e) => e.text)
          .toList(growable: false);
      print('🌐 API: Found ${scriptText.length} script tags');

      var initialData = scriptText
          .firstWhereOrNull((e) => e.contains('var ytInitialData = '));
      initialData ??= scriptText
          .firstWhereOrNull((e) => e.contains('window["ytInitialData"] ='));

      if (initialData == null) {
        print('❌ API: Could not find ytInitialData in page');
        return list;
      }
      print('🌐 API: Found ytInitialData');

      var jsonMap = extractJson(initialData);
      if (jsonMap == null) {
        print('❌ API: Failed to extract JSON from initialData');
        return list;
      }
      print('🌐 API: Successfully extracted JSON map');

      // Try to find videos in the tab structure
      var tabs = jsonMap
          .get('contents')
          ?.get('twoColumnBrowseResultsRenderer')
          ?.getList('tabs');

      if (tabs != null) {
        print('🌐 API: Found ${tabs.length} tabs');

        // Search through all tabs for video content
        for (var i = 0; i < tabs.length; i++) {
          var tab = tabs.elementAtSafe(i);
          var tabContent = tab?.get('tabRenderer')?.get('content');

          if (tabContent == null) continue;

          print('🔍 API: Tab $i content keys: ${tabContent.keys.toList()}');

          // NEW FORMAT: richGridRenderer directly in content
          var richGridRenderer = tabContent.get('richGridRenderer');
          if (richGridRenderer != null) {
            print(
                '🔍 API: richGridRenderer keys: ${richGridRenderer.keys.toList()}');

            var directRichGrid = richGridRenderer.getList('contents');
            if (directRichGrid != null) {
              print(
                  '🔍 API: richGridRenderer has ${directRichGrid.length} total items');

              // Filter out continuationItemRenderer and only keep richItemRenderer
              var videoItems = directRichGrid.where((item) {
                if (item == null) return false;
                // Keep items that have richItemRenderer (actual videos)
                if (item.containsKey('richItemRenderer')) return true;
                // Skip continuationItemRenderer and other non-video items
                print('🔍 API: Skipping item with keys: ${item.keys.toList()}');
                return false;
              }).toList();

              if (videoItems.isNotEmpty) {
                print(
                    '🌐 API: Found ${videoItems.length} video items in direct richGridRenderer (tab $i)');
                list.addAll(videoItems);
                continue; // Found content, move to next tab
              } else {
                print(
                    '⚠️ API: richGridRenderer had ${directRichGrid.length} items but 0 videos');
              }
            } else {
              print('⚠️ API: richGridRenderer.contents is null');
            }
          }

          // OLD FORMAT: sectionListRenderer with nested content
          var tabContents =
              tabContent.get('sectionListRenderer')?.getList('contents');

          if (tabContents != null) {
            print('🌐 API: Tab $i has ${tabContents.length} sections');

            // Search through all sections in this tab
            for (var j = 0; j < tabContents.length; j++) {
              var section = tabContents.elementAtSafe(j);

              // Try to get items from richGridRenderer in itemSectionRenderer
              var richItems = section
                  ?.get('itemSectionRenderer')
                  ?.getList('contents')
                  ?.firstOrNull
                  ?.get('richGridRenderer')
                  ?.getList('contents');

              if (richItems != null && richItems.isNotEmpty) {
                print(
                    '🌐 API: Found ${richItems.length} rich items in tab $i, section $j');
                list.addAll(richItems);
              }

              // Try to get items from shelfRenderer (older format)
              var shelfItems = section
                  ?.get('itemSectionRenderer')
                  ?.getList('contents')
                  ?.firstOrNull
                  ?.get('shelfRenderer')
                  ?.get('content')
                  ?.get('expandedShelfContentsRenderer')
                  ?.getList('items');

              if (shelfItems != null && shelfItems.isNotEmpty) {
                print(
                    '🌐 API: Found ${shelfItems.length} shelf items in tab $i, section $j');
                list.addAll(shelfItems);
              }
            }
          }
        }
      }

      print('✅ API: Total items: ${list.length}');
    } catch (e, stackTrace) {
      print('❌ API ERROR: $e');
      print('❌ API STACK: $stackTrace');
    }
    print(
        '🌐 API: fetchTrendingVideo completed, returning ${list.length} items');
    return list;
  }

  Future fetchTrendingMusic() async {
    String params = "4gINGgt5dG1hX2NoYXJ0cw%3D%3D";
    List list = [];
    var client = http.Client();
    try {
      var response = await client.get(
        Uri.parse(
          'https://www.youtube.com/feed/trending?bp=$params',
        ),
      );
      var raw = response.body;
      var root = parser.parse(raw);
      final scriptText = root
          .querySelectorAll('script')
          .map((e) => e.text)
          .toList(growable: false);
      var initialData = scriptText
          .firstWhereOrNull((e) => e.contains('var ytInitialData = '));
      initialData ??= scriptText
          .firstWhereOrNull((e) => e.contains('window["ytInitialData"] ='));

      if (initialData == null) {
        print('❌ API: Could not find ytInitialData in music page');
        return list;
      }

      var jsonMap = extractJson(initialData);
      if (jsonMap != null) {
        var tabs = jsonMap
            .get('contents')
            ?.get('twoColumnBrowseResultsRenderer')
            ?.getList('tabs');

        if (tabs != null) {
          for (var i = 0; i < tabs.length; i++) {
            var tab = tabs.elementAtSafe(i);
            var tabContent = tab?.get('tabRenderer')?.get('content');

            if (tabContent == null) continue;

            // NEW FORMAT: richGridRenderer directly in content
            var directRichGrid =
                tabContent.get('richGridRenderer')?.getList('contents');
            if (directRichGrid != null && directRichGrid.isNotEmpty) {
              list.addAll(directRichGrid);
              continue;
            }

            // OLD FORMAT: sectionListRenderer with nested content
            var tabContents =
                tabContent.get('sectionListRenderer')?.getList('contents');
            if (tabContents != null) {
              for (var j = 0; j < tabContents.length; j++) {
                var section = tabContents.elementAtSafe(j);

                var richItems = section
                    ?.get('itemSectionRenderer')
                    ?.getList('contents')
                    ?.firstOrNull
                    ?.get('richGridRenderer')
                    ?.getList('contents');

                if (richItems != null && richItems.isNotEmpty) {
                  list.addAll(richItems);
                }

                var shelfItems = section
                    ?.get('itemSectionRenderer')
                    ?.getList('contents')
                    ?.firstOrNull
                    ?.get('shelfRenderer')
                    ?.get('content')
                    ?.get('expandedShelfContentsRenderer')
                    ?.getList('items');

                if (shelfItems != null && shelfItems.isNotEmpty) {
                  list.addAll(shelfItems);
                }
              }
            }
          }
        }
      }
    } catch (e, stackTrace) {
      print('❌ API ERROR in fetchTrendingMusic: $e');
      print('❌ API STACK: $stackTrace');
    }
    return list;
  }

  Future fetchTrendingGaming() async {
    String params = "4gIcGhpnYW1pbmdfY29ycHVzX21vc3RfcG9wdWxhcg";
    List list = [];
    var client = http.Client();
    try {
      var response = await client.get(
        Uri.parse(
          'https://www.youtube.com/feed/trending?bp=$params',
        ),
      );
      var raw = response.body;
      var root = parser.parse(raw);
      final scriptText = root
          .querySelectorAll('script')
          .map((e) => e.text)
          .toList(growable: false);
      var initialData = scriptText
          .firstWhereOrNull((e) => e.contains('var ytInitialData = '));
      initialData ??= scriptText
          .firstWhereOrNull((e) => e.contains('window["ytInitialData"] ='));

      if (initialData == null) {
        print('❌ API: Could not find ytInitialData in gaming page');
        return list;
      }

      var jsonMap = extractJson(initialData);
      if (jsonMap != null) {
        var tabs = jsonMap
            .get('contents')
            ?.get('twoColumnBrowseResultsRenderer')
            ?.getList('tabs');

        if (tabs != null) {
          for (var i = 0; i < tabs.length; i++) {
            var tab = tabs.elementAtSafe(i);
            var tabContents = tab
                ?.get('tabRenderer')
                ?.get('content')
                ?.get('sectionListRenderer')
                ?.getList('contents');

            if (tabContents != null) {
              for (var j = 0; j < tabContents.length; j++) {
                var section = tabContents.elementAtSafe(j);

                var richItems = section
                    ?.get('itemSectionRenderer')
                    ?.getList('contents')
                    ?.firstOrNull
                    ?.get('richGridRenderer')
                    ?.getList('contents');

                if (richItems != null && richItems.isNotEmpty) {
                  list.addAll(richItems);
                }

                var shelfItems = section
                    ?.get('itemSectionRenderer')
                    ?.getList('contents')
                    ?.firstOrNull
                    ?.get('shelfRenderer')
                    ?.get('content')
                    ?.get('expandedShelfContentsRenderer')
                    ?.getList('items');

                if (shelfItems != null && shelfItems.isNotEmpty) {
                  list.addAll(shelfItems);
                }
              }
            }
          }
        }
      }
    } catch (e, stackTrace) {
      print('❌ API ERROR in fetchTrendingGaming: $e');
      print('❌ API STACK: $stackTrace');
    }
    return list;
  }

  Future fetchTrendingMovies() async {
    String params = "4gIKGgh0cmFpbGVycw%3D%3D";
    List list = [];
    var client = http.Client();
    try {
      var response = await client.get(
        Uri.parse(
          'https://www.youtube.com/feed/trending?bp=$params',
        ),
      );
      var raw = response.body;
      var root = parser.parse(raw);
      final scriptText = root
          .querySelectorAll('script')
          .map((e) => e.text)
          .toList(growable: false);
      var initialData = scriptText
          .firstWhereOrNull((e) => e.contains('var ytInitialData = '));
      initialData ??= scriptText
          .firstWhereOrNull((e) => e.contains('window["ytInitialData"] ='));

      if (initialData == null) {
        print('❌ API: Could not find ytInitialData in movies page');
        return list;
      }

      var jsonMap = extractJson(initialData);
      if (jsonMap != null) {
        var tabs = jsonMap
            .get('contents')
            ?.get('twoColumnBrowseResultsRenderer')
            ?.getList('tabs');

        if (tabs != null) {
          for (var i = 0; i < tabs.length; i++) {
            var tab = tabs.elementAtSafe(i);
            var tabContents = tab
                ?.get('tabRenderer')
                ?.get('content')
                ?.get('sectionListRenderer')
                ?.getList('contents');

            if (tabContents != null) {
              for (var j = 0; j < tabContents.length; j++) {
                var section = tabContents.elementAtSafe(j);

                var richItems = section
                    ?.get('itemSectionRenderer')
                    ?.getList('contents')
                    ?.firstOrNull
                    ?.get('richGridRenderer')
                    ?.getList('contents');

                if (richItems != null && richItems.isNotEmpty) {
                  list.addAll(richItems);
                }

                var shelfItems = section
                    ?.get('itemSectionRenderer')
                    ?.getList('contents')
                    ?.firstOrNull
                    ?.get('shelfRenderer')
                    ?.get('content')
                    ?.get('expandedShelfContentsRenderer')
                    ?.getList('items');

                if (shelfItems != null && shelfItems.isNotEmpty) {
                  list.addAll(shelfItems);
                }
              }
            }
          }
        }
      }
    } catch (e, stackTrace) {
      print('❌ API ERROR in fetchTrendingMovies: $e');
      print('❌ API STACK: $stackTrace');
    }
    return list;
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
    var jsonMap = extractJson(initialData!);
    return jsonMap;
  }
}
