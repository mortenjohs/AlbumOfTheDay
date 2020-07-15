# Album of the Day

## Input

### Config file 

* Format: YAML file
* File name: config.yml
* Elements:
    - cache: The directory to cache the jsons from the api
    - rss_dir: Output dir for RSS feeds
    - html_dir: Output dir for HTML files
    - csv_file: Input CSV file
    - backup_csv_file: A CSV file for fallback albums -- will be populated by the random album generator
    - songlink_api: URL for the API
    - url_parameters: List of default parameters that is used for the API lookup (ie userCountry, key, etc.)
    - rss (optional (no RSS feeds are generted if these are missing...))
        - author: author of RSS feed.
        - base_url: URL for the resulting rss feed. Provider and .xml will be added.

Example:

```YAML
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
  author: "someone"
  base_url: "https://somewhere.org/aotd/rss/"
lastfm:
  api_key: "API_KEY"
  base_url: "http://ws.audioscrobbler.com/2.0/"
```

You can also add elements to a file called 'config_override.yml' that will be merged into this config at runtime.

### CSV file

* Format: Comma separated file (CSV)
* Default file name: album_of_the_day.csv
* Columns:
    - date (YYYY-MM-DD, ie 2020-03-31)
    - album (ie "A Living Room Hush")
    - artist (ie "Jaga Jazzist")
    - spotify-app (ie: spotify:album:79yZ6f40ABeqdqh1yqRgiS) 
    - comment (optional, ie "A modern classic from 2001! Bestest track: Airborne.")
    - year (of publication)
    - bandcamp (optional, ie https://jagajazzist.bandcamp.com/album/a-living-room-hush)

Example: 
```csv 
date,album,artist,spotify-app,comment,year,bandcamp
2020-03-31,"A Living Room Hush","Jaga Jazzist",spotify:album:79yZ6f40ABeqdqh1yqRgiS,"A modern classic from 2001! Bestest track: Airborne.",2001,https://jagajazzist.bandcamp.com/album/a-living-room-hush
```

## Ideas

- Tag by genre?

## TODO

- Make cache id based istead of date based...
- Make stats page show actual album names from the various decades on hover...
- Pull album year from last.fm API if missing

