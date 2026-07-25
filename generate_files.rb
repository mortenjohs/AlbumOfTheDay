require "csv"
require "json"
require 'uri'
require 'open-uri'
require "rss"
require "date"
require "yaml"
require "tilt"
require "fileutils"
require "kramdown"
require "set"

puts Time.now # for the log file...

config_file          = "./config.yml"
config_override_file = "./config_override.yml"

config = YAML.load(File.open(config_file).read)
config = config.merge(YAML.load(File.open(config_override_file).read)) if File.exist?(config_override_file)

# Ensure folders exist
[config['cache'], config['rss_dir'], config['html_dir'], config['csv_dir']].each { |dirname| FileUtils.mkdir_p(dirname) unless File.directory?(dirname) }

base_url = config["songlink_api"] + "?"
config["url_parameters"].each { |k,v| base_url+="#{URI.encode_www_form_component(k)}=#{URI.encode_www_form_component(v)}&" } # leave trailing &!

panelbear = config['panelbear_site'] || ''

def normalize_date_key(raw_date)
  return nil if raw_date.nil? || raw_date.to_s.strip.empty?
  parts = raw_date.to_s.strip.split("-")
  if parts.size == 3
    month = sprintf("%02d", parts[1].to_i)
    day   = sprintf("%02d", parts[2].to_i)
    "#{month}-#{day}"
  elsif parts.size == 2
    month = sprintf("%02d", parts[0].to_i)
    day   = sprintf("%02d", parts[1].to_i)
    "#{month}-#{day}"
  else
    nil
  end
end

def date_to_filename(date_key)
  parts = date_key.split("-")
  month = sprintf("%02d", parts[0].to_i)
  day   = sprintf("%02d", parts[1].to_i)
  "#{month}/#{day}.html"
end

def format_verbose_date(date_input)
  return "" if date_input.nil? || date_input.to_s.strip.empty?
  day = nil
  month = nil

  if date_input.is_a?(Date) || date_input.is_a?(Time)
    day = date_input.day
    month = date_input.month
  elsif date_input.to_s.include?("-")
    parts = date_input.to_s.split("-")
    if parts.size == 3
      month = parts[1].to_i
      day   = parts[2].to_i
    elsif parts.size == 2
      month = parts[0].to_i
      day   = parts[1].to_i
    end
  end

  return date_input.to_s if day.nil? || month.nil?

  month_names = [
    nil, "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
  ]

  suffix = case day
           when 1, 21, 31 then "st"
           when 2, 22     then "nd"
           when 3, 23     then "rd"
           else                "th"
           end

  "#{day}#{suffix} of #{month_names[month]}"
end

$bandcamp_cache_file = './cache/bandcamp_covers.json'
$bandcamp_cache = File.exist?($bandcamp_cache_file) ? (JSON.parse(File.read($bandcamp_cache_file)) rescue {}) : {}

def get_bandcamp_album_cover(url) 
  return $bandcamp_cache[url] if $bandcamp_cache.key?(url)
  puts url
  cover = nil
  begin
    f = URI.open(url, 'User-Agent' => 'Nooby').read
    if f =~ /\"og:image\" content=\"([^\"]*)\"/
      cover = $1
    end
  rescue StandardError => e
    puts "Error fetching Bandcamp cover: #{e.message}"
  end
  $bandcamp_cache[url] = cover
  File.open($bandcamp_cache_file, "w") { |file| file << JSON.pretty_generate($bandcamp_cache) }
  cover
end

# Build global index of cached JSON files by Spotify ID and date key
$spotify_cache_index = {}
Dir.glob("#{config['cache']}/*.json").each do |filepath|
  next if filepath.include?("bandcamp_covers")
  basename = File.basename(filepath, ".json")
  parsed = JSON.parse(File.read(filepath)) rescue {}
  next if parsed.empty?

  $spotify_cache_index[basename] = parsed

  if parsed["entityUniqueId"]
    sp_id = parsed["entityUniqueId"].split("::").last
    $spotify_cache_index[sp_id] = parsed
  end

  sp_url = parsed.dig("linksByPlatform", "spotify", "url")
  if sp_url
    sp_id = sp_url.split("/").last.split("?").first
    $spotify_cache_index[sp_id] = parsed
  end

  if parsed["entitiesByUniqueId"]
    parsed["entitiesByUniqueId"].each do |k, v|
      if k.start_with?("SPOTIFY_ALBUM::")
        sp_id = k.split("::").last
        $spotify_cache_index[sp_id] = parsed
      end
    end
  end
end

def attach_providers_data(album, data)
  album["providers"] ||= {}

  # special case for bandcamp
  album["providers"]["bandcamp"] = album["bandcamp"] unless album["bandcamp"].nil? || album["bandcamp"].to_s.strip.empty?

  unless data.nil? || data["entitiesByUniqueId"].nil?
    ## thumbnail
    album["thumbnail"] = data["entitiesByUniqueId"][data["entityUniqueId"]]["thumbnailUrl"] rescue nil
    ## find links
    if data["linksByPlatform"]
      data["linksByPlatform"].each do |k,v| 
        album["providers"][k] = v["url"]
      end
    end
  end

  # If we can't get the default thumbnail, use bandcamp cover if possible.
  if (album["thumbnail"].nil? || album["thumbnail"].to_s.strip.empty?) && album["bandcamp"] && !album["bandcamp"].to_s.strip.empty?
    album["thumbnail"] = get_bandcamp_album_cover(album["bandcamp"])
  end

  album["thumbnail"] ||= ""
  return album
