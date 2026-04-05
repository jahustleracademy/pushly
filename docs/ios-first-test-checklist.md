# Pushly iOS First Test Checklist

## 1. Xcode Signing
- Open `/Users/artur/Desktop/iOS_apps/pushly/ios/Pushly.xcworkspace`.
- Target `Pushly`:
  - `Automatically manage signing` enabled
  - Team selected
  - Bundle ID: `com.artur.pushly`
  - App Group: `group.com.pushly.shared`
  - Family Controls (Development) enabled
- Target `PushlyMonitorTarget`:
  - `Automatically manage signing` enabled
  - Team selected
  - Bundle ID: `com.artur.pushly.monitor`
  - App Group: `group.com.pushly.shared`
  - Family Controls (Development) enabled

## 2. Build + Install
- Connect a real iPhone.
- Select the `Pushly` scheme.
- Build and run from Xcode.

## 3. First Onboarding Test Flow
- Start app and open onboarding.
- Hero step: check the `TEST-READY CHECK` card.
- Continue to `Screen-Time Permission` step:
  - Tap authorize for Family Controls.
  - Open family picker and choose at least one app/category/domain.
- Continue to `Camera Calibration` and `Push-up Trial`:
  - Grant camera access.
  - Verify live camera preview appears.
  - Verify skeleton overlay and rep counter updates.
- Finish onboarding and ensure app routes into tabs/home.

## 4. Acceptance Criteria
- Family Controls status becomes approved.
- Stored selection is non-empty.
- Device monitoring status becomes active after app selection.
- Camera status becomes authorized.
- Push-up trial reaches rep target and unlocks continue CTA.

## 5. Known Gate
- Distribution warning for `Family Controls (Distribution)` is expected until Apple approves it.
- This does not block local development testing on device.
