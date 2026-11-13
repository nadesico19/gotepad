#include "ios_pointer_input.hpp"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#include <godot_cpp/classes/input.hpp>
#include <godot_cpp/classes/input_event_key.hpp>
#include <godot_cpp/classes/input_event_magnify_gesture.hpp>
#include <godot_cpp/classes/input_event_mouse_button.hpp>
#include <godot_cpp/classes/input_event_mouse_motion.hpp>

@interface GotepadPointerScroll : UIPanGestureRecognizer
@property(nonatomic) CGFloat pending_scroll;
- (void)forward_scroll:(UIPanGestureRecognizer*)sender;
@end

@interface GotepadPointerPinch : UIPinchGestureRecognizer
- (void)forward_pinch:(UIPinchGestureRecognizer*)sender;
@end

namespace nd::go::gdext {
namespace {

using TouchHandler = void (*)(UIView*, SEL, NSSet<UITouch*>*, UIEvent*);
enum class PointerPhase { down, move, up, cancel };

godot::Vector2 pointer_position(UIView* view, CGPoint position) {
  return godot::Vector2(position.x, position.y) * view.contentScaleFactor;
}

void send_mouse_button(const godot::Vector2& position, godot::MouseButton index,
                       godot::MouseButtonMask mask, bool pressed,
                       bool canceled = false, bool double_click = false) {
  godot::Ref<godot::InputEventMouseButton> button;
  button.instantiate();
  button->set_position(position);
  button->set_global_position(position);
  button->set_button_index(index);
  button->set_button_mask(mask);
  button->set_pressed(pressed);
  button->set_canceled(canceled);
  button->set_double_click(double_click);
  godot::Input::get_singleton()->parse_input_event(button);
}

void dispatch_pointer(UIView* view, UITouch* touch, UIEvent* event, PointerPhase phase) {
  static char button_key;
  const bool pressed = phase == PointerPhase::down;
  if (pressed) {
    const bool secondary = (event.buttonMask & UIEventButtonMaskSecondary) != 0;
    objc_setAssociatedObject(touch, &button_key, @(secondary), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
  NSNumber* secondary = objc_getAssociatedObject(touch, &button_key);
  if (secondary == nil) return;

  const auto index = secondary.boolValue ? godot::MOUSE_BUTTON_RIGHT : godot::MOUSE_BUTTON_LEFT;
  const auto mask = secondary.boolValue ? godot::MOUSE_BUTTON_MASK_RIGHT : godot::MOUSE_BUTTON_MASK_LEFT;
  const auto position = pointer_position(view, [touch locationInView:view]);
  if (phase == PointerPhase::move) {
    godot::Ref<godot::InputEventMouseMotion> motion;
    motion.instantiate();
    motion->set_position(position);
    motion->set_global_position(position);
    motion->set_relative(position - pointer_position(view, [touch previousLocationInView:view]));
    motion->set_button_mask(mask);
    godot::Input::get_singleton()->parse_input_event(motion);
    return;
  }

  if (!pressed) objc_setAssociatedObject(touch, &button_key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  send_mouse_button(position, index, pressed ? mask : godot::MouseButtonMask{},
                    pressed, phase == PointerPhase::cancel, pressed && touch.tapCount > 1);
}

void attach_pointer_gestures(UIView* view) {
  if (view.window == nil) return;
  for (UIGestureRecognizer* recognizer in view.gestureRecognizers) {
    if ([recognizer isKindOfClass:GotepadPointerScroll.class]) return;
  }
  const UIScrollTypeMask scroll_types[] = {UIScrollTypeMaskDiscrete, UIScrollTypeMaskContinuous};
  for (UIScrollTypeMask type : scroll_types) {
    GotepadPointerScroll* scroll = [[GotepadPointerScroll alloc] initWithTarget:nil action:nil];
    [scroll addTarget:scroll action:@selector(forward_scroll:)];
    scroll.allowedTouchTypes = @[];
    scroll.allowedScrollTypesMask = type;
    scroll.cancelsTouchesInView = NO;
    [view addGestureRecognizer:scroll];
  }
  GotepadPointerPinch* pinch = [[GotepadPointerPinch alloc] initWithTarget:nil action:nil];
  [pinch addTarget:pinch action:@selector(forward_pinch:)];
  // Indirect pinches arrive as transform events. Keep screen touches in Godot.
  pinch.allowedTouchTypes = @[];
  pinch.cancelsTouchesInView = NO;
  [view addGestureRecognizer:pinch];
}

void attach_pointer_gestures_to_existing_views(UIView* view, Class view_class) {
  if ([view isKindOfClass:view_class]) {
    attach_pointer_gestures(view);
    return;
  }
  for (UIView* child in view.subviews) attach_pointer_gestures_to_existing_views(child, view_class);
}

void install_pointer_gestures(Class view_class) {
  SEL selector = @selector(didMoveToWindow);
  Method method = class_getInstanceMethod(view_class, selector);
  auto original = reinterpret_cast<void (*)(UIView*, SEL)>(method_getImplementation(method));
  IMP handler = imp_implementationWithBlock(^(UIView* view) {
    original(view, selector);
    attach_pointer_gestures(view);
  });
  // Add a local override when the method is inherited from UIView.
  if (!class_addMethod(view_class, selector, handler, method_getTypeEncoding(method))) {
    method_setImplementation(method, handler);
  }
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:UIWindowScene.class]) continue;
    for (UIWindow* window in ((UIWindowScene*)scene).windows) {
      attach_pointer_gestures_to_existing_views(window, view_class);
    }
  }
}

// UIKit owns text composition while the Godot text view is first responder.
void forward_editor_shortcuts() {
  Class keyboard_class = NSClassFromString(@"GDTKeyboardInputView");
  if (keyboard_class == Nil) return;
  const SEL selectors[] = {@selector(pressesBegan:withEvent:),
                           @selector(pressesEnded:withEvent:),
                           @selector(pressesCancelled:withEvent:)};
  using PressHandler = void (*)(UIResponder*, SEL, NSSet<UIPress*>*, UIPressesEvent*);
  for (SEL selector : selectors) {
    Method method = class_getInstanceMethod(keyboard_class, selector);
    if (method == nullptr) continue;
    auto original = reinterpret_cast<PressHandler>(method_getImplementation(method));
    const bool pressed = selector == @selector(pressesBegan:withEvent:);
    IMP handler = imp_implementationWithBlock(
        ^(UIResponder* responder, NSSet<UIPress*>* presses, UIPressesEvent* event) {
          NSMutableSet<UIPress*>* remaining = [presses mutableCopy];
          for (UIPress* press in presses) {
            UIKey* key = press.key;
            if (key == nil) continue;
            const auto modifiers = key.modifierFlags;
            if (modifiers & (UIKeyModifierControl | UIKeyModifierAlternate | UIKeyModifierCommand)) continue;
            godot::Key code;
            if (key.keyCode == UIKeyboardHIDUsageKeyboardTab) code = godot::KEY_TAB;
            else if (key.keyCode == UIKeyboardHIDUsageKeyboardEscape) code = godot::KEY_ESCAPE;
            else continue;
            [remaining removeObject:press];
            godot::Ref<godot::InputEventKey> input;
            input.instantiate();
            input->set_keycode(code);
            input->set_physical_keycode(code);
            input->set_shift_pressed((modifiers & UIKeyModifierShift) != 0);
            input->set_pressed(pressed);
            godot::Input::get_singleton()->parse_input_event(input);
          }
          if (remaining.count != 0) original(responder, selector, remaining, event);
        });
    if (!class_addMethod(keyboard_class, selector, handler, method_getTypeEncoding(method))) {
      method_setImplementation(method, handler);
    }
  }
}

void route_touches(UIView* view, SEL selector, NSSet<UITouch*>* touches, UIEvent* event,
                   TouchHandler original, PointerPhase phase) {
  NSMutableSet<UITouch*>* direct_touches = nil;
  for (UITouch* touch in touches) {
    if (touch.type != UITouchTypeIndirectPointer) continue;
    if (direct_touches == nil) direct_touches = [touches mutableCopy];
    [direct_touches removeObject:touch];
    dispatch_pointer(view, touch, event, phase);
  }
  NSSet<UITouch*>* remaining = direct_touches ?: touches;
  if (remaining.count != 0) original(view, selector, remaining, event);
}

} // namespace

void install_ios_pointer_input() {
  // Godot 4.7's GDTView handles pointer clicks through UIKit touch callbacks.
  Class view_class = NSClassFromString(@"GDTView");
  const SEL selectors[] = {
      @selector(touchesBegan:withEvent:), @selector(touchesMoved:withEvent:),
      @selector(touchesEnded:withEvent:), @selector(touchesCancelled:withEvent:)};
  const PointerPhase phases[] = {
      PointerPhase::down, PointerPhase::move, PointerPhase::up, PointerPhase::cancel};
  Method methods[4];
  for (unsigned i = 0; i < 4; ++i) {
    methods[i] = class_getInstanceMethod(view_class, selectors[i]);
    if (methods[i] == nullptr) {
      NSLog(@"Gotepad: could not find Godot's iOS pointer input handlers.");
      return;
    }
  }
  for (unsigned i = 0; i < 4; ++i) {
    SEL selector = selectors[i];
    PointerPhase phase = phases[i];
    auto original = reinterpret_cast<TouchHandler>(method_getImplementation(methods[i]));
    method_setImplementation(methods[i], imp_implementationWithBlock(
        ^(UIView* view, NSSet<UITouch*>* touches, UIEvent* event) {
          route_touches(view, selector, touches, event, original, phase);
        }));
  }
  install_pointer_gestures(view_class);
  forward_editor_shortcuts();
}

} // namespace nd::go::gdext

