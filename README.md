# ScanPro — Flutter source starter

This package contains the first working source-code stage of ScanPro, an Android-first PDF scanner starter.

## Currently implemented
- Modern ScanPro home screen and bottom navigation
- Capture a single image using the camera
- Import multiple images from the gallery
- Convert selected images into one A4 PDF
- Save generated PDFs inside app-private storage
- Import an existing PDF into the ScanPro library
- List/search saved PDFs
- Open PDFs with an installed Android PDF viewer
- Share, rename, and delete saved PDFs
- Basic storage summary and error messages

## Not implemented yet
- Automatic document edge detection
- Manual crop handles and perspective correction
- Document enhancement filters
- Merge/split/compress existing PDFs
- PDF page reordering/rotation
- OCR and Hindi OCR
- PDF password encryption
- Built-in PDF viewer, cloud backup, and app lock

The UI marks unfinished tools honestly rather than pretending they work.

## Create the Android project

Install Flutter SDK and Android Studio/Android SDK, then run:

```bash
flutter create --platforms=android scanpro
```

Copy this package's `pubspec.yaml` and `lib/main.dart` into the generated `scanpro` folder, replacing the files created by Flutter.

Then run:

```bash
cd scanpro
flutter pub get
flutter run
```

To build a debug APK:

```bash
flutter build apk --debug
```

The APK is usually created at:

`build/app/outputs/flutter-apk/app-debug.apk`

## Android permissions
`image_picker` uses Android's system camera/gallery flows. If Flutter's generated Android project requires additional setup for your specific SDK or plugin version, follow the package's current Android installation instructions. Do not add broad storage permissions unless a feature genuinely needs them.

## Important
This source package has not been compiled or tested in an Android build environment here. Run `flutter pub get` and `flutter run` on your machine, and resolve any dependency/API compatibility messages for your installed Flutter version before using it as a release app.

Keep a backup of the project before adding more features.
