# MultiLiveTV brand logos (icon-only)

App / site icon assets. **No wordmark images in app bundles.**

## Allowed

- `icon*` — pure icon, no “MultiLiveTV” text
- `app_dark*` / `app_white*` — app icon plates
- `favicon*` — favicon set (same mark, no wordmark)

## Forbidden in app packages

Do **not** copy these patterns into `clients/` or `web/` asset trees:

- `*transparent*` wordmark sheets
- `*dark_bg*` / `*white_bg*` marketing sheets with “MultiLiveTV” text

App **display name** (CFBundleDisplayName, Android `android:label`, header text, accessibility labels) may stay as plain text.

## Clients

- Apple: `Assets.xcassets` AppIcon / Logo / tvOS brandassets
- Android: `clients/android/app/src/main/res/mipmap-*` + `tv_banner`
- Web: `web/app/favicon.ico`, `web/app/icon.png`, `web/public/icon-*.png`
