# Theme Pack JSON Schema (Draft)

The app can consume remote theme packs from:

- `GET /api/v1/theme-packs`

Expected response:

```json
[
  {
    "familyId": "tokyoNight",
    "displayName": "Tokyo Night",
    "lightAccent": 4286227191,
    "darkAccent": 4286443519,
    "highContrastAccent": 4280098077
  }
]
```

Notes:

- Accent values are ARGB integers (`Color.toARGB32()` format).
- Unknown/invalid payloads are ignored and local built-in packs are used.
