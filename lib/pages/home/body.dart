import 'package:flutter/material.dart';
import '/api/youtube_api.dart';
import '/widgets/video_widget.dart';

class Body extends StatefulWidget {
  List contentList;
  YoutubeApi youtubeApi;

  Body(
      {Key? key,
      required this.contentList,
      required this.youtubeApi,})
      : super(key: key) {
    print('📦 Body: Constructor called with ${contentList.length} items');
  }

  @override
  _BodyState createState() => _BodyState(contentList);
}

class _BodyState extends State<Body> {
  List contentList;

  _BodyState(this.contentList) {
    print('📦 _BodyState: Constructor called with ${contentList.length} items');
  }

  @override
  Widget build(BuildContext context) {
    print('📦 _BodyState: Building with ${contentList.length} items');
    return SafeArea(
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: contentList.length,
        itemBuilder: (context, index) {
          print('📦 _BodyState: Building item at index $index');
          if (contentList[index].containsKey('videoRenderer')) {
            print('📦 _BodyState: Item $index has videoRenderer');
            return video(index, contentList);
          }
          print('⚠️ _BodyState: Item $index does NOT have videoRenderer, keys: ${contentList[index].keys.toList()}');
          return Container();
        },
      ),
    );
  }

  Widget video(int index, List contentList) {
    print('🎥 video: Creating VideoWidget for index $index');
    try {
      var videoData = contentList[index]['videoRenderer'];
      print('🎥 video: videoId = ${videoData['videoId']}');
      return VideoWidget(
        videoId: videoData['videoId'],
        duration: videoData['lengthText']['simpleText'],
        title: videoData['title']['runs'][0]['text'],
        channelName: videoData['longBylineText']['runs'][0]['text'],
        views: videoData['shortViewCountText']['simpleText'],
      );
    } catch (e, stackTrace) {
      print('❌ video: Error creating VideoWidget: $e');
      print('❌ video: Stack: $stackTrace');
      return Container(
        padding: EdgeInsets.all(16),
        child: Text('Error loading video: $e'),
      );
    }
  }
}
