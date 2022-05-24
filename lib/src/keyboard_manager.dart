import 'dart:io';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_interactive_keyboard/src/channel_receiver.dart';

import 'channel_manager.dart';

class KeyboardChange {
  final double offset;
  final bool tracking;
  final double? delta;

  KeyboardChange({
    required this.offset,
    required this.tracking,
    this.delta,
  });
}

typedef KeyboardChangeCallback = Function(KeyboardChange change);

class KeyboardManagerWidget extends StatefulWidget {
  /// The widget behind the view where the drag to close is enabled
  final Widget child;
  final double offset;

  final Function? onKeyboardOpen;
  final Function? onKeyboardClose;
  final KeyboardChangeCallback? keyboardChangeCallback;

  KeyboardManagerWidget({
    Key? key,
    required this.child,
    this.keyboardChangeCallback,
    this.offset = 0,
    this.onKeyboardOpen,
    this.onKeyboardClose,
  }) : super(key: key);

  KeyboardManagerWidgetState createState() => KeyboardManagerWidgetState();
}

class KeyboardManagerWidgetState extends State<KeyboardManagerWidget> {
  /// Only initialised on IOS
  late ChannelReceiver _channelReceiver;

  KeyboardChangeCallback? keyboardChangeCallback;

  List<int> _pointers = [];

  int? get activePointer => _pointers.length > 0 ? _pointers.first : null;

  List<double> _velocities = [];
  double _velocity = 0.0;
  int _lastTime = 0;
  double _lastPosition = 0.0;

  bool _keyboardOpen = false;

  double _keyboardHeight = 0.0;
  double _over = 0.0;

  bool dismissed = true;
  bool _dismissing = false;

  bool _hasScreenshot = false;

  @override
  void initState() {
    super.initState();
    keyboardChangeCallback = widget.keyboardChangeCallback;
    if (Platform.isIOS) {
      _channelReceiver = ChannelReceiver(() {
        _hasScreenshot = true;
      });
      _channelReceiver.init();
      ChannelManager.init();
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = EdgeInsets.fromWindowPadding(
        WidgetsBinding.instance!.window.viewInsets,
        WidgetsBinding.instance!.window.devicePixelRatio);
    var bottom = viewInsets.bottom;
    var keyboardOpen = bottom > 0;
    var oldKeyboardOpen = _keyboardOpen;
    _keyboardOpen = keyboardOpen;

    if (_keyboardOpen) {
      dismissed = false;
      _keyboardHeight = bottom;
      if (!oldKeyboardOpen && activePointer == null) {
        widget.onKeyboardOpen?.call();
      }
    } else {
      // Close notification if the keyobard closes while not dragging
      if (oldKeyboardOpen && activePointer == null) {
        widget.onKeyboardClose?.call();
        dismissed = true;
      }
    }

    return Listener(
      onPointerDown: (details) {
        //print("pointerDown $dismissed $_isAnimating $activePointer $_keyboardOpen ${_pointers.length} $_dismissing");
        if ((!dismissed && !_dismissing) || _keyboardOpen) {
          _pointers.add(details.pointer);
          if (_pointers.length == 1) {
            if (Platform.isIOS) {
              ChannelManager.startScroll(bottom);
            }
            _lastPosition = details.position.dy;
            _lastTime = DateTime.now().millisecondsSinceEpoch;
            _velocities.clear();
          }
        }
      },
      onPointerUp: (details) {
        if (details.pointer == activePointer && _pointers.length == 1) {
          //print("pointerUp $_velocity, $_over, ${details.pointer}, $activePointer");
          if (_over > 0) {
            if (Platform.isIOS) {
              if ((_velocity > 0.1 || _velocity < -0.3)) {
                if (_velocity > 0) {
                  _dismissing = true;
                  if (keyboardChangeCallback != null) {
                    keyboardChangeCallback!(KeyboardChange(
                      tracking: false,
                      offset: 0,
                    ));
                  }
                }
                ChannelManager.fling(_velocity).then((value) {
                  if (_velocity < 0) {
                    if (activePointer == null && !dismissed) {
                      showKeyboard(false);
                    }
                  } else {
                    _dismissing = false;
                    dismissed = true;
                    widget.onKeyboardClose?.call();
                  }
                });
              } else {
                if (keyboardChangeCallback != null) {
                  keyboardChangeCallback!(KeyboardChange(
                    tracking: false,
                    offset: _keyboardHeight,
                  ));
                }
                ChannelManager.expand().then((value) {
                  if (activePointer == null) {
                    showKeyboard(false);
                  }
                });
              }
            }
          }

          if (!Platform.isIOS) {
            if (!_keyboardOpen) {
              dismissed = true;
              widget.onKeyboardClose?.call();
            }
          }
        }
        _pointers.remove(details.pointer);
      },
      onPointerMove: (details) {
        if (details.pointer == activePointer) {
          var position = details.position.dy;
          _over = position -
              (MediaQuery.of(context).size.height - _keyboardHeight) -
              widget.offset;
          final delta = position - _lastPosition;
          updateVelocity(position);
          if (_over > 0) {
            if (Platform.isIOS) {
              if (_keyboardOpen && _hasScreenshot) hideKeyboard(false);
              ChannelManager.updateScroll(_over);
              if (keyboardChangeCallback != null) {
                keyboardChangeCallback!(KeyboardChange(
                  offset: max(0, _keyboardHeight - _over),
                  tracking: true,
                  delta: delta,
                ));
              }
            } else {
              if (_velocity > 0.1) {
                if (_keyboardOpen) {
                  hideKeyboard(true);
                }
              } else if (_velocity < -0.5) {
                if (!_keyboardOpen) {
                  showKeyboard(true);
                  widget.onKeyboardClose?.call();
                }
              }
            }
          } else {
            if (Platform.isIOS) {
              ChannelManager.updateScroll(0.0);
              if (!_keyboardOpen) {
                showKeyboard(false);
              }
            } else {
              if (!_keyboardOpen) {
                showKeyboard(true);
                widget.onKeyboardOpen?.call();
              }
            }
          }
        }
      },
      onPointerCancel: (details) {
        _pointers.remove(details.pointer);
      },
      child: widget.child,
    );
  }

  updateVelocity(double position) {
    var time = DateTime.now().millisecondsSinceEpoch;
    if (time - _lastTime > 0) {
      _velocity = (position - _lastPosition) / (time - _lastTime);
    }
    _lastPosition = position;
    _lastTime = time;
  }

  showKeyboard(bool animate) {
    if (!animate && Platform.isIOS) {
      ChannelManager.showKeyboard(true);
    } else {
      _showKeyboard();
    }
    if (keyboardChangeCallback != null) {
      keyboardChangeCallback!(KeyboardChange(
        tracking: false,
        offset: _keyboardHeight,
      ));
    }
  }

  _showKeyboard() {
    SystemChannels.textInput.invokeMethod('TextInput.show');
  }

  hideKeyboard(bool animate) {
    if (!animate && Platform.isIOS) {
      ChannelManager.showKeyboard(false);
    } else {
      _hideKeyboard();
    }
    if (keyboardChangeCallback != null) {
      keyboardChangeCallback!(KeyboardChange(
        tracking: false,
        offset: 0,
      ));
    }
  }

  _hideKeyboard() {
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    FocusScope.of(context).requestFocus(FocusNode());
  }

  Future<void> removeImageKeyboard() async {
    ChannelManager.updateScroll(_keyboardHeight);
  }

  Future<void> safeHideKeyboard() async {
    await removeImageKeyboard();
    _hideKeyboard();
  }
}
