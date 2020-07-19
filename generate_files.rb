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

puts Time.now # for the log file...

config_file   = "./config.yml"
config_override_file = "./config_override.yml"

config = YAML.load(File.open(config_file).read)
config = config.merge(YAML.load(File.open(config_override_file).read)) if File.exist?(config_override_file)

FUTURE = config['generate_future'] || false
# puts config

# make sure folders exist:
[config['cache'], config['rss_dir'], config['html_dir'], config['csv_dir']].each { |dirname| FileUtils.mkdir_p(dirname) unless File.directory?(dirname) }

base_url = config["songlink_api"] + "?"
config["url_parameters"].each { |k,v| base_url+="#{URI.encode_www_form_component(k)}=#{URI.encode_www_form_component(v)}&" } # leave trailing &!

all_albums = {}

def get_bandcamp_album_cover(url) 
  # TODO add cache?
  f = open(url).read
  f=~/\"og:image\" content=\"(.*)">/
  $1
end

def attach_providers_data(album, data)
  album["providers"] = {}

  # special case for bandcamp
  album["providers"]["bandcamp"] = album["bandcamp"] unless album["bandcamp"].nil? || album["bandcamp"].strip.empty?

  unless data.nil? || data["entitiesByUniqueId"].nil?
    ## thumbnail
    album["thumbnail"] = data["entitiesByUniqueId"][data["entityUniqueId"]]["thumbnailUrl"]     
    ## find links
    data["linksByPlatform"].each do |k,v| 
      album["providers"][k]=v["url"]
    end
  end

  # If we can't get the default thumbnail, use bandcamp, if possible.
  album["thumbnail"] = get_bandcamp_album_cover(album["bandcamp"]) if !album["bandcamp"].nil? && album["thumbnail"].nil?
  
  return album
end

def get_songlink_info(album, base_url, cache='./cache/')
  # spotify_id = album['spotify-app'].split(":")[-1]
  # file_name = "#{cache}/#{album['date']}.json"
  file_name = "#{cache}/#{album['date']}.json"
  data = {}
  if File.exist?(file_name)
    data = JSON.parse(File.open(file_name).read)
    # check that the spotify UUID hasn't changed -- and clear if so
    data = {} if data["entityUniqueId"].split("::")[-1]!=album['spotify-app'].split(":")[-1]
  end
  if data.empty?
    puts "Downloading: #{album['artist']} - #{album['album']}"
    url = base_url + "url=#{album['spotify-app']}"
    open(url) do |f|
      data = JSON.parse(f.read)
      File.open(file_name, "w") {|file| file << JSON.pretty_generate(data) }      
    end
  end
  data
end

CSV.read(config["csv_file"], :headers => true).each do |row|
  album = row.to_h
  ## date
  album["date_obj"] = Date.strptime(album["date"])
  data = {}
  unless album['spotify-app'].nil?
    data = get_songlink_info(album, base_url, config['cache'])
  end
  all_albums[album["date"]] = attach_providers_data(album, data)
end

CSV.read(config["backup_csv_file"], :headers => true).each do |row|
  album = row.to_h
  ## date
  if all_albums[album["date"]].nil?
    album["date_obj"] = Date.strptime(album["date"])
    data = {}
    unless album['spotify-app'].nil?
      data = get_songlink_info(album, base_url, config['cache'])
    end
    all_albums[album["date"]] = attach_providers_data(album, data)
  end
end

def rss_generator(provider, data, author, base_url)
  rss = RSS::Maker.make("atom") do |maker|
    maker.channel.author = author
    maker.channel.updated = Time.now.to_s
    maker.channel.about = "#{base_url}/#{provider}.xml"
    maker.channel.title = "Album of the day on #{provider}"
    data.each do |date, album| 
      if Date.today >= album["date_obj"]
        unless album["providers"][provider].nil?
          maker.items.new_item do |item|
            item.link = album["providers"][provider]
            item.title = "#{album['date']}: #{album['artist']} -- #{album['album']} (#{album['year']})"
            item.updated = date
            item.description = "#{album['comment']}"
          end
        end
      end
    end
  end
  rss
end

