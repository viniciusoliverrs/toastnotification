import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'toast.dart';

class ToastRoute<T> extends OverlayRoute<T> {
  final Toast toast;
  final Builder _builder;
  final Completer<T> _transitionCompleter = Completer<T>();
  final ToastStatusCallback? _onStatusChanged;

  Animation<double>? _filterBlurAnimation;
  Animation<Color?>? _filterColorAnimation;
  Alignment? _initialAlignment;
  Alignment? _endAlignment;
  bool _wasDismissedBySwipe = false;
  Timer? _timer;
  T? _result;
  ToastStatus? currentStatus;

  ToastRoute({
    required this.toast,
    RouteSettings? settings,
  })  : _builder = Builder(builder: (BuildContext innerContext) {
          return GestureDetector(
            onTap: toast.onTap != null ? () => toast.onTap!(toast) : null,
            child: toast,
          );
        }),
        _onStatusChanged = toast.onStatusChanged,
        super(settings: settings) {
    _configureAlignment(toast.toastPosition);
  }

  void _configureAlignment(ToastPosition toastPosition) {
    switch (toast.toastPosition) {
      case ToastPosition.TOP:
        {
          _initialAlignment = const Alignment(-1.0, -2.0);
          _endAlignment = toast.endOffset != null
              ? const Alignment(-1.0, -1.0) +
                  Alignment(toast.endOffset!.dx, toast.endOffset!.dy)
              : const Alignment(-1.0, -1.0);
          break;
        }
      case ToastPosition.BOTTOM:
        {
          _initialAlignment = const Alignment(-1.0, 2.0);
          _endAlignment = toast.endOffset != null
              ? const Alignment(-1.0, 1.0) +
                  Alignment(toast.endOffset!.dx, toast.endOffset!.dy)
              : const Alignment(-1.0, 1.0);
          break;
        }
    }
  }

  Future<T> get completed => _transitionCompleter.future;
  bool get opaque => false;

  @override
  Future<RoutePopDisposition> willPop() {
    if (!toast.isDismissible) {
      return Future.value(RoutePopDisposition.doNotPop);
    }

    return Future.value(RoutePopDisposition.pop);
  }

  @override
  Iterable<OverlayEntry> createOverlayEntries() {
    final overlays = <OverlayEntry>[];

    if (toast.blockBackgroundInteraction) {
      overlays.add(
        OverlayEntry(
            builder: (BuildContext context) {
              return Listener(
                onPointerDown:
                    toast.isDismissible ? (_) => toast.dismiss() : null,
                child: _createBackgroundOverlay(),
              );
            },
            maintainState: false,
            opaque: opaque),
      );
    }

    overlays.add(
      OverlayEntry(
          builder: (BuildContext context) {
            final Widget annotatedChild = Semantics(
              focused: false,
              container: true,
              explicitChildNodes: true,
              child: AlignTransition(
                alignment: _animation!,
                child: toast.isDismissible
                    ? _getDismissibleToast(_builder)
                    : _getToast(),
              ),
            );
            return annotatedChild;
          },
          maintainState: false,
          opaque: opaque),
    );

    return overlays;
  }

