import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:koshian5_tentomushi_mesh/home_page.dart';

final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
          path: '/',
          builder: (BuildContext ctx, GoRouterState state) => const HomePage()
      ),
    ]
  )
);