def csv_generator(provider, data, out_dir)
  headers = ['date', 'link', 'album','artist', 'year', 'description']
  CSV.open(out_dir+provider+'.csv', "w", :headers => headers ) do |csv_file|
    csv_file << headers
    data.each do |date, album| 
      row = {}
      if Date.today >= album["date_obj"]
        unless album["providers"][provider].nil?
          row['date'] = album['date']
          row['link'] = album["providers"][provider]
          row['album'] = album['album']
          row['artist'] = album['artist']
          row['year'] = album['year']
          row['description'] = "#{album['comment']}"
          csv_file << row
        end
      end
    end
  end
end

def get_album_by_provider_ref(ref, base_url = "https://api.song.link/v1-alpha.1/links?", cache = './cache')
  # override cache with cache = nil
  url = base_url + "url=#{ref}"
  data = {}
  open(url) do |f|
    data = JSON.parse(f.read)      
  end
  data
end

def get_songlink_album(artist, album)
  # use itunes to find an url -- first 
  url = "https://itunes.apple.com/search?entity=album&term="
  url += URI.encode_www_form_component("\"#{artist}\"-\"#{album}\"")
  album = {}
  open(url) do |f| 
    data = JSON.parse(f.read) 
    if data['resultCount'] > 0
      itunes_url = data['results'].first['collectionViewUrl']
      album = get_album_by_provider_ref(itunes_url)
    end
  end
  album
end

def get_similar_artists_by_name_lastfm(artist,api_key,limit=10,base_url="http://ws.audioscrobbler.com/2.0/")
  url = "#{base_url}?method=artist.getsimilar&artist=#{URI.escape(artist)}&api_key=#{api_key}&format=json&limit=#{limit}"
  data = {}
  open(url) do |f|
    data = JSON.parse(f.read)
  end
  data['similarartists']['artist']
end

def get_albums_from_artist_by_mbid_lastfm(mbid,api_key,limit=10,base_url="http://ws.audioscrobbler.com/2.0/")
  url = "#{base_url}?method=artist.getTopAlbums&mbid=#{mbid}&api_key=#{api_key}&format=json&limit=#{limit}"
  data = {}
  open(url) { |f| data = JSON.parse(f.read) }
  data['topalbums']['album']
end

def get_random_album_from_similar_artist(artist, api_key)
  artist      = get_similar_artists_by_name_lastfm(artist,api_key).sample
  mbid        = artist['mbid']
  album       = get_albums_from_artist_by_mbid_lastfm(mbid,api_key).sample
  get_songlink_album(artist['name'], album['name']) 
end

def append_csv(csv_filename, hashed_row, default_headers = ["date","album","artist","spotify-app","comment","year","bandcamp"])
  CSV.open(csv_filename, 'a+', headers: true) do |csv|
    row = []
    headers = csv.read.headers
    if headers.empty?
      headers = default_headers
    end
    headers.each do |column|
      row << hashed_row[column] || ''
    end
    csv << row
  end
end

# Filter albums by date
all_albums.select! { |date, album| (!album["date_obj"].nil?) && ((Date.today >= album["date_obj"]) || FUTURE )}
all_albums = (all_albums.sort_by {|date, album| album["date_obj"] }).to_h

if Date.today>all_albums.values.last['date_obj']
  # We miss entries in csv -- let's autogenerate...
  unless config['lastfm'].nil? || config['lastfm']['api_key'].nil?
    artist = all_albums.select{|k,v| Date.today >= v["date_obj"]}.values.map { |e| e['artist']}.sample
    puts artist
    data = {}
    tries = 0
    threshold = 15
    while tries < threshold && data.empty?
      begin
        data = get_random_album_from_similar_artist(artist, config['lastfm']['api_key'])
        if data["linksByPlatform"]['spotify'].nil?
          data = {}
        end
      rescue OpenURI::HTTPError => e
        puts e
      rescue NoMethodError => e
        ## This captures null pointer errors in the random album generator chain...
        puts e
      end
      tries += 1
    end
    unless data.empty?
      album = {}
      album['date_obj'] = all_albums.values.last['date_obj'].next
      album['date']     = album['date_obj'].to_s
      album['artist']   = data["entitiesByUniqueId"][data["entityUniqueId"]]["artistName"]
      album['album']    = data["entitiesByUniqueId"][data["entityUniqueId"]]["title"]
      album['year']     = '' ## placeholder!
      album['bandcamp'] = ''
      album['comment']  = "Random suggestion similar to: #{artist}."
      album = attach_providers_data(album, data)
      album['spotify-app'] = album['providers']['spotify'].nil? ? '' : 'spotify:album:'+album['providers']['spotify'].split('/').last
      append_csv(config["backup_csv_file"], album)
      all_albums[album['date']] = album
    end
  end