end

def get_songlink_info(album, base_url, cache='./cache/')
  spotify_id = album['spotify-app'].to_s.split(":")[-1]
  data = {}

  if spotify_id && !spotify_id.strip.empty? && $spotify_cache_index[spotify_id]
    data = $spotify_cache_index[spotify_id]
  elsif album['date'] && $spotify_cache_index[album['date']]
    data = $spotify_cache_index[album['date']]
  end

  if data.empty? && spotify_id && !spotify_id.strip.empty?
    file_name = "#{cache}/spotify_#{spotify_id}.json"
    if File.exist?(file_name)
      data = JSON.parse(File.read(file_name)) rescue {}
    end
  end

  if data.empty? && spotify_id && !spotify_id.strip.empty?
    puts "Downloading: #{album['artist']} - #{album['album']}"
    url = base_url + "url=#{album['spotify-app']}"
    begin
      URI.open(url, 'User-Agent' => 'Nooby') do |f|
        data = JSON.parse(f.read)
        save_file = "#{cache}/spotify_#{spotify_id}.json"
        File.open(save_file, "w") {|file| file << JSON.pretty_generate(data) }      
        $spotify_cache_index[spotify_id] = data
      end
    rescue OpenURI::HTTPError => e
      puts "HTTP Error fetching songlink info for #{album['artist']} - #{album['album']}: #{e.message}"
    rescue StandardError => e
      puts "Error fetching songlink info: #{e.message}"
    end
  end

  data
end

all_albums = {}

# 1. Load curated albums from album_of_the_day.csv
CSV.read(config["csv_file"], :headers => true).each do |row|
  album = row.to_h
  date_key = normalize_date_key(album["date"])
  next if date_key.nil?
  album["date"] = date_key
  
  data = {}
  unless album['spotify-app'].nil? || album['spotify-app'].empty?
    data = get_songlink_info(album, base_url, config['cache'])
  end
  album = attach_providers_data(album, data)
  album['providers']['aotd'] = config['url'].chomp('/') + "/" + date_to_filename(date_key)

  all_albums[date_key] = album
end

# 2. Load backup random albums from random_album_of_the_day.csv
backup_albums = []
CSV.read(config["backup_csv_file"], :headers => true).each do |row|
  album = row.to_h
  date_key = normalize_date_key(album["date"])
  album["date"] = date_key if date_key
  backup_albums << album
end

# 3. Build 366-day calendar cycle (Jan 1 to Dec 31)
leap_year = Date.today.leap?
calendar_dates = []
(Date.new(2024, 1, 1)..Date.new(2024, 12, 31)).each do |d|
  calendar_dates << sprintf("%02d-%02d", d.month, d.day)
end

# Track used albums to ensure 100% uniqueness (no duplicates)
used_albums = Set.new
all_albums.each do |date, album|
  key = "#{album['artist'].to_s.strip.downcase} - #{album['album'].to_s.strip.downcase}"
  used_albums << key
end

# Filter backup albums to exclude any already in curated list
unused_backup_albums = backup_albums.reject do |b|
  key = "#{b['artist'].to_s.strip.downcase} - #{b['album'].to_s.strip.downcase}"
  used_albums.include?(key)
end

backup_index = 0
calendar_dates.each do |date_key|
  if date_key == "02-29" && !leap_year
    next # Skip Feb 29 on non-leap years
  end

  if all_albums[date_key].nil?
    # Use unused backup album first, then cycle backup albums so all dates are covered
    if backup_index < unused_backup_albums.size
      album = unused_backup_albums[backup_index].clone
    else
      album = backup_albums[backup_index % backup_albums.size].clone
    end
    backup_index += 1

    album["date"] = date_key
    album['comment'] = album['comment'].to_s.empty? ? "Random album suggestion" : album['comment']
    album['ai-generated'] = true
    data = {}
    unless album['spotify-app'].nil? || album['spotify-app'].empty?
      data = get_songlink_info(album, base_url, config['cache'])
    end
    album = attach_providers_data(album, data)
    album['providers']['aotd'] = config['url'].chomp('/') + "/" + date_to_filename(date_key)
    all_albums[date_key] = album

    key = "#{album['artist'].to_s.strip.downcase} - #{album['album'].to_s.strip.downcase}"
    used_albums << key
  end
end

# 4. Compute Previous and Next day navigation links
active_dates = calendar_dates.select { |d| all_albums.key?(d) }
total_active = active_dates.size

