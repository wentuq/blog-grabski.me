require 'flickraw'
require 'yaml'
require 'date'
require 'open-uri'
FlickRaw.api_key       = ENV['FLICKR_API_KEY']
FlickRaw.shared_secret = ENV['FLICKR_API_SECRET']
flickr.access_token    = ENV['FLICKR_ACCESS_TOKEN']
flickr.access_secret   = ENV['FLICKR_ACCESS_SECRET']
user_id = ENV["FLICKR_USER"]

$GLOBAL_APICALL = 0

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
	def initialize(id)
		info = flickr.photos.getInfo(:photo_id => id)
		$GLOBAL_APICALL += 1
		id = info['id']
		#server = info['server']
		#farm = info['farm']
		#secret = info['secret']
		@title = info['title'].strip
		@description = info['description'].strip
		#size = "_#{size}" if not size.empty?
		@page_url = info['urls'][0]['_content']
		@date_posted = info['dates']['posted'].to_i
		date_taken_raw = info['dates']['taken']
		@date_taken = DateTime.strptime(date_taken_raw, "%Y-%m-%d %H:%M:%S").strftime('%s').to_i
		@date_updated = info['dates']['lastupdate'].to_i
		@sizes = {}
		getSizes = flickr.photos.getSizes(:photo_id => id)
		$GLOBAL_APICALL += 1
		getSizes.size.each do |size|
			@sizes[size.label] = { 'width' => size.width.to_i, 'height' => size.height.to_i, 'source' => size.source  }
		@max_photo = max_photo(2048)
		end
	end

	def ==(other)
		self.class === other and
		 other.state == state
	end
	
	def state
    [@title, @description, @page_url, @date_posted, @date_updated]
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
	attr_accessor :order, :title, :description, :page_url, :date_created, :date_updated, :photos, :primaryphoto
	def initialize(user_id, set_id)
		@@order += 1
		@order = @@order
		info = flickr.photosets.getInfo(:photoset_id => set_id)
		# ?shortcut, to not repeat info['id'] ? could be @id ?
		id = info['id']
		@title = info['title'].strip
		@description = info['description'].strip
		@page_url = "https://www.flickr.com/photos/wentuq/sets/#{id}"
		@date_created = info['date_create'].to_i
		@date_updated = info['date_update'].to_i
		getPhotos = flickr.photosets.getPhotos(:photoset_id => id, :user_id => user_id)
		$GLOBAL_APICALL += 1
		@photos = {}
		getPhotos.photo.each do |photo|
			@photos[photo.id.to_i] = FlickrPhoto.new(photo.id)
			download_photo_allsizes(photo.id.to_i)
		end
		@primaryphoto = @photos[info['primary'].to_i]

		# @photos.each do |photo_id, photo|
		# 	phototitle = @title + photo_id.to_s
		# 	download_photo_allsizes(photo, phototitle)
		# end

	end

	def download_photo_allsizes(photo_id)
		phototitle = @title + photo_id.to_s
		path = "/assets/photos/"
		@photos[photo_id].sizes.each do |sid, size|
				url = size['source']
			filename =  path + phototitle.to_slug + sid.to_slug + ".jpg"
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

	def initialize(user_id, *argsets, local_file: false)
		puts "Read photosets: " + argsets.to_s

		@user_id = user_id
		@page_url = "https://www.flickr.com/photos/#{@user_id}/sets/"
		@photosets = {}
		puts "local_file: " + local_file.to_s
		open_photosets(local_file, *argsets)
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
	

	# def add_photoset(user_id, set)
	# 	@photoset[set.to_i] = FlickrSet.new(user_id, set)
	# end

	def open_photosets(local_file, *argsets)
		if local_file and File.exist?(local_file)
			  puts "Loaded from file " + local_file
				tmp = YAML.load_file(local_file)
				@photosets = tmp.photosets
				puts "Photosets ids: " + @photosets.keys.to_s
		end
		unless local_file
			puts "Loading from web"
			argsets.each { |set| @photosets[set.to_i] = FlickrSet.new(user_id, set) }
		end
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
		@photosets.each do |key, photoset|
			slug = photoset.title.to_slug
			open("#{path}#{slug}.md", 'w') { |f|
				f << "---\n"
#				f << "layout: photo_set\n"
				f << "page_url: #{photoset.page_url}\n"
				f << "set_id: #{key}\n"
				f << "title: #{photoset.title}\n"
				f << "description: #{photoset.description}\n"
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

def read_photosets(file)
	args = []
	File.open("photosets.txt").each do |line|
		args.push(line.strip)
	end
	return args
end

yaml_file = "_data/photos.yml"
photosets_file = "photosets.txt"
collection_folder = "_photos/"

args_photosets = read_photosets(photosets_file)

# gallery = FlickrGallery.new(user_id, *args_photosets)
# gallery.write_yaml(yaml_file)
# gallery.gen_collection(collection_folder)

gallery_local = FlickrGallery.new(user_id, *args_photosets, local_file: yaml_file)
puts "GLOBAL_APICALLS: " + $GLOBAL_APICALL.to_s
begin
		gallery_internet = FlickrGallery.new(user_id, *args_photosets)
		puts "GLOBAL_APICALLS: " + $GLOBAL_APICALL.to_s
rescue FlickRaw::FailedResponse => e
	puts "URATOWANO #{e.class}: #{e.message}"
rescue SocketError
  puts 'Network connectivity issue'
  # Network is not 100% reliable
else
	if gallery_local == gallery_internet
		puts "GLOBAL_APICALLS: " + $GLOBAL_APICALL.to_s
		puts "Everything synced"
	else
		gallery_internet.write_yaml(yaml_file)
		gallery_internet.gen_collection(collection_folder)
	end
end