end

providers  = []
all_albums.each {|date, album| providers<<album["providers"].keys;providers = providers.flatten.uniq }
first_date = all_albums.values.first['date_obj']

# If we have necessary info, generate RSS feeds...
unless config["rss"].nil? || config["rss"]["author"].nil? || config['rss']['base_url'].nil?
  providers.each do |p| 
    File.open("#{config["rss_dir"]}/#{p}.xml", "w") do |f|
      f << rss_generator(p, all_albums, config["rss"]["author"], config['rss']['base_url'] )
    end
  end
  puts "Providers' RSS feeds generated: #{providers.sort.join(', ')}"
end

# Generate csv files
unless config['csv_dir'].nil?
  providers.each do |p|
    csv_generator(p, all_albums, config['csv_dir'])
  end
  puts "Providers' CSV files generated: #{providers.sort.join(', ')}"
end

# Generate static htmls
album_template = Tilt.new('views/album.erb')
all_albums.each do |date, album| 
  date_obj = album["date_obj"]
  if Date.today >= date_obj || FUTURE
    filename = "#{config['html_dir']}/#{date_obj.year}/#{date_obj.month}/#{date_obj.day}.html"
    dirname = File.dirname(filename)
    FileUtils.mkdir_p(dirname) unless File.directory?(dirname)
    File.open(filename, "w") do |file|
      file << album_template.render(self, :album => album, :first_date => first_date, :providers => providers )
    end
  end
end

## Generate index redirect.
File.open("#{config['html_dir']}/index.html", "w") do |file|
  file << Tilt.new('views/index.erb').render(self, :today => Date.today)
end

## Generate stats

# https://gist.github.com/mortenjohs/4228838
module Enumerable
  def count_by &block
    Hash[ self.group_by { |e| yield e }.map { |key, list| [key, list.length] } ]
  end
end

stats = {}
stats[:years] = all_albums.select{|k,v| Date.today >= v["date_obj"]}.values.map {|a| a["year"]}.count_by { |a| a.to_s[0,3] }.sort
stats.delete("")
puts stats 

# Generate stats.html
File.open("#{config['html_dir']}/stats.html", "w") do |file|
  file << Tilt.new('views/stats.erb').render(self, :stats => stats)
end

## Generate random page
unless config['lastfm'].nil? || config['lastfm']['api_key'].nil?
  artist = all_albums.select{|k,v| Date.today >= v["date_obj"]}.values.map { |e| e['artist']}.sample
  data = {}
  tries = 0
  threshold = 5
  while tries < threshold && data.empty?
    begin
      data = get_random_album_from_similar_artist(artist, config['lastfm']['api_key']) 
    rescue OpenURI::HTTPError => e
      puts e
    rescue NoMethodError => e
      ## This captures null pointer errors in the random album generator chain...
      puts e
    end
    tries += 1
  end
  unless data.empty?
    album = {}
    album['date_obj'] = Date.today
    album['artist']   = data["entitiesByUniqueId"][data["entityUniqueId"]]["artistName"]
    album['album']    = data["entitiesByUniqueId"][data["entityUniqueId"]]["title"]
    album['date']     = Date.today.to_s
    album['random']   = true
    album['comment']  = "Random suggestion similar to: #{artist}."
    album = attach_providers_data(album, data)
    File.open("#{config['html_dir']}/random.html", "w") do |file|
      file << album_template.render(self, :album => album, :first_date => first_date, :providers => providers )
      puts "Random album: #{data["entitiesByUniqueId"][data["entityUniqueId"]]["artistName"]} - #{data["entitiesByUniqueId"][data["entityUniqueId"]]["title"]} (Based on #{artist}.)"
    end
  end
end
