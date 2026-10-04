# 🎨 Risiti Logo Assets - Usage Guide

Your complete logo asset pack for iOS, Android, Web, and Splash Screens.

---

## 📦 What's Included

This package contains **25 ready-to-use PNG files** organized into 4 folders:

### **iOS** (5 files)
```
risiti_icon_120@120px.png      # Spotlight, iPhone (60@2x)
risiti_icon_180@180px.png      # Settings, iPhone Max (60@3x)
risiti_icon_152@152px.png      # iPad
risiti_icon_167@167px.png      # iPad Pro
risiti_icon_1024@1024px.png    # App Store (REQUIRED)
```

### **Android** (7 files)
```
risiti_icon_ldpi@36px.png      # ldpi density (0.75x)
risiti_icon_mdpi@48px.png      # mdpi density (1x baseline)
risiti_icon_hdpi@72px.png      # hdpi density (1.5x)
risiti_icon_xhdpi@96px.png     # xhdpi density (2x)
risiti_icon_xxhdpi@144px.png   # xxhdpi density (3x)
risiti_icon_xxxhdpi@192px.png  # xxxhdpi density (4x)
risiti_icon_playstore@512px.png # Google Play Store (REQUIRED)
```

### **Web** (5 files)
```
risiti_favicon_16@16px.png     # Browser tab favicon
risiti_favicon_32@32px.png     # Favicon HD (recommended)
risiti_apple_touch_180@180px.png # Apple Touch Icon (iOS home screen)
risiti_logo_web_256@256px.png  # Website logo
risiti_opengraph_1200@1200px.png # Social media sharing
```

### **SplashScreens** (8 files)

**Android:**
```
risiti_splash_android_phone_portrait@1080x1920px.png
risiti_splash_android_phone_landscape@1920x1080px.png
risiti_splash_android_tablet_portrait@1440x2560px.png
risiti_splash_android_tablet_landscape@2560x1440px.png
```

**iOS:**
```
risiti_splash_iphone_14_15@1170x2532px.png
risiti_splash_iphone_13_12@1170x2532px.png
risiti_splash_iphone_se@640x1136px.png
risiti_splash_ipad_pro_129@2048x2732px.png
```

---

## 🚀 Using with Claude Code

### **1. For Mobile App Development (Elixir/Mob Framework)**

**Copy files to your project:**
```bash
# For Android app
cp risiti_logo_assets/Android/* your_project/assets/android/mipmap-*/

# For iOS app
cp risiti_logo_assets/iOS/* your_project/assets/ios/AppIcon.appiconset/

# For Splash screens
cp risiti_logo_assets/SplashScreens/* your_project/assets/splash/
```

**In Claude Code:**
1. Upload the entire `risiti_logo_assets` folder
2. Reference specific sizes in your build configuration
3. For Elixir/Mob: Configure in your app manifest files

### **2. For Website**

**Copy web assets:**
```bash
cp risiti_logo_assets/Web/* your_website/public/
```

**Add to HTML:**
```html
<!-- Favicon -->
<link rel="icon" type="image/png" href="/risiti_favicon_32@32px.png">
<link rel="apple-touch-icon" href="/risiti_apple_touch_180@180px.png">

<!-- Open Graph (social sharing) -->
<meta property="og:image" content="/risiti_opengraph_1200@1200px.png">

<!-- In header -->
<img src="/risiti_logo_web_256@256px.png" alt="Risiti Logo" class="logo">
```

### **3. For Splash Screens**

**Android (in your build.gradle or manifest):**
```xml
<!-- Use appropriate density folder -->
res/drawable-mdpi/splash_screen.png → risiti_splash_android_phone_portrait@1080x1920px.png
```

**iOS (in Xcode):**
```
Assets.xcassets → LaunchScreen → Use 1170x2532 version for iPhone 14/15
```

---

## 🎯 Quick Reference - Which Size to Use

| Use Case | File | Size |
|----------|------|------|
| **App Store (iOS)** | `risiti_icon_1024@1024px.png` | 1024×1024 |
| **Play Store (Android)** | `risiti_icon_playstore@512px.png` | 512×512 |
| **Website Logo** | `risiti_logo_web_256@256px.png` | 256×256 |
| **Favicon** | `risiti_favicon_32@32px.png` | 32×32 |
| **Social Sharing** | `risiti_opengraph_1200@1200px.png` | 1200×1200 |
| **App Icon (Android)** | `risiti_icon_xxxhdpi@192px.png` | 192×192 |
| **App Icon (iOS)** | `risiti_icon_180@180px.png` | 180×180 |

---

## 💾 Storage Locations in Your Project

### **Recommended folder structure:**
```
your_project/
├── public/
│   └── images/
│       ├── risiti_favicon_32@32px.png
│       ├── risiti_logo_web_256@256px.png
│       └── risiti_opengraph_1200@1200px.png
├── assets/
│   ├── splash/
│   │   └── [splash screen images]
│   ├── android/
│   │   ├── mipmap-ldpi/
│   │   ├── mipmap-mdpi/
│   │   ├── mipmap-hdpi/
│   │   ├── mipmap-xhdpi/
│   │   ├── mipmap-xxhdpi/
│   │   └── mipmap-xxxhdpi/
│   └── ios/
│       └── AppIcon.appiconset/
```

---

## 🔧 For Claude Code - Asset Management

When working with Claude Code:

1. **Upload the ZIP file** to your project
2. **Extract to assets folder**: `unzip risiti_logo_assets.zip`
3. **Tell Claude Code:**
   - "Use `risiti_icon_1024@1024px.png` for the iOS App Store"
   - "Place Android icons from the `Android/` folder in `res/mipmap-*` directories"
   - "Add the splash screens to the project"

4. **Reference in code:**
   ```kotlin
   // Android (Kotlin)
   val appIcon = R.drawable.ic_launcher_risiti
   ```

   ```swift
   // iOS (Swift)
   Image("AppIcon")
   ```

   ```javascript
   // Web/React
   import logo from './images/risiti_logo_web_256@32px.png'
   ```

---

## ✅ Deployment Checklist

- [ ] iOS: Add `risiti_icon_1024@1024px.png` to App Store Connect
- [ ] Android: Add `risiti_icon_playstore@512px.png` to Google Play Console
- [ ] Web: Add favicon and social meta tags
- [ ] Web: Test social sharing with Open Graph image
- [ ] Splash Screens: Test on actual devices (iOS Simulator + Android Emulator)
- [ ] App Icons: Verify they display correctly on home screens

---

## 📝 Notes

- All images have **transparent backgrounds** (RGBA PNG format)
- **No watermarks** or extra branding applied
- **Ready for production** - no additional processing needed
- **Gradient background** uses your brand teal color (#2a4f4a to #0f2622)
- **White stroke** receipt outline (6px at 200px base size)

---

## 🎨 Customization

Need to adjust colors or add text? Tell Claude Code:
- "Change the background color to [color]"
- "Add 'RISITI' text to the splash screens"
- "Adjust the logo size in the splash screens"

I can regenerate any size with custom modifications!

---

## 📞 Support

If you need:
- Different sizes
- Custom colors
- Logo variations
- File format changes (WebP, AVIF, etc.)
- Animated versions

Just ask Claude Code to generate them for you! 🚀
