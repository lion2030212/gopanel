# GoFast Admin Panel

Flutter Web administration dashboard with a live driver map and notification composer.

## Run

Replace `YOUR_GOOGLE_MAPS_API_KEY` in `web/index.html` with a Google Maps JavaScript API key restricted to the deployment's allowed web origins. Then run:

```sh
flutter run -d chrome
```

The admin panel uses `http://localhost:3000` when opened on `localhost` or `127.0.0.1`, and `https://goserver-i3ab.onrender.com` on other hosts, including GitHub Pages. To use a different API server, pass `--dart-define=API_BASE_URL=https://your-api.example.com` when running or building.

The API server must be running and configured with its admin login credentials for local development. The map reads an admin-protected fleet snapshot and authenticated Socket.IO updates.