  Widget _createBackgroundOverlay() {
    if (_filterBlurAnimation != null && _filterColorAnimation != null) {
      return AnimatedBuilder(
        animation: _filterBlurAnimation!,
        builder: (context, child) {
          return BackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: _filterBlurAnimation!.value,
                sigmaY: _filterBlurAnimation!.value),
            child: Container(
              constraints: const BoxConstraints.expand(),
              color: _filterColorAnimation!.value,
            ),
          );
        },
      );
    }

    if (_filterBlurAnimation != null) {
      return AnimatedBuilder(
        animation: _filterBlurAnimation!,
        builder: (context, child) {
          return BackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: _filterBlurAnimation!.value,
                sigmaY: _filterBlurAnimation!.value),
            child: Container(
              constraints: const BoxConstraints.expand(),
              color: Colors.transparent,
            ),
          );
        },
      );
    }

    if (_filterColorAnimation != null) {
      AnimatedBuilder(
        animation: _filterColorAnimation!,
        builder: (context, child) {
          return Container(
            constraints: const BoxConstraints.expand(),
            color: _filterColorAnimation!.value,
          );
        },
      );
    }

    return Container(
      constraints: const BoxConstraints.expand(),
      color: Colors.transparent,
    );
  }

  /// This string is a workaround until Dismissible supports a returning item
  String dismissibleKeyGen = '';

  Widget _getDismissibleToast(Widget child) {
    return Dismissible(
      direction: _getDismissDirection(),
      resizeDuration: null,
      confirmDismiss: (_) {
        if (currentStatus == ToastStatus.IS_APPEARING ||
            currentStatus == ToastStatus.IS_HIDING) {
          return Future.value(false);
        }
        return Future.value(true);
      },
      key: Key(dismissibleKeyGen),
      onDismissed: (_) {
        dismissibleKeyGen += '1';
        _cancelTimer();
        _wasDismissedBySwipe = true;

        if (isCurrent) {
          navigator!.pop();
        } else {
          navigator!.removeRoute(this);
        }
      },
      child: _getToast(),
    );
  }

  DismissDirection _getDismissDirection() {
    if (toast.dismissDirection == ToastDismissDirection.HORIZONTAL) {
      return DismissDirection.horizontal;
    } else {
      if (toast.toastPosition == ToastPosition.TOP) {
        return DismissDirection.up;
      } else {
        return DismissDirection.down;
      }
    }
  }

  Widget _getToast() {
    return Container(
      margin: toast.margin,
      child: _builder,
    );
  }

  @override
  bool get finishedWhenPopped =>
      _controller!.status == AnimationStatus.dismissed;

  /// The animation that drives the route's transition and the previous route's
  /// forward transition.
  Animation<Alignment>? get animation => _animation;
  Animation<Alignment>? _animation;

  /// The animation controller that the route uses to drive the transitions.
  ///
  /// The animation itself is exposed by the [animation] property.
  @protected
  AnimationController? get controller => _controller;
  AnimationController? _controller;

  /// Called to create the animation controller that will drive the transitions to
  /// this route from the previous one, and back to the previous route from this
  /// one.
  AnimationController createAnimationController() {
    assert(!_transitionCompleter.isCompleted,
        'Cannot reuse a $runtimeType after disposing it.');
    assert(toast.animationDuration >= Duration.zero);
    return AnimationController(
      duration: toast.animationDuration,
      debugLabel: debugLabel,
      vsync: navigator!,
    );
  }

  /// Called to create the animation that exposes the current progress of
  /// the transition controlled by the animation controller created by
  /// [createAnimationController()].
  Animation<Alignment> createAnimation() {
    assert(!_transitionCompleter.isCompleted,
        'Cannot reuse a $runtimeType after disposing it.');
    assert(_controller != null);
    return AlignmentTween(begin: _initialAlignment, end: _endAlignment).animate(
      CurvedAnimation(
        parent: _controller!,
        curve: toast.forwardAnimationCurve,
        reverseCurve: toast.reverseAnimationCurve,
      ),
    );
  }

  Animation<double>? createBlurFilterAnimation() {
    if (toast.routeBlur == null) return null;

    return Tween(begin: 0.0, end: toast.routeBlur).animate(
      CurvedAnimation(
        parent: _controller!,
        curve: const Interval(
          0.0,
          0.35,
          curve: Curves.easeInOutCirc,
        ),
      ),
    );
  }

  Animation<Color?>? createColorFilterAnimation() {
    if (toast.routeColor == null) return null;

    return ColorTween(begin: Colors.transparent, end: toast.routeColor).animate(
      CurvedAnimation(
        parent: _controller!,
        curve: const Interval(
          0.0,
          0.35,
          curve: Curves.easeInOutCirc,
        ),
      ),
    );
  }

  //copy of `routes.dart`
  void _handleStatusChanged(AnimationStatus status) {
    switch (status) {
      case AnimationStatus.completed:
        currentStatus = ToastStatus.SHOWING;
        if (_onStatusChanged != null) _onStatusChanged!(currentStatus);
        if (overlayEntries.isNotEmpty) overlayEntries.first.opaque = opaque;

        break;
      case AnimationStatus.forward:
        currentStatus = ToastStatus.IS_APPEARING;
        if (_onStatusChanged != null) _onStatusChanged!(currentStatus);
        break;
      case AnimationStatus.reverse:
        currentStatus = ToastStatus.IS_HIDING;
        if (_onStatusChanged != null) _onStatusChanged!(currentStatus);
        if (overlayEntries.isNotEmpty) overlayEntries.first.opaque = false;
        break;
      case AnimationStatus.dismissed:
        assert(!overlayEntries.first.opaque);
        // We might still be the current route if a subclass is controlling the
        // the transition and hits the dismissed status. For example, the iOS
        // back gesture drives this animation to the dismissed status before
        // popping the navigator.
        currentStatus = ToastStatus.DISMISSED;
        if (_onStatusChanged != null) _onStatusChanged!(currentStatus);

        if (!isCurrent) {
          navigator!.finalizeRoute(this);
          if (overlayEntries.isNotEmpty) {
            overlayEntries.clear();
          }
          assert(overlayEntries.isEmpty);
        }
        break;
    }
    changedInternalState();
  }

  @override
  void install() {
    assert(!_transitionCompleter.isCompleted,
        'Cannot install a $runtimeType after disposing it.');
    _controller = createAnimationController();
    assert(_controller != null,
        '$runtimeType.createAnimationController() returned null.');
    _filterBlurAnimation = createBlurFilterAnimation();
    _filterColorAnimation = createColorFilterAnimation();
    _animation = createAnimation();
    assert(_animation != null, '$runtimeType.createAnimation() returned null.');
    super.install();
  }

  @override
  TickerFuture didPush() {
    assert(_controller != null,
        '$runtimeType.didPush called before calling install() or after calling dispose().');
    assert(!_transitionCompleter.isCompleted,
        'Cannot reuse a $runtimeType after disposing it.');
    _animation!.addStatusListener(_handleStatusChanged);
    _configureTimer();
    super.didPush();
    return _controller!.forward();
  }

  @override
  void didReplace(Route<dynamic>? oldRoute) {
    assert(_controller != null,
        '$runtimeType.didReplace called before calling install() or after calling dispose().');
    assert(!_transitionCompleter.isCompleted,
        'Cannot reuse a $runtimeType after disposing it.');
    if (oldRoute is ToastRoute) {
      _controller!.value = oldRoute._controller!.value;
    }
    _animation!.addStatusListener(_handleStatusChanged);
    super.didReplace(oldRoute);
  }

  @override
  bool didPop(T? result) {
    assert(_controller != null,
        '$runtimeType.didPop called before calling install() or after calling dispose().');
    assert(!_transitionCompleter.isCompleted,
        'Cannot reuse a $runtimeType after disposing it.');

    _result = result;
    _cancelTimer();

    if (_wasDismissedBySwipe) {
      Timer(const Duration(milliseconds: 200), () {
        _controller!.reset();
      });

      _wasDismissedBySwipe = false;
    } else {
      _controller!.reverse();
    }

    return super.didPop(result);
  }

  void _configureTimer() {
    if (toast.duration != null) {
      if (_timer != null && _timer!.isActive) {
        _timer!.cancel();
      }
      _timer = Timer(toast.duration!, () {
        if (isCurrent) {
          navigator!.pop();
        } else if (isActive) {
          navigator!.removeRoute(this);
        }
      });
    } else {
      if (_timer != null) {
        _timer!.cancel();
      }
    }
  }

  void _cancelTimer() {
    if (_timer != null && _timer!.isActive) {
      _timer!.cancel();
    }
  }

  /// Whether this route can perform a transition to the given route.
  ///
  /// Subclasses can override this method to restrict the set of routes they
  /// need to coordinate transitions with.
  bool canTransitionTo(ToastRoute<dynamic> nextRoute) => true;

  /// Whether this route can perform a transition from the given route.
  ///
  /// Subclasses can override this method to restrict the set of routes they
  /// need to coordinate transitions with.
  bool canTransitionFrom(ToastRoute<dynamic> previousRoute) => true;

  @override
  void dispose() {
    assert(!_transitionCompleter.isCompleted,
        'Cannot dispose a $runtimeType twice.');
    _controller?.dispose();
    _transitionCompleter.complete(_result);
    super.dispose();
  }

  /// A short description of this route useful for debugging.
  String get debugLabel => '$runtimeType';

  @override
  String toString() => '$runtimeType(animation: $_controller)';
}

ToastRoute showToast<T>({required BuildContext context, required Toast toast}) {
  return ToastRoute<T>(
    toast: toast,
    settings: const RouteSettings(name: TOAST_ROUTE_NAME),
  );
}
