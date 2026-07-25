# Album of the Day

A static site generator for **Album of the Day**, built with Ruby and ERB templates. The site provides a perpetual calendar of curated and recommended albums of the day with streaming provider links, RSS feeds, stats, and random album discovery.

## Features

* **Year-Independent Perpetual Calendar**: Albums are indexed by date (`MM-DD`) rather than specific years. Pages are served from permanent URLs like `/03/31.html` or `/07/24.html`.
* **Verbose Date Formats**: All displayed dates are formatted verbosely (e.g. *31st of March*, *24th of July*).
* **Dynamic Redirects**:
  * `index.html`: Client-side JavaScript redirects dynamically to today's month/day (`./MM/DD.html`) based on the visitor's local date.
  * `random.html`: Client-side JavaScript redirects dynamically to a random date page from the active calendar year.
* **Perpetual Circular Navigation**: Previous and Next navigation arrows cycle smoothly through all 365 days of the year (wrapping `12/31` to `01/01`), with leap year (`02/29`) support.
* **Spotify ID Caching & Fallbacks**: API responses from Songlink and Bandcamp cover images are cached on disk by Spotify ID and URL to prevent rate limits and repeated HTTP lookups.
* **Multi-Platform Provider Links & RSS Feeds**: Generates ATOM RSS feeds and CSV files for supported streaming platforms (Spotify, Apple Music, Bandcamp, Deezer, Tidal, YouTube, etc.).

## Input Files

### Config File (`config.yml` / `config_override.yml`)

* **Format**: YAML
* **File name**: `config.yml` (can be overridden by `config_override.yml`)
* **Keys**:
  - `cache`: Directory path to cache Songlink JSON responses (`./cache`)
  - `rss_dir`: Output directory for generated RSS ATOM XML feeds (`./public/rss`)
  - `csv_dir`: Output directory for generated provider CSV files (`./public/csv/`)
  - `html_dir`: Output directory for generated static HTML site (`./public`)
  - `csv_file`: Main curated CSV file (`./album_of_the_day.csv`)
  - `backup_csv_file`: Fallback CSV file for unassigned dates (`./random_album_of_the_day.csv`)
  - `songlink_api`: Base URL for the Songlink/Odesli API (`https://api.song.link/v1-alpha.1/links`)
  - `url_parameters`: Default parameters for API lookups (e.g. `userCountry: "FR"`)
  - `rss` (optional):
    - `author`: Author name for RSS feeds
    - `base_url`: Base URL for RSS feeds
  - `lastfm` (optional):
    - `api_key`: Last.fm API Key
    - `base_url`: `http://ws.audioscrobbler.com/2.0/`
  - `panelbear_site` (optional): Site ID for Panelbear analytics

Example (`config.yml`):

```yaml
url: "https://somewhere.org/aotd/"
cache: "./cache"
rss_dir: "./public/rss"
csv_dir: "./public/csv/"
html_dir: "./public"
csv_file: "./album_of_the_day.csv"
backup_csv_file: "./random_album_of_the_day.csv"
songlink_api: "https://api.song.link/v1-alpha.1/links"
url_parameters:
  userCountry: "FR"
rss:
  author: "mortenjohs"
  base_url: "https://somewhere.org/aotd/rss/"
lastfm:
  api_key: "API_KEY"
  base_url: "http://ws.audioscrobbler.com/2.0/"
panelbear_site: "SITE_KEY"
```

### CSV Files (`album_of_the_day.csv` & `random_album_of_the_day.csv`)

* **Format**: Comma-Separated Values (CSV)
* **Date Format**: `MM-DD` (e.g. `03-31`, `07-24`). Legacy `YYYY-MM-DD` formats are also supported.
* **Columns**:
  - `date`: Month and day in `MM-DD` format (e.g. `03-31`)
  - `album`: Album title (e.g. `"A Living Room Hush"`)
  - `artist`: Artist name (e.g. `"Jaga Jazzist"`)
  - `spotify-app`: Spotify album URI (e.g. `spotify:album:79yZ6f40ABeqdqh1yqRgiS`)
  - `comment`: Review comment or description (optional)
  - `year`: Publication year (optional)
  - `bandcamp`: Bandcamp URL (optional, e.g. `https://jagajazzist.bandcamp.com/album/a-living-room-hush`)

Example:
```csv
date,album,artist,spotify-app,comment,year,bandcamp
03-31,"A Living Room Hush","Jaga Jazzist",spotify:album:79yZ6f40ABeqdqh1yqRgiS,"A modern classic from 2001! Bestest track: Airborne.",2001,https://jagajazzist.bandcamp.com/album/a-living-room-hush
```

## Running the Generator

### With Ruby

#### Installation

```bash
bundle install
```

#### Execute Generator

```bash
bundle exec ruby generate_files.rb
```

### With Docker

Generate site files using Docker:

```bash
DOCKER_BUILDKIT=1 docker build --output out .
```

This compiles the static HTML, RSS, and CSV files into the `./out` directory.

## Future Roadmap

- Tag albums by genre
- Show actual album titles from decades on hover in the stats chart
- Pull missing publication year from Last.fm API automatically
