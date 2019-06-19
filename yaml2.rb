# encoding: utf-8

### FLICKR API environment variables in ~/.profile
### Scripts that fetches photosets using Flickr API and download photos
### in photosets to assets/photos
### Files used: 
### - photosets.txt - list of photosets, order is important
### Files created:
### - _data/photos.yml - YAML serialized data fetched from Flickr API
### - assets/photos/photosetid_photoid_size.jpg
### - _photos/photosetid.md - created pages using previously fetched data

require 'fileutils'
require_relative 'flickraw-cached'
require 'yaml'
require 'date'
require 'open-uri'

FlickRaw.api_key       = ENV['FLICKR_API_KEY']
FlickRaw.shared_secret = ENV['FLICKR_API_SECRET']
flickr.access_token    = ENV['FLICKR_ACCESS_TOKEN']
flickr.access_secret   = ENV['FLICKR_ACCESS_SECRET']
user_id = ENV["FLICKR_USER"]

String.class_eval do
  def to_slug
    value = self
    value = value.gsub(/[']+/, '')
    value = value.gsub(/\W+/, ' ')
    value = value.strip
    value = value.downcase
    value = value.gsub(' ', '-')
    value
  end
end

class FlickrPhoto
	attr_accessor :id, :title, :description, :src, :page_url, :date_posted, :date_taken, :date_updated, :sizes
	def initialize(photo, pathalias:)
		id = photo.id.to_i
		@title = photo.title.strip
		@description = photo.description.to_s.strip
		#size = "_#{size}" if not size.empty?
		@page_url = "https://www.flickr.com/photos/#{pathalias}/#{id}/"
		@date_posted = photo.dateupload.to_i
		date_taken_raw = photo.datetaken
		@date_taken = DateTime.strptime(date_taken_raw, "%Y-%m-%d %H:%M:%S").strftime('%s').to_i
		@date_updated = photo.lastupdate.to_i
		@sizes = getsizes(photo)
		@max_photo = max_photo(2048)
	end

	def ==(other)
		self.class === other and
		 other.state == state
	end
	
	def state
    [@title, @description, @page_url, @date_posted, @date_updated, @date_taken]
	end
	
	def getsizes(p)
		# p is photo
		# mapping for extra parameters
		#	url_sq, url_q, url_t, url_s, url_n, url_m, url_z, url_c,url_l url_h, url_k, url_o 
      sizes_map = {}
		  sizes_map['Square'] = 'sq'
			sizes_map['Large Square'] = 'q'
			sizes_map['Thumbnail'] = 't'
			sizes_map['Small'] = 's'
			sizes_map['Small 320'] = 'n'
			sizes_map['Medium'] = 'm'
			sizes_map['Medium 640'] = 'z'
			sizes_map['Medium 800'] =  'c'
			sizes_map['Large'] = 'l'
			sizes_map['Large 1600'] = 'h'
			sizes_map['Large 2048'] = 'k'
			sizes_map['Original'] = 'o'

			sizes = {}
			sizes_map.each do |key, v|
				# method send allows to run call method in different way
				# ex. p.width_sq == p.send("width_sq")
				sizes[key] = { 
				'width' => p.send("width_#{v}").to_i, 
				'height' => p.send("height_#{v}").to_i, 
				'source' => p.send("url_#{v}")
			  } if p.respond_to?("url_#{v}") 
			end
			return sizes
	end

	def max_photo(photo_size)
		max_p = 75
		max_label = 'Square'
		@sizes.each do |label,v|
			tmp = [v['width'],v['height']].max
			if (tmp <= photo_size) && (tmp > max_p)
				max_p = tmp
				max_label = label
			end
		end
		return @sizes[max_label]

	end

end

def download_photo(url, filename)
	### download a photo
	unless File.file?(filename)
		open(url) {|f|
			File.open(filename,"wb") do |file|
				file.puts f.read
			end
		}
	end
end

class FlickrSet
	@@order = 0
	attr_accessor :order, :title, :description, :page_url, :date_created, :date_updated, :photos, :primaryphoto, :pathalias
		def initialize(user_id, set_id, pathalias:)
		@@order += 1
		@order = @@order
		info = flickr.photosets.getInfo(:photoset_id => set_id)
		# ?shortcut, to not repeat info['id'] ? could be @id ?
		# id = info['id']
		@title = info['title'].strip
		@description = info['description'].strip
		@page_url = "https://www.flickr.com/photos/#{pathalias}/sets/#{set_id}"
		@date_created = info['date_create'].to_i
    @date_updated = info['date_update'].to_i
		getPhotos = get_photos(user_id, set_id)
		@photos = {}
		getPhotos.photo.each do |photo|
			@photos[photo.id.to_i] = FlickrPhoto.new(photo, pathalias: pathalias)
			download_photo_allsizes(photo.id.to_i, set_id)
		end
		@primaryphoto = @photos[info['primary'].to_i]

	end

	def get_photos(user_id, set_id)
		# extra queries to api
    # a lot of available extras  are not documented in official api
		extras = "last_update, date_upload, date_taken, description, url_sq, url_q, url_t, url_s, url_n, url_m, url_z, url_c, url_l, url_h, url_k, url_o"
		return flickr.photosets.getPhotos(:user_id => user_id,:photoset_id => set_id, :extras => extras)
	end

	def download_photo_allsizes(photo_id, set_id)
		path = "/assets/photos/"
		@photos[photo_id].sizes.each do |sid, size|
				url = size['source']
			filename =  "#{path}#{set_id}_#{photo_id.to_s}_#{sid.to_slug}.jpg"
			size['local-source'] = filename
			# filename[1..-1] need to trim / in path, otherwise wants to save to / root
			download_photo(url,filename[1..-1])
		end
	end

	def ==(other)
		self.class === other and
		 other.state == state
	end
	
	def state
    [@title, @description, @page_url, @date_created, @date_updated, @primaryphoto, @order]
  end
end

class FlickrGallery
	attr_accessor :page_url, :photosets, :user_id, :sorted_photos
	def initialize(user_id, *argsets)
		puts "Read photosets: " + argsets.to_s
		userinfo = flickr.people.getInfo(:user_id => user_id)
		@pathalias = userinfo.path_alias
		@user_id = user_id
		@page_url = "https://www.flickr.com/photos/#{@pathalias}/sets/"
		@photosets = {}
		open_photosets(*argsets)
		m_photos = {}
		@photosets.each do |k, v|
			m_photos.merge!(v.photos)
		end
		@sorted_photos = sort_photos()

	end

	def ==(other)
		self.class === other and
		 other.state == state
	end
	
	def state
		[@user_id, @page_url, @photosets]
	end

	def open_photosets(*argsets)
		argsets.each { |set| @photosets[set.to_i] = FlickrSet.new(user_id, set, pathalias: @pathalias) }
	end

	def sort_photos
		merge_photos = {}
		@photosets.each do |k, v|
			merge_photos.merge!(v.photos)
		end
		sorted_photos = merge_photos.sort_by{ |k, v| v.date_posted }.reverse!
		sorted_photos = sorted_photos.to_h
	end

	def gen_collection(path)
		#first remove all files in path
		FileUtils.rm_f Dir.glob("#{path}/*")
		@photosets.each do |key, photoset|
			slug = photoset.title.to_slug
			open("#{path}#{key}.md", 'w') { |f|
				f << "---\n"
#				f << "layout: photo_set\n"
				f << "page_url: #{photoset.page_url}\n"
				f << "set_id: #{key}\n"
				f << "title: '#{photoset.title}'\n"
				f << "slug: '#{slug}'\n"
				f << "description: '#{photoset.description}'\n"
				f << "date_created: #{photoset.date_created}\n"
				f << "order: #{photoset.order}\n"
#				f << "permalink: /photos/#{slug}/\n"
				f << "---\n"

			}
		end
	end

	def write_yaml(file)
		File.open(file, "w")  {|f| f.write(self.to_yaml) }
	end
end

class Sync
	def initialize(user_id, photosets_file, yaml_file)
		@photosets_file = photosets_file
		@yaml_file = yaml_file
		@collection_folder = "_photos/"
		@photosets_array = read_photosets(photosets_file)
		@gallery_local = read_local_gallery(yaml_file)
		@gallery_internet = FlickrGallery.new(user_id, *@photosets_array)
		if equal_galleries?(@gallery_local, @gallery_internet)
			puts 'Everything is synced'
		else
			if equal_photosets_arrays?(@gallery_internet.photosets.keys, @photosets_array)
				@gallery_internet.write_yaml(@yaml_file)
				@gallery_internet.gen_collection(@collection_folder)
			else
				puts "Gallery internet is not equal with photoset array"
			end
		end
	end

	def equal_galleries?(gallery_local, gallery_internet)
		return gallery_local == gallery_internet
	end

	def equal_photosets_arrays?(photosets_arr1, photosets_arr2)
		return photosets_arr1.sort == photosets_arr2.sort
	end

	def read_photosets(photosets_file)
		args = []
		File.open(photosets_file).each do |line|
			args.push(line.strip.to_i)
		end
		return args
	end

	def read_local_gallery(local_file)
		gallery_tmp = nil
		if local_file and File.exist?(local_file)
			  puts "Loaded from file " + local_file
				gallery_tmp = YAML.load_file(local_file)
				puts "Photosets ids: " + gallery_tmp.photosets.keys.to_s
		else
			puts "File: #{local_file} doesn't exists"
		end
		return gallery_tmp
	end
end

yaml_file = "_data/photos.yml"
photosets_file = "photosets.txt"
# collection_folder = "_photos/"

#begin
	sync = Sync.new(user_id, photosets_file,yaml_file)
#rescue => e
#	 puts 'Network connectivity issue'
#end
	 # Network is not 100% reliable
# args_photosets = read_photosets(photosets_file)

# gallery = FlickrG