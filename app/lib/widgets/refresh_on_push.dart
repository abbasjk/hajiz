import 'package:flutter/widgets.dart';

import '../state/app_scope.dart';

/// يعيد تحميل الشاشة عندما يصل إشعار والتطبيق مفتوح
mixin RefreshOnPush<T extends StatefulWidget> on State<T> {
  ValueNotifier<int>? _tick;

  void onPush();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tick = AppScope.of(context).pushTick;
    if (tick != _tick) {
      _tick?.removeListener(onPush);
      _tick = tick..addListener(onPush);
    }
  }

  @override
  void dispose() {
    _tick?.removeListener(onPush);
    super.dispose();
  }
}
