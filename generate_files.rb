# generate_jsons

require "csv"
require "json"
require 'uri'
require 'open-uri'
require "rss"
require "date"
require "yaml"
require "tilt"
require "fileutils"

puts Time.now

cache    = "./cache"
rss_dir  = "./public/rss"
csv_file = "./album_of_the_day.csv"
config   = "./config.yml"

# https://api.song.link/v1-alpha.1/links?url=spotify%3Aalbum%3A5OZHQ7KG8k04IOkF50fACO&userCountry=FR
songlink_api = "https://api.song.link/v1-alpha.1/links"

config = {
  "userCountry" => "FR"
}

base_url = songlink_api + "?"

config.each { |k,v| base_url+="#{URI::encode(k)}=#{URI::encode(v)}&" } 

all_albums = {}

CSV.read(csv_file, :headers => true).each do |row|
  album = row.to_h
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
    # puts url
    open(url) do |f|
      data = JSON.parse(f.read)
      File.open(file_name, "w") {|file| file << JSON.pretty_generate(data) }      
    end
  end
  ## thumbnail
  album["thumbnail"] = data["entitiesByUniqueId"][data["entityUniqueId"]]["thumbnailUrl"]
  ## date
  album["date_obj"]  = Date.strptime(album["date"])
  ## find links
  album["providers"] = {}
  unless album["bandcamp"].nil?
    album["providers"]["bandcamp"]=album["bandcamp"]
  end
  data["linksByPlatform"].each do |k,v| 
      album["providers"][k]=v["url"]
  end
  all_albums[album["date"]] = album
end

rss_generators = {}

def rss_generator(provider, data)
  rss = RSS::Maker.make("atom") do |maker|
    maker.channel.author = "mortenjohs"
    maker.channel.updated = Time.now.to_s
    maker.channel.about = "https://ervik.hopto.org/aotd/rss/#{provider}.xml"
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

providers  = []
all_albums.each {|date, album| providers<<album["providers"].keys;providers = providers.flatten.uniq }

first_date = Date.strptime(all_albums.keys.sort.first)

providers.each do |p| 
  File.open("#{rss_dir}/#{p}.xml", "w") do |f|
    f << rss_generator(p, all_albums)
  end
end

puts "Providers generated: #{providers.sort.join(', ')}"

album_template = Tilt.new('views/album.erb')
all_albums.each do |date, album| 
  date_obj = album["date_obj"]
  if Date.today >= date_obj
    filename = "#{config['html_dir']}/#{date_obj.year}/#{date_obj.month}/#{date_obj.day}.html"
    dirname = File.dirname(filename)
    unless File.directory?(dirname)
      FileUtils.mkdir_p(dirname)
    end
    File.open(filename, "w") do |file|
      file << album_template.render(self, :album => album, :first_date => first_date, :providers => providers )
    end
  end
end

File.open("#{config['html_dir']}/index.html", "w") do |file|
  file << Tilt.new('views/index.erb').render(self, :today => Date.today)
end
