# GoFast Admin Panel

Flutter Web administration dashboard with a live driver map and notification composer.

## Run

Replace `YOUR_GOOGLE_MAPS_API_KEY` in `web/index.html` with a Google Maps JavaScript API key restricted to the deployment's allowed web origins. Then run:

```sh
flutter run -d chrome
```

The admin panel uses `http://localhost:3000` when opened on `localhost` or `127.0.0.1`, and `https://goserver-i3ab.onrender.com` on other hosts, including GitHub Pages. To use a different API server, pass `--dart-define=API_BASE_URL=https://your-api.example.com` when running or building.

The API server must be running and configured with its admin login credentials for local development. The map reads an admin-protected fleet snapshot and authenticated Socket.IO updates.

## Firebase Photo Storage

The Web Firebase options for project `godrive-d7f94` are in `lib/firebase_options.dart`. Firebase Web API keys and app IDs are public client configuration, not credentials. Restrict the API key to the deployed web origins and the APIs this app uses; never place Firebase Admin service-account keys in this Flutter project.

Enable Firebase Authentication custom-token sign-in and create the Storage bucket `godrive-d7f94.firebasestorage.app`. The API server must use Firebase Admin credentials from the same project and bucket. Storage image reads are public because driver and rider apps render the download URLs; uploads and deletes are limited by Storage Rules to the authorized staff/driver record ID.

From `server`, deploy the rules with `npm run deploy:storage-rules`. To run the local Storage Rules tests, install the server development dependencies and run `npm run test:storage-rules` from `server`; the Firebase Storage Emulator requires Java 21 or newer.
