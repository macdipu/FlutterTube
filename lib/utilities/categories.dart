import 'package:flutter/material.dart';
import 'package:flutter_utube/constants.dart';
import 'package:flutter_utube/theme/colors.dart';
import '/api/youtube_api.dart';

class Categories extends StatelessWidget {
  final List<YoutubeFilter> filters;
  final void Function(int) onSelected;
  final int selectedIndex;

  const Categories({
    Key? key,
    required this.filters,
    required this.onSelected,
    required this.selectedIndex,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) => _buildCategory(index),
      ),
    );
  }

  Widget _buildCategory(int index) {
    final filter = filters[index];
    final isSelected = selectedIndex == index;

    return GestureDetector(
      onTap: () => onSelected(index),
      child: isSelected
          ? Align(
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                margin: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: pink,
                ),
                child: Center(
                  child: Text(
                    filter.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PrimaryColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              margin: const EdgeInsets.symmetric(horizontal: 5),
              child: Center(
                child: Text(
                  filter.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff9e9e9e),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ),
    );
  }
}