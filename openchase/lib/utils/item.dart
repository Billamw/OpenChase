import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';

class Item {
  final String id;
  final String name;
  final String description;
  final String image;
  final LatLng location;

  Item({
    required this.id,
    required this.name,
    required this.description,
    required this.image,
    required this.location,
  });
}