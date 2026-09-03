import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// The shared [Dio] instance used by every feature's API service layer.
final dioProvider = Provider<Dio>((ref) => ApiClient.create());