active_dates.each_with_index do |date_key, idx|
  prev_key = active_dates[(idx - 1) % total_active]
  next_key = active_dates[(idx + 1) % total_active]
  
  if all_albums[date_key]
    all_albums[date_key]['prev_url'] = date_to_filename(prev_key)
    all_albums[date_key]['next_url'] = date_to_filename(next_key)
  end
end

# 5. Extract available providers
providers = []
all_albums.each { |date, album| providers << album["providers"].keys if album["providers"]; providers = providers.flatten.uniq }

# 6. Generate RSS Feeds (rolling 30-day window)
def rss_generator(provider, all_albums, author, base_url)
  RSS::Maker.make("atom") do |maker|
    maker.channel.author = author
    maker.channel.updated = Time.now.to_s
    maker.channel.about = "#{base_url}/#{provider}.xml"
    maker.channel.title = "Album of the day on #{provider}"
    
    # Rolling 30 days
    (0..30).reverse_each do |days_ago|
      d = Date.today - days_ago
      date_key = sprintf("%02d-%02d", d.month, d.day)
      album = all_albums[date_key]
      next if album.nil? || album["providers"][provider].nil?
      
      maker.items.new_item do |item|
        item.link = album["providers"][provider]
        if album['year'].nil? || album['year'].to_s.empty?
          item.title = "#{d.to_s}: #{album['artist']} -- #{album['album']}"
        else
          item.title = "#{d.to_s}: #{album['artist']} -- #{album['album']} (#{album['year']})"
        end
        item.updated = d.to_s
        item.description = "#{album['comment']}"
      end
    end
  end
end

def csv_generator(provider, all_albums, out_dir)
  headers = ['date', 'link', 'album','artist', 'year', 'description']
  CSV.open(out_dir + provider + '.csv', "w", :headers => headers) do |csv_file|
    csv_file << headers
    (0..30).reverse_each do |days_ago|
      d = Date.today - days_ago
      date_key = sprintf("%02d-%02d", d.month, d.day)
      album = all_albums[date_key]
      next if album.nil? || album["providers"][provider].nil?

      row = {}
      row['date'] = d.to_s
      row['link'] = album["providers"][provider]
      row['album'] = album['album']
      row['artist'] = album['artist']
      row['year'] = album['year']
      row['description'] = "#{album['comment']}"
      csv_file << row
    end
  end
end

unless config["rss"].nil? || config["rss"]["author"].nil? || config['rss']['base_url'].nil?
  providers.each do |p| 
    File.open("#{config["rss_dir"]}/#{p}.xml", "w") do |f|
      f << rss_generator(p, all_albums, config["rss"]["author"], config['rss']['base_url'])
    end
  end
  puts "Providers' RSS feeds generated: #{providers.sort.join(', ')}"
end

unless config['csv_dir'].nil?
  providers.each do |p|
    csv_generator(p, all_albums, config['csv_dir'])
  end
  puts "Providers' CSV files generated: #{providers.sort.join(', ')}"
end

# 7. Generate static HTML pages (clean old month pages first)
album_template = Tilt.new('views/album.erb')
(1..12).each do |m|
  m_str = sprintf("%02d", m)
  Dir.glob("#{config['html_dir']}/#{m}/*.html").each { |f| File.delete(f) rescue nil }
  Dir.glob("#{config['html_dir']}/#{m_str}/*.html").each { |f| File.delete(f) rescue nil }
end
all_albums.each do |date_key, album|
  filename = "#{config['html_dir']}/#{date_to_filename(date_key)}"
  dirname = File.dirname(filename)
  FileUtils.mkdir_p(dirname) unless File.directory?(dirname)
  File.open(filename, "w") do |file|
    file << album_template.render(self, :album => album, :providers => providers, :panelbear => panelbear)
  end
end

# 8. Generate index.html redirect to today's month/day
File.open("#{config['html_dir']}/index.html", "w") do |file|
  file << Tilt.new('views/index.erb').render(self, :today => Date.today)
end

# 9. Generate stats
module Enumerable
  def count_by &block
    Hash[ self.group_by { |e| yield e }.map { |key, list| [key, list.length] } ]
  end
end

stats = {}
stats[:years] = all_albums.values.map {|a| a["year"]}.reject { |y| y.nil? || y.to_s.empty? }.map { |a| a.to_s[0,3] }.count_by { |a| a }.sort
stats[:years].reject! { |v| v[0] == "" }
puts stats 

File.open("#{config['html_dir']}/stats.html", "w") do |file|
  file << Tilt.new('views/stats.erb').render(self, :stats => stats, :panelbear => panelbear)
end

# 10. Generate curated list
File.open("#{config['html_dir']}/curated.html", "w") do |file|
  file << Tilt.new('views/curated.erb').render(self, :albums => all_albums.select { |date, album| !album["ai-generated"] }, :panelbear => panelbear)
end

# 11. Generate random.html redirect to a random date in the year
active_date_urls = active_dates.map { |d| date_to_filename(d) }
File.open("#{config['html_dir']}/random.html", "w") do |file|
  file << Tilt.new('views/random.erb').render(self, :active_urls => active_date_urls)
end
