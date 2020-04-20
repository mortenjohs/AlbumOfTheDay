require "csv"
require "json"
require 'uri'
require 'open-uri'
require "rss"
require "date"
require "yaml"
require "tilt"
require "fileutils"

puts Time.now # for the log file...


config_file   = "./config.yml"
config_override_file = "./config_override.yml"

config = YAML.load(File.open(config_file).read)
config = config.merge(YAML.load(File.open(config_override_file).read)) if File.exist?(config_override_file)

FUTURE = config['generate_future'] || false
# puts config

# make sure folders exist:
[config['cache'], config['rss_dir'], config['html_dir']].each { |dirname| FileUtils.mkdir_p(dirname) unless File.directory?(dirname) }

base_url = config["songlink_api"] + "?"
config["url_parameters"].each { |k,v| base_url+="#{URI::encode(k)}=#{URI::encode(v)}&" } # leave trailing &!

all_albums = {}

def get_bandcamp_album_cover(url) 
  f = open(url).read
  f=~/\"og:image\" content=\"(.*)">/
  $1
end

def attach_providers_data(album, data)
  album["providers"] = {}

  # special case for bandcamp
  album["providers"]["bandcamp"] = album["bandcamp"] unless album["bandcamp"].nil?

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
  spotify_id = album['spotify-app'].split(":")[-1]
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
  album["date_obj"]  = Date.strptime(album["date"])
  date = {}
  unless album['spotify-app'].nil?
    data = get_songlink_info(album, base_url, config['cache'])
  end
  all_albums[album["date"]] = attach_providers_data(album, data)
end

rss_generators = {}

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
            item.title = "#{date}: #{album['artist']} -- #{album['album']}"
            item.updated = date
            item.description = "#{album['comment']}"
          end
        end
      end
    end
  end
  rss
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
  url += URI::encode("\"#{artist}\"-\"#{album}\"")
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
  url = "#{base_url}?method=artist.getsimilar&artist=#{artist}&api_key=#{api_key}&format=json&limit=#{limit}"
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

providers  = []
all_albums.each {|date, album| providers<<album["providers"].keys;providers = providers.flatten.uniq }

first_date = Date.strptime(all_albums.keys.sort.first)

# If we have necessary info, generate RSS feeds...
unless config["rss"].nil? || config["rss"]["author"].nil? || config['rss']['base_url'].nil?
  providers.each do |p| 
    File.open("#{config["rss_dir"]}/#{p}.xml", "w") do |f|
      f << rss_generator(p, all_albums, config["rss"]["author"], config['rss']['base_url'] )
    end
  end
  puts "Providers' RSS feeds generated: #{providers.sort.join(', ')}"
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

## Generate random page
unless config['lastfm'].nil? || config['lastfm']['api_key'].nil?
  artist = all_albums.values.map { |e| e['artist']}.sample
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