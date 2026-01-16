import 'package:flutter/material.dart';
import 'package:flutter_utube/pages/home/subscribed_channels.dart';
import '../../constants.dart';
import '../../theme/colors.dart';
import '../../utilities/categories.dart';
import '/api/youtube_api.dart';
import '/pages/home/body.dart';
import '/utilities/custom_app_bar.dart';
import '/widgets/loading.dart';
import 'package:flutter/foundation.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  YoutubeApi youtubeApi = YoutubeApi();
  List contentList = [];
  List<YoutubeFilter> filters = const [YoutubeFilter(title: 'All', params: '')];
  int _selectedIndex = 0;
  late Future<TrendingResult> trending;
  int trendingIndex = 0;
  late double progressPosition;

  @override
  void initState() {
    super.initState();
    print('🚀 HomePage: initState called');
    trending = youtubeApi.fetchExplore();
    print('🔄 HomePage: fetchExplore initiated');
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    progressPosition = MediaQuery.of(context).size.height / 0.5;
    return Scaffold(
      backgroundColor: SecondaryColor,
      appBar: CustomAppBar(),
      body: body(),
      bottomNavigationBar: customBottomNavigationBar(),
    );
  }

  Widget body() {
    switch (_selectedIndex) {
      case 1:
        return SubscribedChannels();
      case 2:
        return Center(
          child: Text("TODO"),
        );
      case 3:
        return Center(
          child: Text("TODO"),
        );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<TrendingResult>(
        future: trending,
        builder: (BuildContext context, AsyncSnapshot<TrendingResult> snapshot) {
          print('📡 FutureBuilder: connectionState = ${snapshot.connectionState}');

          if (snapshot.connectionState == ConnectionState.waiting ||
              snapshot.connectionState == ConnectionState.active) {
            print('⏳ FutureBuilder: waiting/active...');
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  _categoriesBar(filters),
                  Padding(
                    padding: EdgeInsets.only(top: 300),
                    child: loading(),
                  ),
                ],
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.none) {
            print('❌ FutureBuilder: Connection None');
            return const Text("Connection None");
          }

          if (snapshot.hasError) {
            print('❌ FutureBuilder ERROR: ${snapshot.error}');
            print('❌ FutureBuilder STACK: ${snapshot.stackTrace}');
            return Container(child: Text(snapshot.stackTrace.toString()));
          }

          if (!snapshot.hasData) {
            print('⚠️ FutureBuilder: no data');
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  _categoriesBar(filters),
                  const Center(child: Text("No data")),
                ],
              ),
            );
          }

          final result = snapshot.data!;
          final fetchedFilters = result.filters.isNotEmpty ? result.filters : filters;
          _syncFilters(fetchedFilters);
          contentList = result.items;

          print('✅ FutureBuilder: has data, length = ${contentList.length}');

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                _categoriesBar(filters),
                contentList.isNotEmpty
                    ? Body(contentList: contentList, youtubeApi: youtubeApi)
                    : const Padding(
                        padding: EdgeInsets.symmetric(vertical: 120),
                        child: Center(child: Text("No data")),
                      ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _categoriesBar(List<YoutubeFilter> data) {
    return Padding(
      padding: EdgeInsets.only(left: 10, right: 10, top: 18, bottom: 10),
      child: Categories(
        filters: data,
        onSelected: changeTrendingState,
        selectedIndex: trendingIndex.clamp(0, data.isEmpty ? 0 : data.length - 1),
      ),
    );
  }

  Widget customBottomNavigationBar() {
    return Container(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.only(
              topRight: Radius.circular(30), topLeft: Radius.circular(30)),
          boxShadow: [
            BoxShadow(color: Colors.black12, spreadRadius: 0, blurRadius: 10),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(30.0),
            topRight: Radius.circular(30.0),
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            type: BottomNavigationBarType.fixed,
            showUnselectedLabels: true,
            onTap: _onItemTapped,
            backgroundColor: const Color(0xff424242),
            selectedItemColor: pink,
            selectedLabelStyle: TextStyle(fontFamily: 'Cairo'),
            unselectedLabelStyle: TextStyle(fontFamily: 'Cairo'),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.local_fire_department),
                label: 'Trending',
              ),
              BottomNavigationBarItem(
                  icon: Icon(Icons.live_tv), label: 'Subscriptions'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.history), label: 'History'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.cloud_download), label: 'Downloads')
            ],
          ),
        ));
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void changeTrendingState(int index) {
    if (index < 0 || index >= filters.length) {
      return;
    }
    setState(() {
      trendingIndex = index;
      final query = '${filters[index].title.toLowerCase()} trending';
      trending = youtubeApi
          .fetchSearchVideo(query)
          .then((items) => TrendingResult(items: items, filters: filters));
      contentList = [];
    });
  }

  void _syncFilters(List<YoutubeFilter> fetched) {
    final currentKeys = filters.map((f) => '${f.title}|${f.params}').toList();
    final nextKeys = fetched.map((f) => '${f.title}|${f.params}').toList();
    if (!listEquals(currentKeys, nextKeys)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          filters = fetched;
          if (trendingIndex >= filters.length) {
            trendingIndex = 0;
          }
        });
      });
    }
  }

  Future<bool> _refresh() async {
    print('🔄 _refresh: Starting refresh...');
    final latestFilters = await youtubeApi.fetchExploreFiltersFromWeb();
    final effectiveFilters = latestFilters.isNotEmpty ? latestFilters : filters;
    final safeIndex = effectiveFilters.isEmpty
        ? 0
        : trendingIndex.clamp(0, effectiveFilters.length - 1);
    final selectedFilter =
        effectiveFilters.isNotEmpty ? effectiveFilters[safeIndex] : const YoutubeFilter(title: 'All', params: '');
    final query = '${selectedFilter.title.toLowerCase()} trending';
    final items = await youtubeApi.fetchSearchVideo(query);

    print('🔄 _refresh: Received ${items.length} items');

    if (mounted) {
      setState(() {
        filters = effectiveFilters.isNotEmpty ? effectiveFilters : filters;
        trendingIndex = safeIndex;
        contentList = items;
        trending = Future.value(TrendingResult(items: items, filters: filters));
      });
    }

    if (items.isEmpty) {
      print('⚠️ _refresh: New list is empty');
      return false;
    }

    print('✅ _refresh: Updated content list');
    return true;
  }
}