@implementation GotepadPointerScroll

- (void)forward_scroll:(UIPanGestureRecognizer*)sender {
  if (sender.state == UIGestureRecognizerStateBegan) self.pending_scroll = 0;
  if (sender.state != UIGestureRecognizerStateBegan &&
      sender.state != UIGestureRecognizerStateChanged) return;

  UIView* view = sender.view;
  const CGFloat delta = [sender translationInView:view].y;
  [sender setTranslation:CGPointZero inView:view];
  if (delta == 0) return;

  constexpr CGFloat kTrackpadPointsPerStep = 24;
  const bool discrete = self.allowedScrollTypesMask == UIScrollTypeMaskDiscrete;
  self.pending_scroll += discrete ? (delta > 0 ? 1 : -1) : delta;
  const CGFloat step = discrete ? 1 : kTrackpadPointsPerStep;
  const auto position = nd::go::gdext::pointer_position(view, [sender locationInView:view]);
  while (self.pending_scroll >= step || self.pending_scroll <= -step) {
    const bool up = self.pending_scroll > 0;
    self.pending_scroll += up ? -step : step;
    const auto button = up ? godot::MOUSE_BUTTON_WHEEL_UP : godot::MOUSE_BUTTON_WHEEL_DOWN;
    nd::go::gdext::send_mouse_button(position, button, {}, true);
    nd::go::gdext::send_mouse_button(position, button, {}, false);
  }
}

@end


@implementation GotepadPointerPinch

- (void)forward_pinch:(UIPinchGestureRecognizer*)sender {
  if (sender.state != UIGestureRecognizerStateBegan &&
      sender.state != UIGestureRecognizerStateChanged) return;

  const CGFloat factor = sender.scale;
  sender.scale = 1.0;
  if (factor <= 0 || factor == 1.0) return;

  UIView* view = sender.view;
  godot::Ref<godot::InputEventMagnifyGesture> gesture;
  gesture.instantiate();
  gesture->set_position(nd::go::gdext::pointer_position(view, [sender locationInView:view]));
  gesture->set_factor(factor);
  godot::Input::get_singleton()->parse_input_event(gesture);
}

@end
