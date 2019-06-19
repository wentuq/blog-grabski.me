require 'flickraw'
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
	def initialize(id)
		info = flickr.photos.getInfo(:photo_id => id)
		id = info['id']
		#server = info['server']
		#farm = info['farm']
		#secret = info['secret']
		@title = info['title'].strip
		@description = info['description'].strip
		#size = "_#{size}" if not size.empty?
		#@src = "https://farm#{farm}.static.flickr.com/#{server}/#{id}_#{secret}#{size}.jpg"
		@page_url = info['urls'][0]['_content']
		@date_posted = info['dates']['posted'].to_i
		date_taken_raw = info['dates']['taken']
		@date_taken = DateTime.strptime(date_taken_raw, "%Y-%m-%d %H:%M:%S").strftime('%s').to_i
		@date_updated = info['dates']['lastupdate'].to_i
		@sizes = {}
		getSizes = flickr.photos.getSizes(:photo_id => id)
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

def download_photo_allsizes(photo, phototitle)
	path = "/assets/photos/"
	photo.sizes.each do |sid, size|
	    url = size['source']
		filename =  path + phototitle.to_slug + sid.to_slug + ".jpg"
		size['local-source'] = filename
		# filename[1..-1] need to trim / in path, otherwise wants to save to / root
		download_photo(url,filename[1..-1])

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
		@photos = {}
		getPhotos.photo.each do |photo|
			@photos[photo.id.to_i] = FlickrPhoto.new(photo.id)
			phototitle = @title + photo.id.to_s
			download_photo_allsizes(@photos[photo.id.to_i],phototitle)
		end
		@primaryphoto = @photos[info['primary'].to_i]

		# @photos.each do |photo_id, photo|
		# 	phototitle = @title + photo_id.to_s
		# 	download_photo_allsizes(photo, phototitle)
		# end

	end

	def ==(other)
		self.class === other and
		 other.state == state
	end
	
	def state
    [@title, @description, @page_url, @date_created, @date_updated, @primaryphoto]
  end
end

class FlickrGallery
	attr_accessor :page_url, :photosets, :user_id, :sorted_photos
	def initialize(user_id, *argsets)
		puts argsets
		@user_id = user_id
		@page_url = "https://www.flickr.com/photos/#{@user_id}/sets/"
		@photosets = {}
		open_photosets()
		if @photosets.empty?
			puts "#brak pliku"
			argsets.each { |set| @photosets[set.to_i] = FlickrSet.new(user_id, set) }
		end

		m_photos = {}
		@photosets.each do |k, v|
			m_photos.merge!(v.photos)
		end
		@sorted_photos = sort_photos()

	end


	def open_photosets
		if File.exist?('_data/photos.yml')
				tmp = YAML.load_file('_data/photos.yml')
				@photosets = tmp.photosets
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

	def gen_collection(path, *argsets)
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
end
